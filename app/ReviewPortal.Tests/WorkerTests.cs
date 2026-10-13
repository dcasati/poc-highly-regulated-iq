using Azure.Core;
using Microsoft.Extensions.Logging.Abstractions;
using ReviewPortal;
using System.Net;
using System.Text.Json;
using Xunit;

namespace ReviewPortal.Tests;

public sealed class WorkerTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task CorruptRecordDoesNotBlockLaterRecordAndIsVisibleInActivity(bool malformedFields)
    {
        var handler = new StorageTests.BlobHandler();
        var store = StorageTests.Store(handler);
        var corrupt = StorageTests.Case() with { Id = Guid.Parse("00000000-0000-0000-0000-000000000001") };
        var recover = StorageTests.Case() with
            { Id = Guid.Parse("00000000-0000-0000-0000-000000000002"), Status = "Submitting" };
        await store.Save(corrupt, null, CancellationToken.None);
        handler.Corrupt($"/review-state/{corrupt.OwnerId}/{corrupt.Id:D}.json", malformedFields
            ? JsonSerializer.SerializeToUtf8Bytes(corrupt with { Fields = [null!] }, new JsonSerializerOptions(JsonSerializerDefaults.Web))
            : "not json"u8.ToArray());
        await store.Save(recover, null, CancellationToken.None);
        var activity = new WorkerActivity();
        await Worker(store, activity).ScanOnce(CancellationToken.None);
        Assert.Equal("SubmissionOutcomeUnknown", (await store.Load(recover.OwnerId, recover.Id, CancellationToken.None)).Case.FailureCode);
        var status = JsonSerializer.SerializeToElement(activity.Snapshot());
        Assert.Equal("degraded", status.GetProperty("status").GetString());
        Assert.Equal(malformedFields ? "InvalidOperationException" : "JsonException",
            status.GetProperty("lastErrorType").GetString());
        Assert.Equal(JsonValueKind.Null, status.GetProperty("lastSuccessfulScan").ValueKind);
    }

    [Fact]
    public async Task LeaseReleaseOutageDoesNotTerminateScanOrPreventLaterWork()
    {
        var handler = new StorageTests.BlobHandler { FailLeaseRelease = true };
        var store = StorageTests.Store(handler);
        var first = StorageTests.Case() with { Status = "Submitting" };
        var second = StorageTests.Case() with { Status = "Submitting" };
        await store.Save(first, null, CancellationToken.None);
        await store.Save(second, null, CancellationToken.None);
        var activity = new WorkerActivity();
        await Worker(store, activity).ScanOnce(CancellationToken.None);
        foreach (var item in new[] { first, second })
            Assert.Equal("Failed", (await store.Load(item.OwnerId, item.Id, CancellationToken.None)).Case.Status);
        Assert.Equal("degraded", JsonSerializer.SerializeToElement(activity.Snapshot()).GetProperty("status").GetString());
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task LostSubmissionResponseIsDurableAndDoesNotAutomaticallyResubmit(bool timeout)
    {
        var handler = new StorageTests.BlobHandler();
        var store = StorageTests.Store(handler);
        var item = StorageTests.Case();
        await store.Save(item, null, CancellationToken.None);
        handler.Seed($"/originals/{item.OwnerId}/{item.Id:D}.pdf", StorageTests.Pdf);
        var cloud = new FailingCloud { Timeout = timeout };
        var worker = Worker(store, new(), cloud);
        await worker.ScanOnce(CancellationToken.None);
        Assert.Equal("Submitting", (await store.Load(item.OwnerId, item.Id, CancellationToken.None)).Case.Status);
        await worker.ScanOnce(CancellationToken.None);
        var recovered = (await store.Load(item.OwnerId, item.Id, CancellationToken.None)).Case;
        Assert.Equal("Failed", recovered.Status);
        Assert.Equal("SubmissionOutcomeUnknown", recovered.FailureCode);
        Assert.Equal(1, cloud.Calls);
    }

    [Fact]
    public async Task ExpiredAnalysisDeadlineFailsWithoutPollingAndHealthyScanIsObserved()
    {
        var handler = new StorageTests.BlobHandler();
        var store = StorageTests.Store(handler);
        var item = StorageTests.Case() with
            { Status = "Analyzing", AnalysisStartedAt = DateTimeOffset.UtcNow.AddHours(-1) };
        await store.Save(item, null, CancellationToken.None);
        var activity = new WorkerActivity();
        var cloud = new FailingCloud();
        await Worker(store, activity, cloud).ScanOnce(CancellationToken.None);
        Assert.Equal("AnalysisDeadlineExceeded", (await store.Load(item.OwnerId, item.Id, CancellationToken.None)).Case.FailureCode);
        Assert.Equal(0, cloud.Calls);
        var status = JsonSerializer.SerializeToElement(activity.Snapshot());
        Assert.Equal("active", status.GetProperty("status").GetString());
        Assert.NotEqual(JsonValueKind.Null, status.GetProperty("lastSuccessfulScan").ValueKind);
    }

    [Fact]
    public async Task PartialPublicationDoesNotApproveUntilBothConditionalWritesFinish()
    {
        var handler = new StorageTests.BlobHandler();
        var store = StorageTests.Store(handler);
        var item = StorageTests.Reviewed();
        await store.Save(item, null, CancellationToken.None);
        handler.Seed($"/originals/{item.OwnerId}/{item.Id:D}.pdf", StorageTests.Pdf);
        handler.FailNextWritePath = $"/approved/{item.Id:D}.pdf";
        var worker = Worker(store, new());
        await worker.ScanOnce(CancellationToken.None);
        Assert.Equal("Publishing", (await store.Load(item.OwnerId, item.Id, CancellationToken.None)).Case.Status);
        await worker.ScanOnce(CancellationToken.None);
        Assert.Equal("Approved", (await store.Load(item.OwnerId, item.Id, CancellationToken.None)).Case.Status);
        Assert.Equal(4, handler.Writes); // Initial state, two artifacts, final state.
    }

    private static ExtractionWorker Worker(CaseStore store, WorkerActivity activity, FailingCloud? handler = null) =>
        new(store, new CloudServices(new HttpClient(handler ?? new FailingCloud()), new SyntheticCredential(), ReviewTests.Options),
            ReviewTests.Options, NullLogger<ExtractionWorker>.Instance, activity);

    private sealed class FailingCloud : HttpMessageHandler
    {
        public int Calls { get; private set; }
        public bool Timeout { get; init; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            if (Timeout) return Task.FromException<HttpResponseMessage>(new OperationCanceledException());
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadGateway));
        }
    }
    private sealed class SyntheticCredential : TokenCredential
    {
        public override AccessToken GetToken(TokenRequestContext requestContext, CancellationToken cancellationToken) =>
            new("synthetic-offline-token", DateTimeOffset.UtcNow.AddHours(1));
        public override ValueTask<AccessToken> GetTokenAsync(TokenRequestContext requestContext, CancellationToken cancellationToken) =>
            ValueTask.FromResult(GetToken(requestContext, cancellationToken));
    }
}
