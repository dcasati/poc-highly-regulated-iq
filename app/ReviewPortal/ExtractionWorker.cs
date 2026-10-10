using Azure;
using Azure.Storage.Blobs.Specialized;
using System.Net;

namespace ReviewPortal;

public sealed class WorkerActivity
{
    private readonly object sync = new();
    private DateTimeOffset? heartbeat, lastSuccessfulScan, lastErrorAt;
    private string? lastErrorType;
    private bool scanFailed;

    public object Snapshot()
    {
        lock (sync) return new { heartbeat, lastSuccessfulScan, lastErrorAt, lastErrorType,
            status = heartbeat is null ? "starting" :
                DateTimeOffset.UtcNow - heartbeat > TimeSpan.FromMinutes(2) ? "stale" :
                lastErrorType is not null ? "degraded" : "active" };
    }
    public void Begin() { lock (sync) { heartbeat = DateTimeOffset.UtcNow; scanFailed = false; } }
    public void Touch() { lock (sync) heartbeat = DateTimeOffset.UtcNow; }
    public void Error(Exception ex)
    {
        lock (sync) { scanFailed = true; lastErrorAt = DateTimeOffset.UtcNow; lastErrorType = ex.GetType().Name; }
    }
    public void Complete()
    {
        lock (sync)
        {
            heartbeat = DateTimeOffset.UtcNow;
            if (!scanFailed) { lastSuccessfulScan = heartbeat; lastErrorType = null; }
        }
    }
}

public sealed class ExtractionWorker(CaseStore store, CloudServices cloud, PortalOptions options,
    ILogger<ExtractionWorker> logger, WorkerActivity activity) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(10));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await ScanOnce(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) when (Recoverable(ex) || ex is OperationCanceledException)
            {
                activity.Error(ex);
                logger.LogError("Extraction scan failed: {ErrorType}. It will retry on the next scan.", ex.GetType().Name);
            }
        }
    }

    public async Task ScanOnce(CancellationToken ct)
    {
        activity.Begin();
        await foreach (var blob in store.State.GetBlobsAsync(cancellationToken: ct))
        {
            var parts = blob.Name.Split('/');
            if (parts.Length != 2 || !Guid.TryParse(parts[0], out var owner) || owner.ToString("D") != parts[0] ||
                !parts[1].EndsWith(".json", StringComparison.Ordinal) ||
                !Guid.TryParse(Path.GetFileNameWithoutExtension(parts[1]), out var id)) continue;
            activity.Touch();
            try
            {
                var snapshot = await store.Load(parts[0], id, ct);
                if (snapshot.Case.Status is not ("Pending" or "Submitting" or "Analyzing" or "Publishing")) continue;
                await Process(snapshot, blob.Name, ct);
            }
            catch (Exception ex) when (Recoverable(ex) || ex is OperationCanceledException && !ct.IsCancellationRequested)
            {
                activity.Error(ex);
                logger.LogError("Extraction record {CaseId} failed: {ErrorType}. Later records will still be scanned.",
                    id, ex.GetType().Name);
            }
        }
        activity.Complete();
    }

    private static bool Recoverable(Exception ex) =>
        ex is RequestFailedException or HttpRequestException or InvalidOperationException or IOException
            or System.Text.Json.JsonException or Azure.Identity.AuthenticationFailedException;

    private async Task Process(CaseSnapshot snapshot, string blobName, CancellationToken ct)
    {
        var lease = store.State.GetBlobClient(blobName).GetBlobLeaseClient();
        string leaseId;
        using var acquireDeadline = CancellationTokenSource.CreateLinkedTokenSource(ct);
        acquireDeadline.CancelAfter(TimeSpan.FromSeconds(5));
        try { leaseId = (await lease.AcquireAsync(TimeSpan.FromSeconds(60), cancellationToken: acquireDeadline.Token)).Value.LeaseId; }
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
            activity.Error(new TimeoutException());
            logger.LogWarning("Extraction record {CaseId} exceeded its deadline; durable state will be inspected on the next scan.",
                snapshot.Case.Id);
        }
        catch (Exception ex) when (Recoverable(ex))
        {
            activity.Error(ex);
            logger.LogError("Extraction record {CaseId} failed: {ErrorType}. No content or cloud response is logged.",
                snapshot.Case.Id, ex.GetType().Name);
            if (ex is HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests or HttpStatusCode.ServiceUnavailable } ||
                ex is RequestFailedException { Status: 409 or 412 or 429 or 503 }) return;
            var current = await store.Load(snapshot.Case.OwnerId, snapshot.Case.Id, ct);
            // A submission can succeed remotely even when its response is lost.
            if (current.Case.Status == "Submitting") return;
            await store.Save(current.Case with { Status = "Failed", FailureCode = "ExtractionOrPublicationFailed" },
                current.Version, ct, leaseId);
        }
        finally
        {
            using var releaseDeadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try { await lease.ReleaseAsync(cancellationToken: releaseDeadline.Token); }
            catch (Exception ex) when (Recoverable(ex) || ex is OperationCanceledException)
            {
                activity.Error(ex);
                logger.LogWarning("Extraction record {CaseId} lease release failed: {ErrorType}. The bounded lease will expire.",
                    snapshot.Case.Id, ex.GetType().Name);
            }
        }
    }
}
