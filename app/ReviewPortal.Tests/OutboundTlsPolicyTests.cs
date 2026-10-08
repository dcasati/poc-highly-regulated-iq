using Azure.Core.Pipeline;
using Azure.Identity;
using Azure.Storage.Blobs;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Xunit;

namespace ReviewPortal.Tests;

public sealed class OutboundTlsPolicyTests : IClassFixture<PortalFactory>
{
    private readonly PortalFactory factory;
    public OutboundTlsPolicyTests(PortalFactory factory) => this.factory = factory;

    [Theory]
    [InlineData("")]
    [InlineData(nameof(CloudServices))]
    [InlineData(OutboundTlsPolicy.AzureClient)]
    [InlineData(OutboundTlsPolicy.MetadataClient)]
    [InlineData("FutureNamedClient")]
    public void FactoryClientsUseTheSharedPolicy(string name)
    {
        var handler = factory.Services.GetRequiredService<IHttpMessageHandlerFactory>().CreateHandler(name);
        AssertPolicy(PrimaryHandler(handler));
    }

    [Fact]
    public void BlobAndBothProductionIdentityOptionsUseTheFactoryTransport()
    {
        var services = factory.Services;
        var transport = services.GetRequiredService<HttpClientTransport>();
        Assert.Same(transport, services.GetRequiredService<BlobClientOptions>().Transport);
        Assert.Same(transport, services.GetRequiredService<WorkloadIdentityCredentialOptions>().Transport);
        Assert.Same(transport, services.GetRequiredService<ManagedIdentityCredentialOptions>().Transport);
        Assert.NotNull(services.GetRequiredService<BlobServiceClient>());
        Assert.NotNull(services.GetRequiredService<CloudServices>());
    }

    [Fact]
    public void JwtMetadataUsesTheFactoryClientAndRequiresHttps()
    {
        var options = factory.Services.GetRequiredService<IOptionsMonitor<JwtBearerOptions>>()
            .Get(JwtBearerDefaults.AuthenticationScheme);
        Assert.NotNull(options.Backchannel);
        Assert.Null(options.BackchannelHttpHandler);
        Assert.True(options.RequireHttpsMetadata);
        Assert.Equal(TimeSpan.FromMinutes(1), options.Backchannel.Timeout);
    }

    [Fact]
    public void ProductionRequiresTheSupportedCipherPolicyPlatform()
    {
        if (OperatingSystem.IsLinux())
        {
            using var handler = OutboundTlsPolicy.CreateHandler(false);
            AssertPolicy(handler);
        }
        else
            Assert.Throws<PlatformNotSupportedException>(() => OutboundTlsPolicy.CreateHandler(false));
    }

    [Theory]
    [InlineData(SslProtocols.None, nameof(CloudServices))]
    [InlineData(SslProtocols.None, OutboundTlsPolicy.AzureClient)]
    [InlineData(SslProtocols.None, OutboundTlsPolicy.MetadataClient)]
    [InlineData(SslProtocols.Tls12, nameof(CloudServices))]
    [InlineData(SslProtocols.Tls12, OutboundTlsPolicy.AzureClient)]
    [InlineData(SslProtocols.Tls12, OutboundTlsPolicy.MetadataClient)]
    public async Task DefaultOrTls12ServerNegotiatesOnlyTls12(SslProtocols serverProtocols, string clientName)
    {
        var result = await Exchange(serverProtocols, trustCertificate: true, clientName: clientName);
        Assert.Null(result.ClientError);
        Assert.Null(result.ServerError);
        Assert.Equal(SslProtocols.Tls12, result.Protocol);
    }

    [Fact]
    public async Task BlobSdkUsesTheTls12FactoryTransport()
    {
        var result = await Exchange(SslProtocols.None, trustCertificate: true,
            clientName: OutboundTlsPolicy.AzureClient, blobRequest: true);
        Assert.Null(result.ClientError);
        Assert.Null(result.ServerError);
        Assert.Equal(SslProtocols.Tls12, result.Protocol);
    }

    [Theory]
    [InlineData("blob")]
    [InlineData("content")]
    [InlineData("search")]
    [InlineData("project")]
    public void ConfiguredServiceEndpointsCannotUseTheIdentityMetadataHttpException(string service)
    {
        const string endpoint = "http://127.0.0.1/";
        var options = service switch
        {
            "blob" => ReviewTests.Options with { BlobEndpoint = endpoint },
            "content" => ReviewTests.Options with { ContentEndpoint = endpoint },
            "search" => ReviewTests.Options with { SearchEndpoint = endpoint },
            _ => ReviewTests.Options with { ProjectEndpoint = endpoint }
        };
        Assert.Throws<InvalidOperationException>(options.Validate);
    }

    [Theory]
    [InlineData(192)] // TLS 1.0
    [InlineData(768)] // TLS 1.1
    [InlineData((int)SslProtocols.Tls13)]
    public async Task OtherProtocolOnlyServersAreRejected(int serverProtocols)
    {
        var result = await Exchange((SslProtocols)serverProtocols, trustCertificate: true);
        Assert.IsType<HttpRequestException>(result.ClientError);
        Assert.NotEqual(SslProtocols.Tls12, result.Protocol);
    }

    [Fact]
    public async Task UntrustedCertificateIsRejected()
    {
        var result = await Exchange(SslProtocols.Tls12, trustCertificate: false);
        Assert.IsType<HttpRequestException>(result.ClientError);
    }

    [Fact]
    public async Task TrustedCertificateWithWrongHostnameIsRejected()
    {
        var result = await Exchange(SslProtocols.Tls12, trustCertificate: true, wrongHostname: true);
        Assert.IsType<HttpRequestException>(result.ClientError);
    }

    private static void AssertPolicy(SocketsHttpHandler handler)
    {
        Assert.Equal(SslProtocols.Tls12, handler.SslOptions.EnabledSslProtocols);
        Assert.Null(handler.SslOptions.RemoteCertificateValidationCallback);
        Assert.Null(handler.SslOptions.CertificateChainPolicy);
        Assert.False(handler.AllowAutoRedirect);
        if (OperatingSystem.IsLinux())
            Assert.Equal(
                new[]
                {
                    TlsCipherSuite.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
                    TlsCipherSuite.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
                    TlsCipherSuite.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
                    TlsCipherSuite.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
                }, handler.SslOptions.CipherSuitesPolicy!.AllowedCipherSuites);
        else
            Assert.Null(handler.SslOptions.CipherSuitesPolicy);
    }

    private static SocketsHttpHandler PrimaryHandler(HttpMessageHandler handler)
    {
        while (handler is DelegatingHandler delegating)
            handler = Assert.IsAssignableFrom<HttpMessageHandler>(delegating.InnerHandler);
        return Assert.IsType<SocketsHttpHandler>(handler);
    }

    private static async Task<(Exception? ClientError, Exception? ServerError, SslProtocols Protocol)> Exchange(
        SslProtocols serverProtocols, bool trustCertificate, bool wrongHostname = false,
        string clientName = nameof(CloudServices), bool blobRequest = false)
    {
        using var key = RSA.Create(2048);
        var request = new CertificateRequest("CN=localhost", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(
            X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyCertSign, true));
        var names = new SubjectAlternativeNameBuilder();
        names.AddDnsName("localhost");
        request.CertificateExtensions.Add(names.Build());
        using var certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-1),
            DateTimeOffset.UtcNow.AddMinutes(10));
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var server = Serve();
        using var services = new ServiceCollection().AddOutboundTlsPolicy(true).BuildServiceProvider();
        var handler = PrimaryHandler(services.GetRequiredService<IHttpMessageHandlerFactory>().CreateHandler(clientName));
        handler.UseProxy = false;
        if (trustCertificate)
        {
            // Trust only this ephemeral root; normal chain and hostname validation remain enabled.
            handler.SslOptions.CertificateChainPolicy = new X509ChainPolicy
            {
                TrustMode = X509ChainTrustMode.CustomRootTrust,
                RevocationMode = X509RevocationMode.NoCheck
            };
            handler.SslOptions.CertificateChainPolicy.CustomTrustStore.Add(certificate);
        }
        using var client = services.GetRequiredService<IHttpClientFactory>().CreateClient(clientName);
        Exception? clientError = null;
        try
        {
            var host = wrongHostname ? "127.0.0.1" : "localhost";
            var endpoint = new Uri($"https://{host}:{((IPEndPoint)listener.LocalEndpoint).Port}/");
            if (blobRequest)
            {
                var blobOptions = services.GetRequiredService<BlobClientOptions>();
                blobOptions.Retry.MaxRetries = 0;
                var blob = new BlobServiceClient(endpoint, blobOptions).GetBlobContainerClient("test");
                Assert.True((await blob.ExistsAsync(timeout.Token)).Value);
            }
            else
            {
                using var response = await client.GetAsync(endpoint, timeout.Token);
                response.EnsureSuccessStatusCode();
            }
        }
        catch (HttpRequestException ex) { clientError = ex; }
        var result = await server;
        return (clientError, result.Error, result.Protocol);

        async Task<(Exception? Error, SslProtocols Protocol)> Serve()
        {
            var protocol = SslProtocols.None;
            try
            {
                using var socket = await listener.AcceptTcpClientAsync(timeout.Token);
                using var stream = new SslStream(socket.GetStream());
                await stream.AuthenticateAsServerAsync(new SslServerAuthenticationOptions
                {
                    ServerCertificate = certificate, EnabledSslProtocols = serverProtocols
                }, timeout.Token);
                protocol = stream.SslProtocol;
                using var reader = new StreamReader(stream, leaveOpen: true);
                while (await reader.ReadLineAsync(timeout.Token) is { Length: > 0 }) { }
                await stream.WriteAsync("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"u8.ToArray(),
                    timeout.Token);
                return (null, protocol);
            }
            catch (Exception ex) when (ex is AuthenticationException or IOException or PlatformNotSupportedException)
            {
                return (ex, protocol);
            }
        }
    }
}
