using Azure;
using Azure.Core;
using Azure.Identity;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.Tokens;
using ReviewPortal;
using System.Security.Claims;
using System.Threading.RateLimiting;

var builder = WebApplication.CreateBuilder(args);
var options = builder.Configuration.GetSection("Portal").Get<PortalOptions>() ??
    throw new InvalidOperationException("Portal configuration is required.");
options.Validate();
builder.Services.AddSingleton(options);
builder.WebHost.ConfigureKestrel(k => k.Limits.MaxRequestBodySize = options.MaxUploadBytes);
builder.Services.AddOutboundTlsPolicy(builder.Environment.IsDevelopment());
builder.Services.AddSingleton<TokenCredential>(sp => builder.Environment.IsDevelopment()
    ? new AzureCliCredential()
    : !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("AZURE_FEDERATED_TOKEN_FILE"))
        ? new WorkloadIdentityCredential(sp.GetRequiredService<WorkloadIdentityCredentialOptions>())
        : new ManagedIdentityCredential(options.ManagedIdentityClientId ??
            throw new InvalidOperationException("An assigned runtime identity is required."),
            sp.GetRequiredService<ManagedIdentityCredentialOptions>()));
builder.Services.AddSingleton(sp => new BlobServiceClient(new Uri(options.BlobEndpoint),
    sp.GetRequiredService<TokenCredential>(), sp.GetRequiredService<BlobClientOptions>()));
builder.Services.AddSingleton<CaseStore>();
builder.Services.AddHttpClient<CloudServices>(c => c.Timeout = TimeSpan.FromSeconds(120));
builder.Services.AddHostedService<ExtractionWorker>();
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(jwt =>
{
    jwt.Authority = $"https://login.microsoftonline.com/{options.TenantId}/v2.0";
    jwt.Audience = options.ApiAudience;
    jwt.MapInboundClaims = false;
    jwt.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true, ValidateAudience = true, ValidateLifetime = true,
        RoleClaimType = "roles", NameClaimType = "oid", ClockSkew = TimeSpan.FromSeconds(30)
    };
});
builder.Services.AddAuthorization(auth =>
{
    auth.AddPolicy("caseworker", p => p.RequireAuthenticatedUser().RequireRole("Caseworker")
        .RequireAssertion(c => Guid.TryParse(c.User.FindFirstValue("oid"), out _) &&
            c.User.FindFirstValue("tid") == options.TenantId &&
            (c.User.FindFirstValue("scp") ?? "").Split(' ').Contains(options.ApiScope.Split('/').Last())));
    auth.AddPolicy("reviewer", p => p.RequireAuthenticatedUser().RequireRole("Caseworker", "Reviewer")
        .RequireAssertion(c => c.User.IsInRole("Caseworker") && c.User.IsInRole("Reviewer") &&
            Guid.TryParse(c.User.FindFirstValue("oid"), out _) && c.User.FindFirstValue("tid") == options.TenantId &&
            (c.User.FindFirstValue("scp") ?? "").Split(' ').Contains(options.ApiScope.Split('/').Last())));
});
builder.Services.AddRateLimiter(r =>
{
    r.RejectionStatusCode = 429;
    r.AddPolicy("api", context => RateLimitPartition.GetFixedWindowLimiter(
        context.User.FindFirstValue("oid") ?? context.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 30, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
});
var app = builder.Build();
app.Use(async (context, next) =>
{
    context.Response.Headers["Cache-Control"] = "no-store";
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers["Content-Security-Policy"] =
        "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self' https://login.microsoftonline.com; frame-src blob:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'";
    try { await next(context); }
    catch (RequestFailedException ex) when (ex.Status is 404 or 409 or 412)
    {
        context.Response.StatusCode = ex.Status == 404 ? 404 : 409;
        await context.Response.WriteAsJsonAsync(new { error = "Case missing or changed. Refresh before retrying.", requestId = context.TraceIdentifier });
    }
    catch (Exception ex) when (ex is RequestFailedException or HttpRequestException or InvalidOperationException or System.Text.Json.JsonException)
    {
        app.Logger.LogError("Request {RequestId} failed: {ErrorType}.", context.TraceIdentifier, ex.GetType().Name);
        context.Response.StatusCode = 502;
        await context.Response.WriteAsJsonAsync(new { error = "Operation failed or evidence is not ready. Contact the operator with the request ID.", requestId = context.TraceIdentifier });
    }
});
app.UseDefaultFiles();
app.UseStaticFiles();
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();
app.MapGet("/health/live", () => Results.Ok(new { status = "alive" }));
app.MapGet("/health/ready", async (CaseStore store, CancellationToken ct) =>
{
    await store.State.GetPropertiesAsync(cancellationToken: ct);
    return Results.Ok(new { status = "storage-reachable", retrievalVerified = false });
});
app.MapGet("/api/config", () => new
{
    options.TenantId, options.ClientId, options.ApiScope, options.ConfidenceThreshold, options.MaxUploadBytes
});
var api = app.MapGroup("/api/cases").RequireAuthorization("caseworker").RequireRateLimiting("api");
api.MapGet("/", async (ClaimsPrincipal user, CaseStore store, CancellationToken ct) =>
    await store.List(Owner(user), ct));
api.MapGet("/{id:guid}", async (Guid id, ClaimsPrincipal user, CaseStore store, CancellationToken ct) =>
    await store.Load(Owner(user), id, ct));
api.MapPost("/", async (HttpRequest request, ClaimsPrincipal user, CaseStore store, CancellationToken ct) =>
{
    if (request.ContentType?.Split(';')[0] != "application/pdf") return Results.BadRequest(new { error = "Upload a PDF body." });
    using var buffer = new MemoryStream();
    await request.Body.CopyToAsync(buffer, ct);
    if (buffer.Length is < 8 || buffer.Length > options.MaxUploadBytes ||
        !buffer.GetBuffer().AsSpan(0, 5).SequenceEqual("%PDF-"u8))
        return Results.BadRequest(new { error = "Invalid PDF or size limit exceeded." });
    var id = Guid.NewGuid();
    var item = new ReviewCase(id, Owner(user), "application.pdf", DateTimeOffset.UtcNow, "Pending",
        OriginalSha256: Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(buffer.GetBuffer().AsSpan(0, (int)buffer.Length))));
    buffer.Position = 0;
    await store.Original(item.OwnerId, id).UploadAsync(buffer, new BlobUploadOptions
    {
        Conditions = new BlobRequestConditions { IfNoneMatch = ETag.All },
        HttpHeaders = new BlobHttpHeaders { ContentType = "application/pdf" }
    }, ct);
    await store.Save(item, null, ct);
    return Results.Created($"/api/cases/{id:D}", item);
});
api.MapGet("/{id:guid}/original", async (Guid id, ClaimsPrincipal user, CaseStore store, CancellationToken ct) =>
{
    await store.Load(Owner(user), id, ct);
    var stream = await store.Original(Owner(user), id).OpenReadAsync(cancellationToken: ct);
    return Results.Stream(stream, "application/pdf", fileDownloadName: "application.pdf");
});
api.MapPost("/{id:guid}/review", async (Guid id, ReviewInput input, ClaimsPrincipal user, CaseStore store, CancellationToken ct) =>
{
    if (input.Values is null || string.IsNullOrWhiteSpace(input.Version))
        return Results.BadRequest(new { error = "Supply field values and the current case version." });
    var snapshot = await store.Load(Owner(user), id, ct);
    if (snapshot.Version != input.Version) return Results.Conflict(new { error = "The case changed; refresh it." });
    if (snapshot.Case.Status != "NeedsReview") return Results.Conflict(new { error = "Case is not awaiting review." });
    ReviewCase reviewed;
    try { reviewed = ReviewRules.Approve(snapshot.Case, input, Owner(user)); }
    catch (InvalidOperationException) { return Results.BadRequest(new { error = "Confirm every configured field, using at most 4000 characters per field." }); }
    await store.Save(reviewed, input.Version, ct);
    return Results.Accepted($"/api/cases/{id:D}", reviewed);
}).RequireAuthorization("reviewer");
api.MapPost("/{id:guid}/retry", async (Guid id, ClaimsPrincipal user, CaseStore store, CancellationToken ct) =>
{
    var snapshot = await store.Load(Owner(user), id, ct);
    if (snapshot.Case.Status != "Failed") return Results.Conflict(new { error = "Only failed cases can be retried." });
    var publishing = snapshot.Case.ReviewedAt.HasValue;
    await store.Save(snapshot.Case with
    {
        Status = publishing ? "Publishing" : "Pending", Operation = publishing ? snapshot.Case.Operation : null,
        AnalysisStartedAt = publishing ? snapshot.Case.AnalysisStartedAt : null, FailureCode = null
    }, snapshot.Version, ct);
    return Results.Accepted();
});
api.MapPost("/{id:guid}/chat", async (Guid id, ChatInput input, ClaimsPrincipal user, CaseStore store,
    CloudServices cloud, CancellationToken ct) =>
{
    var validationError = ChatContextRules.ValidationError(input.Question, input.History);
    if (validationError is not null)
        return Results.BadRequest(new { error = validationError });
    var item = (await store.Load(Owner(user), id, ct)).Case;
    if (item.Status != "Approved") return Results.Conflict(new { error = "Human validation and publication must finish first." });
    return Results.Ok(await cloud.Chat(item, input.Question!, ct, input.History));
});
app.Run();

static string Owner(ClaimsPrincipal user) => Guid.Parse(user.FindFirstValue("oid") ??
    throw new InvalidOperationException("Missing object ID.")).ToString("D");

public partial class Program;
