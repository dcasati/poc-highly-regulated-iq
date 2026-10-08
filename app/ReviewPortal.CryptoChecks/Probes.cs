using System.Net.Security;
using System.Net.Sockets;
using System.Runtime.Versioning;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace ReviewPortal.CryptoChecks;

public static class Probes
{
    public const SslProtocols EncryptionTlsProtocols = SslProtocols.Tls12;

    [SupportedOSPlatform("linux")]
    public static ManagedEvidence Managed(NativeCrypto native)
    {
        var sha = Convert.ToHexString(SHA256.HashData("abc"u8))
            == "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD";
        var random = RandomNumberGenerator.GetBytes(32);
        var otherRandom = RandomNumberGenerator.GetBytes(32);
        var rng = random.Any(b => b != 0) && !random.SequenceEqual(otherRandom);
        CryptographicOperations.ZeroMemory(random);
        CryptographicOperations.ZeroMemory(otherRandom);
        // Transient synthetic signing material; never output key, signature or random bytes.
        using var signer = new RSAOpenSsl(2048);
        using var verifier = new RSAOpenSsl();
        verifier.ImportParameters(signer.ExportParameters(false));
        var hash = SHA256.HashData("synthetic-rs256-qualification-probe"u8);
        var signature = signer.SignHash(hash, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        var valid = verifier.VerifyHash(hash, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        hash[0] ^= 1;
        var rejected = !verifier.VerifyHash(hash, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        // Do not pass a .NET-owned EVP pointer into a potentially different OpenSSL installation.
        if (MappedCryptoModules().Count(path => Path.GetFileName(path).StartsWith("libcrypto.so", StringComparison.Ordinal)) != 1)
            throw new InvalidOperationException("Multiple or missing OpenSSL mappings.");
        using var generated = signer.DuplicateKeyHandle();
        using var imported = verifier.DuplicateKeyHandle();
        return new(sha, rng, verifier.KeySize, valid, rejected,
            native.KeyProvider(generated.DangerousGetHandle()), native.KeyProvider(imported.DangerousGetHandle()),
            native.VerifyContextProvider(imported.DangerousGetHandle()));
    }

    public static async Task<TlsEvidence> Tls(Options options)
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(options.TlsTimeoutSeconds));
        using var client = new TcpClient();
        await client.ConnectAsync(options.TlsHost!, options.TlsPort, deadline.Token);
        using var stream = new SslStream(client.GetStream(), leaveInnerStreamOpen: false);
        await stream.AuthenticateAsClientAsync(new SslClientAuthenticationOptions
        {
            TargetHost = options.TlsHost!,
            EnabledSslProtocols = EncryptionTlsProtocols,
            CertificateRevocationCheckMode = X509RevocationMode.Online,
            AllowRenegotiation = false
        }, deadline.Token);
        return new(options.TlsHost!, options.TlsPort, "Tls12", stream.SslProtocol.ToString(),
            stream.NegotiatedCipherSuite.ToString(), stream.IsAuthenticated, stream.IsEncrypted,
            true, "Online");
    }

    public static void ModuleReceipts(Evidence evidence)
    {
        var paths = MappedCryptoModules();
        if (paths.Count(path => Path.GetFileName(path).StartsWith("libcrypto.so", StringComparison.Ordinal)) != 1)
            evidence.Errors.Add("mapped-libcrypto-identity-missing-or-ambiguous");
        foreach (var path in paths)
        {
            using var file = File.OpenRead(path);
            evidence.Modules.Add(new(Path.GetFileName(path), Convert.ToHexString(SHA256.HashData(file))));
        }
    }

    private static string[] MappedCryptoModules()
        => File.ReadLines("/proc/self/maps").Select(line => line.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            .Where(parts => parts.Length >= 6).Select(parts => parts[5])
            .Where(path => path.StartsWith('/') && RelevantModule(Path.GetFileName(path)))
            .Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray();

    private static bool RelevantModule(string name)
        => name.StartsWith("libcrypto.so", StringComparison.Ordinal)
            || name.StartsWith("libssl.so", StringComparison.Ordinal)
            || name.Contains("symcrypt", StringComparison.OrdinalIgnoreCase)
            || name == "System.Security.Cryptography.Native.OpenSsl.so"
            || name == "libSystem.Security.Cryptography.Native.OpenSsl.so";

    public static void ConfigurationReceipts(Evidence evidence)
    {
        foreach (var path in new[] { "/etc/pki/tls/openssl.cnf", "/etc/pki/tls/symcrypt_prov.cnf", "/app/openssl-tls.cnf", "/etc/os-release" })
        {
            if (!File.Exists(path)) { evidence.Limitations.Add("Receipt file absent: " + path); continue; }
            using var file = File.OpenRead(path);
            evidence.Configuration.Add(new(path, Convert.ToHexString(SHA256.HashData(file))));
        }
        evidence.Limitations.Add("Configuration hashes identify candidate files, not proof they were loaded; overrides/includes are not dumped.");
    }
}
