using Azure;
using Azure.Storage.Blobs.Specialized;
using System.Net;

namespace ReviewPortal;

public sealed class ExtractionWorker(CaseStore store, CloudServices cloud, PortalOptions options,
    ILogger<ExtractionWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(10));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await foreach (var blob in store.State.GetBlobsAsync(cancellationToken: stoppingToken))
                {
                    var parts = blob.Name.Split('/');
                    if (parts.Length != 2 || !Guid.TryParse(parts[0], out _) ||
                        !Guid.TryParse(Path.GetFileNameWithoutExtension(parts[1]), out var id)) continue;
                    var snapshot = await store.Load(parts[0], id, stoppingToken);
                    if (snapshot.Case.Status is not ("Pending" or "Submitting" or "Analyzing" or "Publishing")) continue;
                    await Process(snapshot, blob.Name, stoppingToken);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) when (ex is RequestFailedException or HttpRequestException or InvalidOperationException
                or System.Text.Json.JsonException or Azure.Identity.AuthenticationFailedException)
            {
                logger.LogError("Extraction scan failed: {ErrorType}. It will retry on the next scan.", ex.GetType().Name);
            }
        }
    }

    private async Task Process(CaseSnapshot snapshot, string blobName, CancellationToken ct)
    {
        var lease = store.State.GetBlobClient(blobName).GetBlobLeaseClient();
        string leaseId;
        try { leaseId = (await lease.AcquireAsync(TimeSpan.FromSeconds(60), cancellationToken: ct)).Value.LeaseId; }
        catch (RequestFailedException ex) when (ex.Status == 409) { return; }
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(ct);
        deadline.CancelAfter(TimeSpan.FromSeconds(40));
        try
        {
            snapshot = await store.Load(snapshot.Case.OwnerId, snapshot.Case.Id, deadline.Token);
            var item = snapshot.Case;
            switch (item.Status)
            {
                case "Submitting":
                    item = item with { Status = "Failed", FailureCode = "SubmissionOutcomeUnknown" };
                    break;
                case "Pending":
                    item = item with { Status = "Submitting", AnalysisStartedAt = DateTimeOffset.UtcNow };
                    await store.Save(item, snapshot.Version, deadline.Token, leaseId);
                    snapshot = await store.Load(item.OwnerId, item.Id, deadline.Token);
                    await using (var pdf = await store.Original(item.OwnerId, item.Id).OpenReadAsync(cancellationToken: deadline.Token))
                        item = item with { Status = "Analyzing", Operation = await cloud.Start(pdf, deadline.Token) };
                    break;
                case "Analyzing":
                    if (DateTimeOffset.UtcNow - (item.AnalysisStartedAt ?? item.CreatedAt) > TimeSpan.FromMinutes(30))
                    {
                        item = item with { Status = "Failed", FailureCode = "AnalysisDeadlineExceeded" };
                        break;
                    }
                    var result = await cloud.Poll(item.Operation ?? throw new InvalidOperationException("Missing operation."), deadline.Token);
                    if (!result.TryGetProperty("status", out var operationStatus))
                        throw new InvalidOperationException("Analysis response has no operation status.");
                    var status = operationStatus.GetString()?.ToLowerInvariant();
                    if (status is "running" or "notstarted") return;
                    if (status == "succeeded") await store.RetainAnalysis(item, result, deadline.Token);
                    item = status == "succeeded"
                        ? item with { Status = "NeedsReview", Fields = ReviewRules.Extract(result, options.FieldNames) }
                        : item with { Status = "Failed", FailureCode = "AnalyzerFailed" };
                    break;
                case "Publishing":
                    await store.Publish(item, deadline.Token);
                    item = item with { Status = "Approved" };
                    break;
                default: return;
            }
            await store.Save(item, snapshot.Version, deadline.Token, leaseId);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            logger.LogWarning("Extraction step exceeded its deadline; durable state will be inspected on the next scan.");
        }
        catch (Exception ex) when (ex is HttpRequestException or RequestFailedException or InvalidOperationException
            or System.Text.Json.JsonException or Azure.Identity.AuthenticationFailedException)
        {
            logger.LogError("Extraction step failed: {ErrorType}. No content or cloud response is logged.", ex.GetType().Name);
            if (ex is HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests or HttpStatusCode.ServiceUnavailable } ||
                ex is RequestFailedException { Status: 409 or 412 or 429 or 503 }) return;
            var current = await store.Load(snapshot.Case.OwnerId, snapshot.Case.Id, ct);
            await store.Save(current.Case with { Status = "Failed", FailureCode = "ExtractionOrPublicationFailed" },
                current.Version, ct, leaseId);
        }
        finally
        {
            try { await lease.ReleaseAsync(cancellationToken: CancellationToken.None); }
            catch (RequestFailedException ex) when (ex.Status is 409 or 412)
            { logger.LogWarning("Extraction lease expired before release."); }
        }
    }
}
