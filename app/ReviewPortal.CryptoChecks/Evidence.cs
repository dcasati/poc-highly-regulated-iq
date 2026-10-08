using System.Runtime.InteropServices;

namespace ReviewPortal.CryptoChecks;

public sealed class Evidence
{
    public string Schema { get; } = "review-portal-crypto-observation/v1";
    public bool Qualified { get; } = false;
    public string Scope { get; } = "Diagnostic only; not CMVP, operating-environment, platform or approved-mode acceptance.";
    public string Platform { get; } = RuntimeInformation.OSDescription;
    public string Architecture { get; } = RuntimeInformation.ProcessArchitecture.ToString();
    public string Framework { get; } = RuntimeInformation.FrameworkDescription;
    public List<string> Errors { get; } = [];
    public List<string> Limitations { get; } =
    [
        "External certificate/security-policy, operating-environment and hosting/TLS-boundary acceptance is required.",
        "Algorithm fetches observe the default OpenSSL context; they do not trace each managed operation.",
        "A provider name, fips=yes property, status=1 or self-test return=1 is not FIPS certification.",
        "Full effective default-property string is not exposed by the public OpenSSL 3.3 API.",
        "SHA/RNG functional checks are not validated-module self-tests or statistical assurance.",
        "Managed RNG implementation and complete managed SHA/TLS provider paths are not proven by these observations.",
        "AES-GCM vectors prove functional answers only, not FIPS 140-3 certificate/approved-mode validation.",
        "Native AES-GCM fetches do not trace the actual .NET AesGcm or SslStream contexts.",
        "Hash/signature/RNG observations are supplemental diagnostics, not independent whole-app certification prerequisites."
    ];
    public NativeEvidence? Native { get; set; }
    public ManagedEvidence? Managed { get; set; }
    public EncryptionEvidence? Encryption { get; set; }
    public TlsEvidence? Tls { get; set; }
    public List<ModuleEvidence> Modules { get; } = [];
    public List<FileEvidence> Configuration { get; } = [];
}

public sealed class NativeEvidence
{
    public string RequestedLibrary { get; } = "libcrypto.so.3";
    public string? OpenSslVersion { get; set; }
    public bool? DefaultFipsPropertyEnabled { get; set; }
    public string FetchPropertyQuery { get; } = "NULL (observe existing default properties; no override)";
    public List<ProviderEvidence> Providers { get; } = [];
    public Dictionary<string, string> SelectedProviders { get; } = [];
    public string? EncryptionCipherProvider => SelectedProviders.GetValueOrDefault("EVP_CIPHER:AES-256-GCM");
}

public sealed record ProviderEvidence(string Name, string? Version, int? Status,
    bool SelfTestApiAvailable, bool SelfTestDispatchAvailable, int? SelfTestResult);
public sealed record ModuleEvidence(string FileName, string Sha256);
public sealed record FileEvidence(string Label, string Sha256);
public sealed record ManagedEvidence(bool Sha256KnownAnswer, bool RngSmoke, int RsaBits,
    bool Rs256ValidAccepted, bool Rs256TamperedRejected, string? GeneratedKeyProvider,
    string? ImportedPublicKeyProvider, string? ImportedVerifyContextProvider);
public sealed record EncryptionEvidence(int KeyBits, int NonceBytes, int TagBytes,
    IReadOnlyList<EncryptionVectorEvidence> Vectors);
public sealed record EncryptionVectorEvidence(string Case, int PlaintextBytes, int AadBytes,
    bool CiphertextMatches, bool TagMatches, bool KnownAnswerDecryptMatches, bool RoundTripMatches,
    bool CiphertextTamperRejected, bool TagTamperRejected, bool AadTamperRejected);
public sealed record TlsEvidence(string Host, int Port, string AllowedProtocols, string NegotiatedProtocol,
    string CipherSuite, bool Authenticated, bool Encrypted, bool CertificateValidated, string RevocationMode);

public static class EvidencePolicy
{
    public const int Unqualified = 2;
    public const int Failed = 3;
    public const int Unsupported = 4;
    public const int InvalidArguments = 64;

    public static int ExitCode(Evidence evidence, bool linux)
        => !linux ? Unsupported : evidence.Errors.Count > 0 ? Failed : Unqualified;

    public static bool HasSelfTestDispatch(IEnumerable<int> functionIds)
        => functionIds.Contains(1031);

    public static bool ManagedChecksPassed(ManagedEvidence evidence)
        => evidence.Sha256KnownAnswer && evidence.RngSmoke && evidence.RsaBits >= 2048
            && evidence.Rs256ValidAccepted && evidence.Rs256TamperedRejected;

    public static bool EncryptionChecksPassed(EncryptionEvidence evidence)
        => evidence.KeyBits == 256 && evidence.NonceBytes == 12 && evidence.TagBytes == 16
            && evidence.Vectors.Count == 2
            && evidence.Vectors.All(v => v.PlaintextBytes is >= 0 and <= EncryptionChecks.MaximumPlaintextBytes
                && v.AadBytes is >= 0 and <= EncryptionChecks.MaximumAadBytes
                && v.CiphertextMatches && v.TagMatches && v.KnownAnswerDecryptMatches && v.RoundTripMatches
                && v.CiphertextTamperRejected && v.TagTamperRejected && v.AadTamperRejected);

    public static bool TlsChecksPassed(TlsEvidence evidence)
        => evidence.Authenticated && evidence.Encrypted && evidence.CertificateValidated
            && evidence.AllowedProtocols == "Tls12" && evidence.NegotiatedProtocol == "Tls12"
            && evidence.RevocationMode == "Online";
}
