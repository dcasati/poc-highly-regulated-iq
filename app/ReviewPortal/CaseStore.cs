using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using System.Text.Json;

namespace ReviewPortal;

public sealed class CaseStore(BlobServiceClient blobs, PortalOptions options)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public BlobContainerClient State => blobs.GetBlobContainerClient(options.StateContainer);
    private BlobClient StateBlob(string owner, Guid id) => State.GetBlobClient($"{owner}/{id:D}.json");
    public BlobClient Original(string owner, Guid id) =>
        blobs.GetBlobContainerClient(options.OriginalContainer).GetBlobClient($"{owner}/{id:D}.pdf");

    public async Task<CaseSnapshot> Load(string owner, Guid id, CancellationToken ct)
    {
        var response = await StateBlob(owner, id).DownloadContentAsync(ct);
        return new(response.Value.Content.ToObjectFromJson<ReviewCase>(Json) ??
            throw new InvalidOperationException("Invalid stored case."), response.Value.Details.ETag.ToString());
    }

    public async Task Save(ReviewCase item, string? version, CancellationToken ct, string? leaseId = null)
    {
        await StateBlob(item.OwnerId, item.Id).UploadAsync(BinaryData.FromObjectAsJson(item, Json),
            new BlobUploadOptions
            {
                Conditions = new BlobRequestConditions
                {
                    IfMatch = version is null ? default : new ETag(version),
                    IfNoneMatch = version is null ? ETag.All : default,
                    LeaseId = leaseId
                },
                HttpHeaders = new BlobHttpHeaders { ContentType = "application/json" }
            }, ct);
    }

    public async Task<IReadOnlyList<ReviewCase>> List(string owner, CancellationToken ct)
    {
        var items = new List<ReviewCase>();
        await foreach (var blob in State.GetBlobsAsync(prefix: $"{owner}/", cancellationToken: ct))
        {
            if (blob.Name.Split('/').Length != 2) continue;
            var response = await State.GetBlobClient(blob.Name).DownloadContentAsync(ct);
            items.Add(response.Value.Content.ToObjectFromJson<ReviewCase>(Json) ??
                throw new InvalidOperationException("Invalid stored case."));
        }
        return items.OrderByDescending(c => c.CreatedAt).ToArray();
    }

    public async Task RetainAnalysis(ReviewCase item, JsonElement result, CancellationToken ct)
    {
        var path = $"{item.OwnerId}/extractions/{item.Id:D}/{Uri.EscapeDataString(item.Operation ?? throw new InvalidOperationException("Missing operation identity."))}.json";
        var blob = State.GetBlobClient(path);
        try
        {
            await blob.UploadAsync(BinaryData.FromString(result.GetRawText()), new BlobUploadOptions
            {
                Conditions = new BlobRequestConditions { IfNoneMatch = ETag.All },
                HttpHeaders = new BlobHttpHeaders { ContentType = "application/json" }
            }, ct);
        }
        catch (RequestFailedException ex) when (ex.Status == 409 || ex.Status == 412)
        {
            var existing = await blob.DownloadContentAsync(ct);
            if (!JsonElement.DeepEquals(existing.Value.Content.ToObjectFromJson<JsonElement>(), result))
                throw new InvalidOperationException("Stored extraction conflicts with the completed operation.");
        }
    }

    public async Task Publish(ReviewCase item, CancellationToken ct)
    {
        if (item.Status != "Publishing" || item.Fields is null || item.Fields.Any(f => !f.Reviewed))
            throw new InvalidOperationException("Unreviewed content cannot be published.");
        var evidence = new
        {
            id = $"review-{item.Id:D}", case_id = item.Id.ToString("D"), owner_id = item.OwnerId,
            title = "Human-validated extraction", page_from = 0, page_to = 0,
            content = string.Join("\n", item.Fields.Select(f => $"{f.Name}: {f.Value}")),
            source_kind = "reviewedFields"
        };
        await blobs.GetBlobContainerClient(options.EvidenceContainer).GetBlobClient($"{item.Id:D}.json")
            .UploadAsync(BinaryData.FromObjectAsJson(evidence), overwrite: true, cancellationToken: ct);
        await using var original = await Original(item.OwnerId, item.Id).OpenReadAsync(cancellationToken: ct);
        await blobs.GetBlobContainerClient(options.ApprovedContainer).GetBlobClient($"{item.Id:D}.pdf")
            .UploadAsync(original, new BlobUploadOptions
            {
                Metadata = new Dictionary<string, string>
                {
                    ["case_id"] = item.Id.ToString("D"), ["owner_id"] = item.OwnerId, ["source_kind"] = "original"
                },
                HttpHeaders = new BlobHttpHeaders { ContentType = "application/pdf" }
            }, ct);
    }
}
