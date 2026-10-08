using System.Security.Cryptography;
using System.Text.Json;
using ReviewPortal.CryptoChecks;
using Xunit;

namespace ReviewPortal.CryptoChecks.Tests;

public sealed class EncryptionTests
{
    [Fact]
    public void NativeObservationCannotBeConstructedOutsideLinux()
    {
        if (!OperatingSystem.IsLinux())
            Assert.Throws<PlatformNotSupportedException>(() => new NativeCrypto());
    }

    [Fact]
    public void ManagedAesGcm256MatchesBothPublishedNistAnswersAndRejectsTampering()
    {
        Assert.True(AesGcm.IsSupported);
        var evidence = EncryptionChecks.Run();
        Assert.True(EvidencePolicy.EncryptionChecksPassed(evidence));
        Assert.Equal(256, evidence.KeyBits);
        Assert.Equal(12, evidence.NonceBytes);
        Assert.Equal(16, evidence.TagBytes);
        Assert.Equal(2, evidence.Vectors.Count);
        Assert.Collection(evidence.Vectors,
            vector => { Assert.Equal(0, vector.PlaintextBytes); Assert.Equal(0, vector.AadBytes); },
            vector => { Assert.Equal(16, vector.PlaintextBytes); Assert.Equal(16, vector.AadBytes); });
    }

    [Fact]
    public void ExpectedBytesAreIndependentPublishedAnswersWithinFixedBounds()
    {
        Assert.Equal("bdc1ac884d332457a1d2664f168c76f0", EncryptionChecks.KnownAnswerVectors[0].TagHex);
        Assert.Equal("8995ae2e6df3dbf96fac7b7137bae67f", EncryptionChecks.KnownAnswerVectors[1].CiphertextHex);
        Assert.Equal("eca5aa77d51d4a0a14d9c51e1da474ab", EncryptionChecks.KnownAnswerVectors[1].TagHex);
        foreach (var vector in EncryptionChecks.KnownAnswerVectors)
        {
            Assert.Equal(32, Convert.FromHexString(vector.KeyHex).Length);
            Assert.Equal(12, Convert.FromHexString(vector.NonceHex).Length);
            Assert.Equal(16, Convert.FromHexString(vector.TagHex).Length);
            Assert.InRange(Convert.FromHexString(vector.PlaintextHex).Length, 0, 16);
            Assert.InRange(Convert.FromHexString(vector.AadHex).Length, 0, 16);
            Assert.Equal(vector.PlaintextHex.Length, vector.CiphertextHex.Length);
        }
        Assert.Equal(2, EncryptionChecks.KnownAnswerVectors.Select(v => (v.KeyHex, v.NonceHex)).Distinct().Count());
    }

    [Fact]
    public void RejectsAnyFailedEncryptionObservationOrInvalidBounds()
    {
        var evidence = EncryptionChecks.Run();
        var vector = evidence.Vectors[1];
        EncryptionVectorEvidence[] failures =
        [
            vector with { CiphertextMatches = false }, vector with { TagMatches = false },
            vector with { KnownAnswerDecryptMatches = false }, vector with { RoundTripMatches = false },
            vector with { CiphertextTamperRejected = false }, vector with { TagTamperRejected = false },
            vector with { AadTamperRejected = false }, vector with { PlaintextBytes = 17 },
            vector with { AadBytes = 17 }, vector with { PlaintextBytes = -1 }, vector with { AadBytes = -1 }
        ];
        foreach (var failure in failures)
            Assert.False(EvidencePolicy.EncryptionChecksPassed(evidence with { Vectors = [evidence.Vectors[0], failure] }));
        Assert.False(EvidencePolicy.EncryptionChecksPassed(evidence with { KeyBits = 128 }));
        Assert.False(EvidencePolicy.EncryptionChecksPassed(evidence with { NonceBytes = 8 }));
        Assert.False(EvidencePolicy.EncryptionChecksPassed(evidence with { TagBytes = 12 }));
        Assert.False(EvidencePolicy.EncryptionChecksPassed(evidence with { Vectors = [] }));
    }

    [Fact]
    public void EncryptionEvidenceNeverQualifiesAndDoesNotPrintKeyOrPlaintext()
    {
        var report = new Evidence { Encryption = EncryptionChecks.Run() };
        Assert.Equal(EvidencePolicy.Unqualified, EvidencePolicy.ExitCode(report, linux: true));
        Assert.False(report.Qualified);
        var json = JsonSerializer.Serialize(report);
        foreach (var vector in EncryptionChecks.KnownAnswerVectors)
        {
            Assert.DoesNotContain(vector.KeyHex, json);
            if (vector.PlaintextHex.Length > 0) Assert.DoesNotContain(vector.PlaintextHex, json);
        }
        Assert.Contains("do not trace the actual .NET AesGcm or SslStream", json);
    }

    [Fact]
    public void NativeEncryptionProviderFieldIsOnlyADefaultContextFetchObservation()
    {
        var native = new NativeEvidence();
        Assert.Null(native.EncryptionCipherProvider);
        native.SelectedProviders["EVP_CIPHER:AES-256-GCM"] = "observed-provider";
        Assert.Equal("observed-provider", native.EncryptionCipherProvider);
        Assert.Contains("no override", native.FetchPropertyQuery);
        Assert.False(new Evidence { Native = native }.Qualified);
    }
}
