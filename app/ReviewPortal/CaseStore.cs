using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using System.Security.Cryptography;
using System.Text.Json;

namespace ReviewPortal;

public sealed record CasePage(IReadOnlyList<ReviewCase> Items, string? ContinuationToken);

public sealed class CaseStore(BlobServiceClient blobs, PortalOptions options, ILogger<CaseStore>? logger = null)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public BlobContainerClient State => blobs.GetBlobContainerClient(options.StateContainer);
    private BlobClient StateBlob(string owner, Guid id) => State.GetBlobClient($"{owner}/{id:D}.json");
    public BlobClient Original(string owner, Guid id) =>
        blobs.GetBlobContainerClient(options.OriginalContainer).GetBlobClient($"{owner}/{id:D}.pdf");

    public async Task<CaseSnapshot> Load(string owner, Guid id, CancellationToken ct)
    {
        var response = await StateBlob(owner, id).DownloadContentAsync(ct);
        var item = response.Value.Content.ToObjectFromJson<ReviewCase>(Json) ??
            throw new InvalidOperationException("Invalid stored case.");
        if (item.Id != id || item.OwnerId != owner)
            throw new InvalidOperationException("Stored case identity does not match its path.");
        if (item.Status is not ("Pending" or "Submitting" or "Analyzing" or "NeedsReview" or "Publishing" or "Approved" or "Failed") ||
            item.Fields?.Any(field => field is null || string.IsNullOrWhiteSpace(field.Name) ||
                field.Value is null || field.OriginalValue is null) == true ||
            item.Fields is not null && item.Fields.Select(field => field.Name).Distinct().Count() != item.Fields.Count)
            throw new InvalidOperationException("Stored case has invalid state or fields.");
        if (item.Status is "Publishing" or "Approved") ValidateReviewed(item);
        return new(item, response.Value.Details.ETag.ToString());
    }

    public async Task Save(ReviewCase item, string? version, CancellationToken ct, string? leaseId = null)
    {
        if (!Guid.TryParse(item.OwnerId, out var owner) || owner.ToString("D") != item.OwnerId || item.Id == Guid.Empty)
            throw new InvalidOperationException("Invalid case identity.");
        if (version is not null)
        {
            var previous = await Load(item.OwnerId, item.Id, ct);
            if (previous.Version != version) throw new RequestFailedException(412, "Case changed.");
            if (previous.Case.ReviewedAt.HasValue &&
                (!FrozenReviewEquals(previous.Case, item) || previous.Case.Status == "Approved" ||
                 item.Status is not ("Publishing" or "Approved" or "Failed")))
                throw new InvalidOperationException("Reviewed case content is frozen.");
        }
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

    public async Task<CasePage> List(string owner, int pageSize, string? continuationToken, CancellationToken ct)
    {
        if (pageSize is < 1 or > 100) throw new ArgumentOutOfRangeException(nameof(pageSize));
        var items = new List<ReviewCase>();
        await foreach (var page in State.GetBlobsAsync(prefix: $"{owner}/", cancellationToken: ct)
            .AsPages(continuationToken, pageSize))
        {
            foreach (var blob in page.Values)
            {
                var parts = blob.Name.Split('/');
                if (parts.Length != 2 || !parts[1].EndsWith(".json", StringComparison.Ordinal) ||
                    !Guid.TryParse(Path.GetFileNameWithoutExtension(parts[1]), out var id)) continue;
                try { items.Add((await Load(owner, id, ct)).Case); }
                catch (Exception ex) when (ex is RequestFailedException or InvalidOperationException or JsonException)
                {
                    logger?.LogError("Case list record {CaseId} failed: {ErrorType}.", id, ex.GetType().Name);
                    // Return an owner-scoped placeholder rather than hiding a corrupt record.
                    items.Add(new(id, owner, "application.pdf", DateTimeOffset.MinValue, "Failed",
                        FailureCode: "StoredCaseUnreadable"));
                }
            }
            return new(items.OrderByDescending(c => c.CreatedAt).ToArray(),
                string.IsNullOrEmpty(page.ContinuationToken) ? null : page.ContinuationToken);
        }
        return new(items, null);
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
        ValidateReviewed(item);
        if (item.Status != "Publishing") throw new InvalidOperationException("Case is not publishing.");
        await using var original = await Original(item.OwnerId, item.Id).OpenReadAsync(cancellationToken: ct);
        if (original.Length > options.MaxUploadBytes)
            throw new InvalidOperationException("Original exceeds the configured upload limit.");
        var originalHash = Convert.ToHexStringLower(await SHA256.HashDataAsync(original, ct));
        if (originalHash != item.OriginalSha256)
            throw new InvalidOperationException("Original content conflicts with the reviewed hash.");
        original.Position = 0;
        var reviewHash = Convert.ToHexStringLower(SHA256.HashData(
            BinaryData.FromObjectAsJson(item with { Status = "Publishing", FailureCode = null }, Json).ToArray()));
        var metadata = new Dictionary<string, string>
        {
            ["case_id"] = item.Id.ToString("D"), ["owner_id"] = item.OwnerId,
            ["original_sha256"] = originalHash, ["review_sha256"] = reviewHash,
            ["reviewed_at"] = item.ReviewedAt!.Value.ToString("O"), ["reviewer_id"] = item.ReviewerId!
        };
        var evidence = new
        {
            id = $"review-{item.Id:D}", case_id = item.Id.ToString("D"), owner_id = item.OwnerId,
            title = "Human-validated extraction", page_from = 0, page_to = 0,
            content = string.Join("\n", item.Fields!.Select(f => $"{f.Name}: {f.Value}")),
            source_kind = "reviewedFields", original_sha256 = originalHash, review_sha256 = reviewHash,
            reviewed_at = item.ReviewedAt, reviewer_id = item.ReviewerId
        };
        var evidenceData = BinaryData.FromObjectAsJson(evidence);
        await using var evidenceStream = evidenceData.ToStream();
        await PublishOnce(blobs.GetBlobContainerClient(options.EvidenceContainer).GetBlobClient($"{item.Id:D}.json"),
            evidenceStream, Convert.ToHexStringLower(SHA256.HashData(evidenceData.ToArray())),
            "application/json", metadata, ct);
        await PublishOnce(blobs.GetBlobContainerClient(options.ApprovedContainer).GetBlobClient($"{item.Id:D}.pdf"),
            original, originalHash, "application/pdf", metadata, ct);
    }

    public static void ValidateReviewed(ReviewCase item)
    {
        if (!item.ReviewedAt.HasValue || item.ReviewerId != item.OwnerId || item.Fields is null ||
            item.Fields.Count == 0 || item.Fields.Any(f => !f.Reviewed) ||
            item.OriginalSha256 is not { Length: 64 } || item.OriginalSha256.Any(c => !char.IsAsciiHexDigit(c)))
            throw new InvalidOperationException("Unreviewed content cannot be published.");
    }

    private static bool FrozenReviewEquals(ReviewCase previous, ReviewCase item) =>
        BinaryData.FromObjectAsJson(previous with { Status = "", FailureCode = null }, Json).ToString() ==
        BinaryData.FromObjectAsJson(item with { Status = "", FailureCode = null }, Json).ToString();

    private static async Task PublishOnce(BlobClient blob, Stream content, string hash, string contentType,
        Dictionary<string, string> metadata, CancellationToken ct)
    {
        try
        {
            await blob.UploadAsync(content, new BlobUploadOptions
            {
                Conditions = new BlobRequestConditions { IfNoneMatch = ETag.All },
                Metadata = new Dictionary<string, string>(metadata)
                    { ["source_kind"] = contentType == "application/pdf" ? "original" : "reviewedFields" },
                HttpHeaders = new BlobHttpHeaders { ContentType = contentType }
            }, ct);
        }
        catch (RequestFailedException ex) when (ex.Status is 409 or 412)
        {
            var properties = await blob.GetPropertiesAsync(cancellationToken: ct);
            if (properties.Value.ContentType != contentType ||
                !properties.Value.Metadata.TryGetValue("source_kind", out var sourceKind) ||
                sourceKind != (contentType == "application/pdf" ? "original" : "reviewedFields") ||
                metadata.Any(pair => !properties.Value.Metadata.TryGetValue(pair.Key, out var value) || value != pair.Value))
                throw new InvalidOperationException("Published review metadata conflicts with the frozen review.");
            await using var existing = await blob.OpenReadAsync(new BlobOpenReadOptions(false)
            {
                Conditions = new BlobRequestConditions { IfMatch = properties.Value.ETag }
            }, ct);
            if (Convert.ToHexStringLower(await SHA256.HashDataAsync(existing, ct)) != hash)
                throw new InvalidOperationException("Published content conflicts with the frozen review.");
        }
    }
}
