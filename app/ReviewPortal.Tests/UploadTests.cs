using Azure.Core.Pipeline;
using Azure.Storage.Blobs;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ReviewPortal;
using System.Net;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Xunit;

namespace ReviewPortal.Tests;

public sealed class UploadTests
{
    [Theory]
    [InlineData("not a PDF", 100, false)]
    [InlineData("%PDF-12", 100, false)]
    [InlineData("%PDF-123", 8, true)]
    [InlineData("%PDF-1234", 8, false)]
    public async Task PdfInputIsValidatedAndBoundedEvenWithoutContentLength(string text, int limit, bool accepted)
    {
        using var input = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(text));
        using var result = await PdfUpload.Read(input, limit, CancellationToken.None);
        Assert.Equal(accepted, result is not null);
        if (result is not null) Assert.Equal(0, result.Position);
    }

    [Fact]
    public async Task UploadConcurrencyIsBoundedAcrossAllOwnersAndRecoversAfterRelease()
    {
        using var factory = new UploadFactory();
        factory.Blobs.BlockOriginalUploads = true;
        using var client = factory.CreateClient();
        var firstRequest = Upload(client, new MemoryStream(StorageTests.Pdf));
        var secondRequest = Upload(client, new MemoryStream(StorageTests.Pdf), Guid.NewGuid().ToString("D"));
        await factory.Blobs.TwoOriginalUploads.Task.WaitAsync(TimeSpan.FromSeconds(10));
        using var excess = await Upload(client, new MemoryStream(StorageTests.Pdf), Guid.NewGuid().ToString("D"));
        Assert.Equal(HttpStatusCode.TooManyRequests, excess.StatusCode);
        factory.Blobs.ReleaseOriginalUploads.TrySetResult();
        var responses = await Task.WhenAll(firstRequest, secondRequest).WaitAsync(TimeSpan.FromSeconds(10));
        foreach (var response in responses) { Assert.Equal(HttpStatusCode.Created, response.StatusCode); response.Dispose(); }
        using var later = await Upload(client, new MemoryStream(StorageTests.Pdf));
        Assert.Equal(HttpStatusCode.Created, later.StatusCode);
    }

    [Fact]
    public async Task UnknownSubmissionRetryRequiresExplicitAcknowledgment()
    {
        using var factory = new UploadFactory();
        using var client = factory.CreateClient();
        var store = factory.Services.GetRequiredService<CaseStore>();
        var item = StorageTests.Case() with { Status = "Failed", FailureCode = "SubmissionOutcomeUnknown" };
        await store.Save(item, null, CancellationToken.None);
        var snapshot = await store.Load(item.OwnerId, item.Id, CancellationToken.None);
        using var denied = await client.PostAsync($"/api/cases/{item.Id:D}/retry",
            System.Net.Http.Json.JsonContent.Create(new RetryInput(snapshot.Version)));
        Assert.Equal(HttpStatusCode.Conflict, denied.StatusCode);
        Assert.Equal("Failed", (await store.Load(item.OwnerId, item.Id, CancellationToken.None)).Case.Status);
        using var stale = await client.PostAsync($"/api/cases/{item.Id:D}/retry",
            System.Net.Http.Json.JsonContent.Create(new RetryInput("stale", true)));
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        using var accepted = await client.PostAsync($"/api/cases/{item.Id:D}/retry",
            System.Net.Http.Json.JsonContent.Create(new RetryInput(snapshot.Version, true)));
        Assert.Equal(HttpStatusCode.Accepted, accepted.StatusCode);
        Assert.Equal("Pending", (await store.Load(item.OwnerId, item.Id, CancellationToken.None)).Case.Status);
    }

    [Fact]
    public async Task ListReturnsExplicitOwnerScopedPagesOfAtMostFifty()
    {
        using var factory = new UploadFactory();
        using var client = factory.CreateClient();
        var store = factory.Services.GetRequiredService<CaseStore>();
        for (var index = 0; index < 51; index++) await store.Save(StorageTests.Case(), null, CancellationToken.None);
        await store.Save(StorageTests.Case() with { OwnerId = Guid.NewGuid().ToString("D") }, null, CancellationToken.None);
        using var first = JsonDocument.Parse(await client.GetStringAsync("/api/cases/"));
        Assert.Equal(50, first.RootElement.GetProperty("items").GetArrayLength());
        var token = first.RootElement.GetProperty("continuationToken").GetString();
        Assert.False(string.IsNullOrEmpty(token));
        using var second = JsonDocument.Parse(await client.GetStringAsync("/api/cases/?continuationToken=" + Uri.EscapeDataString(token!)));
        Assert.Equal(1, second.RootElement.GetProperty("items").GetArrayLength());
        Assert.Equal(JsonValueKind.Null, second.RootElement.GetProperty("continuationToken").ValueKind);
        Assert.All(first.RootElement.GetProperty("items").EnumerateArray().Concat(second.RootElement.GetProperty("items").EnumerateArray()),
            item => Assert.Equal(ReviewTests.Options.TenantId, item.GetProperty("ownerId").GetString()));
    }

    [Fact]
    public async Task PublicationRetryRejectsInvalidFrozenHumanGate()
    {
        using var factory = new UploadFactory();
        using var client = factory.CreateClient();
        var store = factory.Services.GetRequiredService<CaseStore>();
        var item = StorageTests.Reviewed() with { Status = "Failed", ReviewerId = Guid.NewGuid().ToString("D") };
        await store.Save(item, null, CancellationToken.None);
        var snapshot = await store.Load(item.OwnerId, item.Id, CancellationToken.None);
        using var denied = await client.PostAsync($"/api/cases/{item.Id:D}/retry",
            System.Net.Http.Json.JsonContent.Create(new RetryInput(snapshot.Version)));
        Assert.Equal(HttpStatusCode.Conflict, denied.StatusCode);
        Assert.Equal("Failed", (await store.Load(item.OwnerId, item.Id, CancellationToken.None)).Case.Status);
    }

    private static async Task<HttpResponseMessage> Upload(HttpClient client, Stream input, string? owner = null)
    {
        using var content = new StreamContent(input);
        content.Headers.ContentType = new("application/pdf");
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/cases/") { Content = content };
        request.Headers.Add("X-Offline-Owner", owner ?? ReviewTests.Options.TenantId);
        return await client.SendAsync(request);
    }

    private sealed class UploadFactory : WebApplicationFactory<Program>
    {
        public StorageTests.BlobHandler Blobs { get; } = new();
        protected override IHost CreateHost(IHostBuilder builder)
        {
            var values = new Dictionary<string, string?>();
            foreach (var field in JsonSerializer.SerializeToElement(ReviewTests.Options).EnumerateObject())
            {
                if (field.Value.ValueKind == JsonValueKind.Array)
                {
                    var index = 0;
                    foreach (var value in field.Value.EnumerateArray()) values[$"Portal:{field.Name}:{index++}"] = value.ToString();
                }
                else values[$"Portal:{field.Name}"] = field.Value.ValueKind == JsonValueKind.Null ? null : field.Value.ToString();
            }
            builder.ConfigureHostConfiguration(config => config.AddInMemoryCollection(values));
            return base.CreateHost(builder);
        }
        protected override void ConfigureWebHost(IWebHostBuilder builder) => builder.ConfigureServices(services =>
        {
            services.RemoveAll<IHostedService>();
            services.RemoveAll<BlobServiceClient>();
            var options = new BlobClientOptions { Transport = new HttpClientTransport(new HttpClient(Blobs)) };
            options.Retry.MaxRetries = 0;
            services.AddSingleton(new BlobServiceClient(new Uri(ReviewTests.Options.BlobEndpoint), options));
            services.AddAuthentication("offline").AddScheme<AuthenticationSchemeOptions, OfflineAuthentication>("offline", _ => { });
        });
    }

    private sealed class OfflineAuthentication(IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger, UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
    {
        protected override Task<AuthenticateResult> HandleAuthenticateAsync() => Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([
                new("oid", Request.Headers["X-Offline-Owner"].FirstOrDefault() ?? ReviewTests.Options.TenantId),
                new("tid", ReviewTests.Options.TenantId),
                new("scp", "access_as_user"), new(ClaimTypes.Role, "Caseworker"), new(ClaimTypes.Role, "Reviewer")
            ], "offline")), "offline")));
    }
}
