using Azure;
using Azure.Core.Pipeline;
using Azure.Storage.Blobs;
using ReviewPortal;
using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using Xunit;

namespace ReviewPortal.Tests;

public class StorageTests
{
    [Fact]
    public async Task DurableStateUsesConditionalWritesAndOwnerSpecificPaths()
    {
        var handler = new BlobHandler();
        var store = Store(handler);
        var item = Case();
        await store.Save(item, null, CancellationToken.None);
        var saved = await store.Load(item.OwnerId, item.Id, CancellationToken.None);
        Assert.Equal(item, saved.Case);
        await store.Save(item with { Status = "Analyzing" }, saved.Version, CancellationToken.None);
        var stale = await Assert.ThrowsAsync<RequestFailedException>(() =>
            store.Save(item with { Status = "Approved" }, saved.Version, CancellationToken.None));
        Assert.Equal(412, stale.Status);
        var foreign = await Assert.ThrowsAsync<RequestFailedException>(() =>
            store.Load("33333333-3333-3333-3333-333333333333", item.Id, CancellationToken.None));
        Assert.Equal(404, foreign.Status);
        var duplicate = await Assert.ThrowsAsync<RequestFailedException>(() => store.Save(item, null, CancellationToken.None));
        Assert.Equal(412, duplicate.Status);
    }

    [Fact]
    public async Task UnreviewedCasesCannotBePublished()
    {
        var handler = new BlobHandler();
        await Assert.ThrowsAsync<InvalidOperationException>(() => Store(handler).Publish(Case(), CancellationToken.None));
        Assert.Equal(0, handler.Writes);
    }

    [Fact]
    public async Task RetainedAnalysisAcceptsEquivalentJsonButRejectsChangedResults()
    {
        var handler = new BlobHandler();
        var store = Store(handler);
        var item = Case() with { Operation = "https://foundry.example/contentunderstanding/operations/test" };
        using var original = JsonDocument.Parse("""{"status":"succeeded","result":{"value":1}}""");
        using var equivalent = JsonDocument.Parse("""{ "result": { "value": 1 }, "status": "succeeded" }""");
        using var changed = JsonDocument.Parse("""{"status":"succeeded","result":{"value":2}}""");
        await store.RetainAnalysis(item, original.RootElement, CancellationToken.None);
        await store.RetainAnalysis(item, equivalent.RootElement, CancellationToken.None);
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.RetainAnalysis(item, changed.RootElement, CancellationToken.None));
        Assert.Equal(1, handler.Writes);
    }

    [Fact]
    public async Task PersistedOwnerAndIdMustMatchRequestedPath()
    {
        var handler = new BlobHandler();
        var store = Store(handler);
        var item = Case();
        foreach (var changed in new[] { item with { Id = Guid.NewGuid() }, item with { OwnerId = Guid.NewGuid().ToString("D") } })
        {
            handler.Seed($"/review-state/{item.OwnerId}/{item.Id:D}.json",
                JsonSerializer.SerializeToUtf8Bytes(changed, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
            await Assert.ThrowsAsync<InvalidOperationException>(() => store.Load(item.OwnerId, item.Id, CancellationToken.None));
        }
    }

    [Fact]
    public async Task PublicationIsRepeatableAfterPartialWriteAndRejectsContentConflict()
    {
        var handler = new BlobHandler();
        var store = Store(handler);
        var item = Reviewed();
        handler.Seed($"/originals/{item.OwnerId}/{item.Id:D}.pdf", Pdf);
        handler.FailNextWritePath = $"/approved/{item.Id:D}.pdf";
        await Assert.ThrowsAsync<RequestFailedException>(() => store.Publish(item, CancellationToken.None));
        Assert.Equal(1, handler.Writes);
        await store.Publish(item, CancellationToken.None);
        Assert.Equal(2, handler.Writes);
        await store.Publish(item, CancellationToken.None);
        Assert.Equal(2, handler.Writes);
        handler.Corrupt($"/approved/{item.Id:D}.pdf", "%PDF-changed"u8.ToArray());
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.Publish(item, CancellationToken.None));
        Assert.Equal(2, handler.Writes);
    }

    [Fact]
    public async Task OriginalHashAndReviewedRevisionConflictsFailClosed()
    {
        var handler = new BlobHandler();
        var store = Store(handler);
        var item = Reviewed();
        handler.Seed($"/originals/{item.OwnerId}/{item.Id:D}.pdf", "%PDF-changed"u8.ToArray());
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.Publish(item, CancellationToken.None));
        Assert.Equal(0, handler.Writes);
        handler.Seed($"/originals/{item.OwnerId}/{item.Id:D}.pdf", Pdf);
        await store.Publish(item, CancellationToken.None);
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.Publish(item with
        { Fields = [item.Fields![0] with { Value = "Changed after review" }] }, CancellationToken.None));
        Assert.Equal(2, handler.Writes);
    }

    [Fact]
    public async Task ReviewedStateCannotChangeFieldsOrReturnToExtraction()
    {
        var handler = new BlobHandler();
        var store = Store(handler);
        var item = Reviewed();
        await store.Save(item, null, CancellationToken.None);
        var snapshot = await store.Load(item.OwnerId, item.Id, CancellationToken.None);
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.Save(item with
            { Fields = [item.Fields![0] with { Value = "Injected" }] }, snapshot.Version, CancellationToken.None));
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.Save(item with
            { Status = "Pending" }, snapshot.Version, CancellationToken.None));
        await store.Save(item with { Status = "Approved" }, snapshot.Version, CancellationToken.None);
        snapshot = await store.Load(item.OwnerId, item.Id, CancellationToken.None);
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.Save(item with
            { Status = "Failed" }, snapshot.Version, CancellationToken.None));
    }

    [Fact]
    public async Task ListIsCappedAndReportsCorruptRecordsWithoutCrossingOwner()
    {
        var handler = new BlobHandler();
        var store = Store(handler);
        var first = Case();
        var second = Case();
        await store.Save(first, null, CancellationToken.None);
        await store.Save(second, null, CancellationToken.None);
        handler.Corrupt($"/review-state/{first.OwnerId}/{first.Id:D}.json", "not json"u8.ToArray());
        await store.Save(Case() with { OwnerId = Guid.NewGuid().ToString("D") }, null, CancellationToken.None);
        var page = await store.List(first.OwnerId, 1, null, CancellationToken.None);
        Assert.Single(page.Items);
        Assert.NotNull(page.ContinuationToken);
        var next = await store.List(first.OwnerId, 1, page.ContinuationToken, CancellationToken.None);
        Assert.Single(next.Items);
        Assert.Null(next.ContinuationToken);
        Assert.All(page.Items.Concat(next.Items), item => Assert.Equal(first.OwnerId, item.OwnerId));
        Assert.Contains(page.Items.Concat(next.Items), item => item.FailureCode == "StoredCaseUnreadable");
    }

    internal static readonly byte[] Pdf = "%PDF-synthetic"u8.ToArray();
    internal static ReviewCase Reviewed() => Case() with
    {
        Status = "Publishing", ReviewerId = "11111111-1111-1111-1111-111111111111", ReviewedAt = DateTimeOffset.UtcNow,
        OriginalSha256 = Convert.ToHexStringLower(SHA256.HashData(Pdf)),
        Fields = [new("ApplicantName", "Synthetic", "Reviewed", .5, null, true)]
    };
    internal static ReviewCase Case() => new(Guid.NewGuid(), "11111111-1111-1111-1111-111111111111",
        "application.pdf", DateTimeOffset.UtcNow, "Pending");
    internal static CaseStore Store(BlobHandler handler)
    {
        var options = new BlobClientOptions { Transport = new HttpClientTransport(new HttpClient(handler)) };
        options.Retry.MaxRetries = 0;
        var service = new BlobServiceClient(new Uri(ReviewTests.Options.BlobEndpoint), options);
        return new CaseStore(service, ReviewTests.Options);
    }

    internal sealed class BlobHandler : HttpMessageHandler
    {
        private readonly System.Collections.Concurrent.ConcurrentDictionary<string,
            (byte[] Data, string Etag, Dictionary<string, string> Metadata, string ContentType)> blobs = [];
        private int writes, originalUploads;
        public int Writes => writes;
        public string? FailNextWritePath { get; set; }
        public bool FailLeaseRelease { get; set; }
        public bool BlockOriginalUploads { get; set; }
        public TaskCompletionSource TwoOriginalUploads { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource ReleaseOriginalUploads { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public void Seed(string path, byte[] content) => blobs[path] = (content, "\"seed\"", [], "application/octet-stream");
        public void Corrupt(string path, byte[] content) => blobs[path] = blobs[path] with { Data = content };
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var path = request.RequestUri!.AbsolutePath;
            var query = System.Web.HttpUtility.ParseQueryString(request.RequestUri.Query);
            var exists = blobs.TryGetValue(path, out var stored);
            if (query["comp"] == "list")
            {
                var prefix = query["prefix"] ?? "";
                var names = blobs.Keys.Where(key => key.StartsWith(path.TrimEnd('/') + "/" + prefix, StringComparison.Ordinal))
                    .Select(key => key[(path.Length + 1)..]).Order().ToArray();
                var offset = int.TryParse(query["marker"], out var marker) ? marker : 0;
                var size = int.TryParse(query["maxresults"], out var max) ? max : 5000;
                var next = offset + size < names.Length ? (offset + size).ToString() : "";
                return new(HttpStatusCode.OK)
                {
                    Content = new StringContent("<EnumerationResults><Blobs>" +
                        string.Join("", names.Skip(offset).Take(size).Select(name =>
                            $"<Blob><Name>{System.Security.SecurityElement.Escape(name)}</Name><Properties><BlobType>BlockBlob</BlobType><Content-Length>1</Content-Length></Properties></Blob>")) +
                        $"</Blobs><NextMarker>{next}</NextMarker></EnumerationResults>", System.Text.Encoding.UTF8, "application/xml")
                };
            }
            if (query["comp"] == "lease")
            {
                if (request.Headers.GetValues("x-ms-lease-action").Single() == "release" && FailLeaseRelease)
                    return Error(HttpStatusCode.ServiceUnavailable, "ServerBusy");
                var response = new HttpResponseMessage(request.Headers.GetValues("x-ms-lease-action").Single() == "release"
                    ? HttpStatusCode.OK : HttpStatusCode.Created);
                response.Headers.Add("x-ms-lease-id", Guid.NewGuid().ToString());
                return response;
            }
            if (request.Method == HttpMethod.Put)
            {
                if (BlockOriginalUploads && path.StartsWith("/originals/", StringComparison.Ordinal))
                {
                    if (Interlocked.Increment(ref originalUploads) == 2) TwoOriginalUploads.TrySetResult();
                    await ReleaseOriginalUploads.Task.WaitAsync(ct);
                }
                if (FailNextWritePath == path)
                { FailNextWritePath = null; return Error(HttpStatusCode.ServiceUnavailable, "ServerBusy"); }
                if ((request.Headers.IfNoneMatch.Any() && exists) ||
                    (request.Headers.IfMatch.Any() && (!exists || request.Headers.IfMatch.Single().Tag != stored.Etag)))
                    return Error(HttpStatusCode.PreconditionFailed, "ConditionNotMet");
                stored = (await request.Content!.ReadAsByteArrayAsync(ct), $"\"version-{Interlocked.Increment(ref writes)}\"",
                    request.Headers.Where(h => h.Key.StartsWith("x-ms-meta-", StringComparison.OrdinalIgnoreCase))
                        .ToDictionary(h => h.Key[10..], h => h.Value.Single(), StringComparer.OrdinalIgnoreCase),
                    request.Headers.TryGetValues("x-ms-blob-content-type", out var types) ? types.Single() : "application/octet-stream");
                blobs[path] = stored;
                var response = new HttpResponseMessage(HttpStatusCode.Created);
                response.Headers.ETag = new(stored.Etag);
                response.Headers.Add("x-ms-request-id", Guid.NewGuid().ToString());
                return response;
            }
            if ((request.Method == HttpMethod.Get || request.Method == HttpMethod.Head) && exists)
            {
                var range = request.Headers.TryGetValues("x-ms-range", out var ranges)
                    ? System.Net.Http.Headers.RangeHeaderValue.Parse(ranges.Single()).Ranges.Single()
                    : request.Headers.Range?.Ranges.Single();
                var data = request.Method == HttpMethod.Head ? [] :
                    range is null ? stored.Data : stored.Data.Skip((int)(range.From ?? 0)).Take((int)Math.Min(stored.Data.Length, (range.To ?? stored.Data.Length - 1) - (range.From ?? 0) + 1)).ToArray();
                var response = new HttpResponseMessage(range is null ? HttpStatusCode.OK : HttpStatusCode.PartialContent)
                    { Content = new ByteArrayContent(data) };
                if (request.Method == HttpMethod.Head) response.Content.Headers.ContentLength = stored.Data.Length;
                if (range is not null) response.Content.Headers.ContentRange = new(range.From ?? 0,
                    (range.From ?? 0) + data.Length - 1, stored.Data.Length);
                response.Content.Headers.ContentType = new(stored.ContentType);
                foreach (var pair in stored.Metadata) response.Headers.Add("x-ms-meta-" + pair.Key, pair.Value);
                response.Headers.ETag = new(stored.Etag);
                response.Headers.Add("x-ms-blob-type", "BlockBlob");
                response.Headers.Add("x-ms-request-id", Guid.NewGuid().ToString());
                response.Content.Headers.LastModified = DateTimeOffset.UtcNow;
                return response;
            }
            return Error(HttpStatusCode.NotFound, "BlobNotFound");
        }
        private static HttpResponseMessage Error(HttpStatusCode code, string name)
        {
            var response = new HttpResponseMessage(code)
            { Content = new StringContent($"<Error><Code>{name}</Code><Message>Synthetic storage response.</Message></Error>") };
            response.Headers.Add("x-ms-error-code", name);
            return response;
        }
    }
}
