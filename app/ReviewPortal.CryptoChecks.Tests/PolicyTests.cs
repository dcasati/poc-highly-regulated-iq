using System.Text.Json;
using ReviewPortal.CryptoChecks;
using Xunit;

namespace ReviewPortal.CryptoChecks.Tests;

public sealed class PolicyTests
{
    [Fact]
    public void OpenSslParameterAndDispatchLayoutsMatchThe64BitCAbi()
        => Assert.True(NativeCrypto.HasExpected64BitAbi);

    [Fact]
    public void CleanObservationsNeverQualifyTheDeployment()
    {
        var evidence = new Evidence();
        Assert.False(evidence.Qualified);
        Assert.Equal(EvidencePolicy.Unqualified, EvidencePolicy.ExitCode(evidence, linux: true));
        Assert.Contains("\"Qualified\":false", JsonSerializer.Serialize(evidence));
    }

    [Fact]
    public void ErrorAndUnsupportedHaveNonzeroDistinctExits()
    {
        var evidence = new Evidence();
        evidence.Errors.Add("missing-library");
        Assert.Equal(EvidencePolicy.Failed, EvidencePolicy.ExitCode(evidence, linux: true));
        Assert.Equal(EvidencePolicy.Unsupported, EvidencePolicy.ExitCode(evidence, linux: false));
    }

    [Fact]
    public void SuccessfulNoopIsNotAProviderSelfTest()
    {
        Assert.False(EvidencePolicy.HasSelfTestDispatch([1024, 1025, 1027, 1030]));
        Assert.True(EvidencePolicy.HasSelfTestDispatch([1024, 1031]));
        var provider = new ProviderEvidence("symcryptprovider", "1.10.2", 1, true, false, null);
        Assert.Null(provider.SelfTestResult);
    }

    [Theory]
    [InlineData("https://host")]
    [InlineData("host/path")]
    [InlineData("user:secret@host")]
    [InlineData("host?token=secret")]
    [InlineData("127.0.0.1")]
    [InlineData("::1")]
    [InlineData("-host.example")]
    [InlineData("host..example")]
    [InlineData("host\nexample")]
    public void RejectsNonHostnameOrCredentialLikeTlsInput(string host)
        => Assert.Throws<ArgumentException>(() => Options.Parse(["--tls-host", host]));

    [Theory]
    [InlineData("--timeout-seconds", "0")]
    [InlineData("--timeout-seconds", "121")]
    [InlineData("--tls-timeout-seconds", "31")]
    [InlineData("--tls-port", "65536")]
    [InlineData("--unknown", "value")]
    public void RejectsInvalidOptions(string name, string value)
        => Assert.Throws<ArgumentException>(() => Options.Parse([name, value]));

    [Fact]
    public void RequiresExplicitTlsAndBoundedDeadline()
    {
        Assert.Null(Options.Parse([]).TlsHost);
        Assert.Equal(5, Options.Parse(["--timeout-seconds", "5"]).TimeoutSeconds);
        Assert.Throws<ArgumentException>(() => Options.Parse(["--tls-port", "443"]));
        Assert.Throws<ArgumentException>(() => Options.Parse(["--tls-host"]));
        Assert.Throws<ArgumentException>(() => Options.Parse(["--timeout-seconds", "45", "--timeout-seconds", "45"]));
        Assert.Throws<ArgumentException>(() => Options.Parse(["--tls-host", "example.test", "--timeout-seconds", "10", "--tls-timeout-seconds", "10"]));
        Assert.Equal("example.test", Options.Parse(["--tls-host", "example.test"]).TlsHost);
    }

    [Fact]
    public void RejectsWeakOrFailedManagedChecks()
    {
        var evidence = new ManagedEvidence(true, true, 2048, true, true, null, null, null);
        Assert.True(EvidencePolicy.ManagedChecksPassed(evidence));
        Assert.False(EvidencePolicy.ManagedChecksPassed(evidence with { RsaBits = 1024 }));
        Assert.False(EvidencePolicy.ManagedChecksPassed(evidence with { Sha256KnownAnswer = false }));
        Assert.False(EvidencePolicy.ManagedChecksPassed(evidence with { RngSmoke = false }));
        Assert.False(EvidencePolicy.ManagedChecksPassed(evidence with { Rs256ValidAccepted = false }));
        Assert.False(EvidencePolicy.ManagedChecksPassed(evidence with { Rs256TamperedRejected = false }));
    }

    [Fact]
    public void RejectsUnauthenticatedOrObsoleteTls()
    {
        Assert.Equal(System.Security.Authentication.SslProtocols.Tls12, Probes.EncryptionTlsProtocols);
        var evidence = new TlsEvidence("example.test", 443, "Tls12", "Tls12", "observed-suite", true, true, true, "Online");
        Assert.True(EvidencePolicy.TlsChecksPassed(evidence));
        Assert.False(EvidencePolicy.TlsChecksPassed(evidence with { NegotiatedProtocol = "Tls13" }));
        Assert.False(EvidencePolicy.TlsChecksPassed(evidence with { AllowedProtocols = "Tls12|Tls13" }));
        Assert.False(EvidencePolicy.TlsChecksPassed(evidence with { NegotiatedProtocol = "Tls" }));
        Assert.False(EvidencePolicy.TlsChecksPassed(evidence with { CertificateValidated = false }));
        Assert.False(EvidencePolicy.TlsChecksPassed(evidence with { Authenticated = false }));
        Assert.False(EvidencePolicy.TlsChecksPassed(evidence with { Encrypted = false }));
        Assert.False(EvidencePolicy.TlsChecksPassed(evidence with { RevocationMode = "NoCheck" }));
    }
}
