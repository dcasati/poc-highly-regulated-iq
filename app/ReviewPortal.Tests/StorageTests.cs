using Azure;
using Azure.Core.Pipeline;
using Azure.Storage.Blobs;
using ReviewPortal;
using System.Net;
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

    private static ReviewCase Case() => new(Guid.NewGuid(), "11111111-1111-1111-1111-111111111111",
        "application.pdf", DateTimeOffset.UtcNow, "Pending");
    private static CaseStore Store(BlobHandler handler)
    {
        var options = new BlobClientOptions { Transport = new HttpClientTransport(new HttpClient(handler)) };
        options.Retry.MaxRetries = 0;
        var service = new BlobServiceClient(new Uri(ReviewTests.Options.BlobEndpoint), options);
        return new CaseStore(service, ReviewTests.Options);
    }

    private sealed class BlobHandler : HttpMessageHandler
    {
        private readonly Dictionary<string, (byte[] Data, string Etag)> blobs = [];
        public int Writes { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var path = request.RequestUri!.AbsolutePath;
            var exists = blobs.TryGetValue(path, out var stored);
            if (request.Method == HttpMethod.Put)
            {
                if ((request.Headers.IfNoneMatch.Any() && exists) ||
                    (request.Headers.IfMatch.Any() && (!exists || request.Headers.IfMatch.Single().Tag != stored.Etag)))
                    return Error(HttpStatusCode.PreconditionFailed, "ConditionNotMet");
                stored = (await request.Content!.ReadAsByteArrayAsync(ct), $"\"version-{++Writes}\"");
                blobs[path] = stored;
                var response = new HttpResponseMessage(HttpStatusCode.Created);
                response.Headers.ETag = new(stored.Etag);
                response.Headers.Add("x-ms-request-id", Guid.NewGuid().ToString());
                return response;
            }
            if (request.Method == HttpMethod.Get && exists)
            {
                var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(stored.Data) };
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
