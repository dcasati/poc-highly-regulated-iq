using Xunit;

namespace ReviewPortal.Tests;

public sealed class OpenSslProfileTests
{
    private static string Source(string name) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "PolicySources", name));

    [Fact]
    public void ProfileIncludesVendorConfigurationAndOnlyOverridesSslAndDiagnostics()
    {
        var lines = Source("openssl-tls.cnf").Split('\n').Select(line => line.Trim())
            .Where(line => line.Length > 0 && !line.StartsWith('#')).ToArray();
        Assert.Equal(".include /etc/pki/tls/openssl.cnf", lines[0]);
        Assert.Equal(new[]
        {
            ".include /etc/pki/tls/openssl.cnf",
            "[default]", "config_diagnostics = 1",
            "[openssl_init]", "ssl_conf = reviewportal_ssl",
            "[reviewportal_ssl]", "system_default = reviewportal_tls",
            "[reviewportal_tls]", "MinProtocol = TLSv1.2", "MaxProtocol = TLSv1.2",
            "CipherString = ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256",
            "Groups = P-256:P-384"
        }, lines);
    }

    [Fact]
    public void RuntimeImageRequiresReadableVendorConfigurationBeforeStartingDotnet()
    {
        var docker = Source("Dockerfile");
        var runtime = docker[docker.IndexOf("FROM ${RUNTIME_IMAGE} AS runtime", StringComparison.Ordinal)..];
        Assert.Contains("COPY openssl-tls.cnf /app/openssl-tls.cnf\nRUN chmod -R a+rX /app && chmod 0444 /app/openssl-tls.cnf\nUSER 1654:1654", runtime);
        Assert.DoesNotContain("--chmod", runtime);
        Assert.Contains("USER 1654:1654\nRUN test -r /etc/pki/tls/openssl.cnf && test -s /etc/pki/tls/openssl.cnf", runtime);
        Assert.Contains("&& test -r /etc/pki/tls/symcrypt_prov.cnf && test -s /etc/pki/tls/symcrypt_prov.cnf", runtime);
        Assert.Contains("openssl_conf[[:space:]]*=[[:space:]]*openssl_init", runtime);
        Assert.Contains(@"grep -Eq '^[[:space:]]*\[[[:space:]]*openssl_init[[:space:]]*\]'", runtime);
        Assert.Contains("ENV OPENSSL_CONF=/app/openssl-tls.cnf", runtime);
        Assert.Contains("""ENTRYPOINT ["dotnet", "ReviewPortal.dll"]""", runtime);
        Assert.DoesNotContain("||", runtime);
        Assert.DoesNotContain("default_properties", runtime);
        Assert.DoesNotContain("OPENSSL_FORCE_FIPS_MODE", runtime);
        Assert.DoesNotContain("OPENSSL_MODULES", runtime);
        Assert.DoesNotContain("activate", runtime);
    }
}
