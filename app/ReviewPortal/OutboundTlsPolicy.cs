using Azure.Core.Pipeline;
using Azure.Identity;
using Azure.Storage.Blobs;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using System.Net.Security;
using System.Security.Authentication;

namespace ReviewPortal;

public static class OutboundTlsPolicy
{
    public const string AzureClient = "AzureSdk";
    public const string MetadataClient = "JwtMetadata";

    public static SocketsHttpHandler CreateHandler(bool syntheticDevelopment)
    {
        if (!OperatingSystem.IsLinux() && !syntheticDevelopment)
            throw new PlatformNotSupportedException("Production outbound cipher policy requires Linux.");

        var handler = new SocketsHttpHandler
        {
            AllowAutoRedirect = false,
            SslOptions = new SslClientAuthenticationOptions
            {
                // Certificate 5313 approves TLS 1.2 KDF, not TLS 1.3 HKDF.
                EnabledSslProtocols = SslProtocols.Tls12
            }
        };
        if (OperatingSystem.IsLinux())
        {
            // The image's OpenSSL system_default profile limits groups to P-256/P-384.
            // Native approved-mode/module mapping still requires runtime evidence.
            handler.SslOptions.CipherSuitesPolicy = new CipherSuitesPolicy(
            [
                TlsCipherSuite.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
                TlsCipherSuite.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
                TlsCipherSuite.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
                TlsCipherSuite.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
            ]);
        }
        // macOS development uses OS cipher defaults; neither branch proves native module mapping.
        return handler;
    }

    public static IServiceCollection AddOutboundTlsPolicy(this IServiceCollection services,
        bool syntheticDevelopment)
    {
        services.ConfigureHttpClientDefaults(http =>
            http.ConfigurePrimaryHttpMessageHandler(() => CreateHandler(syntheticDevelopment)));
        services.AddHttpClient(AzureClient);
        services.AddHttpClient(MetadataClient, http => http.Timeout = TimeSpan.FromMinutes(1));
        services.AddSingleton(sp => new HttpClientTransport(
            sp.GetRequiredService<IHttpClientFactory>().CreateClient(AzureClient)));
        services.AddSingleton(sp => new BlobClientOptions
        {
            Transport = sp.GetRequiredService<HttpClientTransport>()
        });
        services.AddSingleton(sp => new WorkloadIdentityCredentialOptions
        {
            Transport = sp.GetRequiredService<HttpClientTransport>()
        });
        services.AddSingleton(sp => new ManagedIdentityCredentialOptions
        {
            Transport = sp.GetRequiredService<HttpClientTransport>()
        });
        services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
            .Configure<IHttpClientFactory>((jwt, factory) =>
                jwt.Backchannel = factory.CreateClient(MetadataClient));
        return services;
    }
}
