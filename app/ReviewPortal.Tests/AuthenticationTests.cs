using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Json;
using Xunit;

namespace ReviewPortal.Tests;

public sealed class AuthenticationTests : IClassFixture<PortalFactory>
{
    private readonly HttpClient client;
    public AuthenticationTests(PortalFactory factory) => client = factory.CreateClient();

    [Fact]
    public async Task AnonymousApiAccessIsRejected() =>
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/cases/")).StatusCode);

    [Theory]
    [InlineData("Caseworker", "wrong_scope", PortalFactory.Tenant)]
    [InlineData("Other", "access_as_user", PortalFactory.Tenant)]
    [InlineData("Caseworker", "access_as_user", "22222222-2222-2222-2222-222222222222")]
    public async Task RolesScopeAndTenantAreRequired(string role, string scope, string tenant)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/cases/");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", PortalFactory.Token(role, scope, tenant));
        Assert.Equal(HttpStatusCode.Forbidden, (await client.SendAsync(request)).StatusCode);
    }

    [Fact]
    public async Task CaseworkerCannotPublishWithoutReviewerRole()
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"/api/cases/{Guid.NewGuid():D}/review")
        { Content = new StringContent("""{"values":{},"version":"etag"}""", System.Text.Encoding.UTF8, "application/json") };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", PortalFactory.Token("Caseworker", "access_as_user", PortalFactory.Tenant));
        Assert.Equal(HttpStatusCode.Forbidden, (await client.SendAsync(request)).StatusCode);
    }

    [Theory]
    [InlineData("""{"values":null,"version":"etag"}""")]
    [InlineData("""{"version":"etag"}""")]
    [InlineData("""{"values":{}}""")]
    [InlineData("""{"values":{},"version":null}""")]
    public async Task MalformedReviewIsRejectedBeforeAccessingStorage(string json)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"/api/cases/{Guid.NewGuid():D}/review")
        { Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json") };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer",
            PortalFactory.Token("Caseworker Reviewer", "access_as_user", PortalFactory.Tenant));
        Assert.Equal(HttpStatusCode.BadRequest, (await client.SendAsync(request)).StatusCode);
    }

    [Fact]
    public async Task FrontendHasNoThirdPartyScriptsAndSetsSecurityHeaders()
    {
        var response = await client.GetAsync("/");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("script-src 'self'", response.Headers.GetValues("Content-Security-Policy").Single());
        Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
        var html = await response.Content.ReadAsStringAsync();
        Assert.Contains("/theme.js", html);
        Assert.DoesNotContain("cdn.", html);
    }
}

public sealed class PortalFactory : WebApplicationFactory<Program>
{
    public const string Tenant = "11111111-1111-1111-1111-111111111111";
    private static readonly SymmetricSecurityKey Key = new(System.Text.Encoding.UTF8.GetBytes(new string('k', 64)));
    protected override IHost CreateHost(IHostBuilder builder)
    {
        builder.ConfigureHostConfiguration(config => config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Portal:TenantId"] = Tenant, ["Portal:ClientId"] = Tenant, ["Portal:ApiAudience"] = Tenant,
            ["Portal:ApiScope"] = $"api://{Tenant}/access_as_user",
            ["Portal:BlobEndpoint"] = ReviewTests.Options.BlobEndpoint,
            ["Portal:ContentEndpoint"] = ReviewTests.Options.ContentEndpoint,
            ["Portal:SearchEndpoint"] = ReviewTests.Options.SearchEndpoint,
            ["Portal:OpenAIEndpoint"] = ReviewTests.Options.OpenAIEndpoint,
            ["Portal:ChatDeployment"] = "review-chat", ["Portal:AnalyzerId"] = "review",
            ["Portal:KnowledgeBase"] = "review-kb", ["Portal:KnowledgeSource"] = "review-source",
            ["Portal:FieldNames:0"] = "ApplicantName", ["Portal:FieldNames:1"] = "SignaturePresent"
        }));
        return base.CreateHost(builder);
    }
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<IHostedService>();
            services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
            {
                options.Authority = null;
                options.Configuration = new OpenIdConnectConfiguration { Issuer = "https://test.example" };
                options.ConfigurationManager = new StaticConfigurationManager<OpenIdConnectConfiguration>(options.Configuration);
                options.TokenValidationParameters.ValidIssuer = "https://test.example";
                options.TokenValidationParameters.IssuerSigningKey = Key;
            });
        });
    }
    public static string Token(string role, string scope, string tenant) =>
        new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken("https://test.example", Tenant,
            role.Split(' ').Select(r => new Claim("roles", r)).Concat(
                [new Claim("oid", Tenant), new Claim("tid", tenant), new Claim("scp", scope)]),
            expires: DateTime.UtcNow.AddMinutes(5), signingCredentials: new SigningCredentials(Key, SecurityAlgorithms.HmacSha256)));
}
