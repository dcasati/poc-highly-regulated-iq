using System.Security.Cryptography;

namespace ReviewPortal.CryptoChecks;

public sealed record GcmKnownAnswerVector(string Case, string KeyHex, string NonceHex,
    string PlaintextHex, string AadHex, string CiphertextHex, string TagHex);

public static class EncryptionChecks
{
    public const int KeyBytes = 32;
    public const int NonceBytes = 12;
    public const int TagBytes = 16;
    public const int MaximumPlaintextBytes = 16;
    public const int MaximumAadBytes = 16;

    // Public CAVP gcmEncryptExtIV256.rsp Count=0 cases, not secret/application keys.
    public static IReadOnlyList<GcmKnownAnswerVector> KnownAnswerVectors { get; } =
        Array.AsReadOnly<GcmKnownAnswerVector>(
        [
            new("NIST-CAVP-PT0-AAD0-Count0",
                "b52c505a37d78eda5dd34f20c22540ea1b58963cf8e5bf8ffa85f9f2492505b4",
                "516c33929df5a3284ff463d7", "", "", "",
                "bdc1ac884d332457a1d2664f168c76f0"),
            new("NIST-CAVP-PT128-AAD128-Count0",
                "92e11dcdaa866f5ce790fd24501f92509aacf4cb8b1339d50c9c1240935dd08b",
                "ac93a1a6145299bde902f21a",
                "2d71bcfa914e4ac045b2aa60955fad24",
                "1e0889016f67601c8ebea4943bc23ad6",
                "8995ae2e6df3dbf96fac7b7137bae67f",
                "eca5aa77d51d4a0a14d9c51e1da474ab")
        ]);

    public static EncryptionEvidence Run()
    {
        if (!AesGcm.IsSupported)
            throw new PlatformNotSupportedException("Managed AES-GCM unavailable.");
        var observations = KnownAnswerVectors.Select(Observe).ToArray();
        return new(KeyBytes * 8, NonceBytes, TagBytes, observations);
    }

    private static EncryptionVectorEvidence Observe(GcmKnownAnswerVector vector)
    {
        if (vector.KeyHex.Length != KeyBytes * 2 || vector.NonceHex.Length != NonceBytes * 2
            || vector.TagHex.Length != TagBytes * 2
            || vector.PlaintextHex.Length > MaximumPlaintextBytes * 2 || vector.PlaintextHex.Length % 2 != 0
            || vector.AadHex.Length > MaximumAadBytes * 2 || vector.AadHex.Length % 2 != 0
            || vector.CiphertextHex.Length != vector.PlaintextHex.Length)
            throw new InvalidOperationException("AES-GCM vector exceeded diagnostic bounds.");
        var key = Convert.FromHexString(vector.KeyHex);
        var nonce = Convert.FromHexString(vector.NonceHex);
        var plain = Convert.FromHexString(vector.PlaintextHex);
        var aad = Convert.FromHexString(vector.AadHex);
        var expectedCipher = Convert.FromHexString(vector.CiphertextHex);
        var expectedTag = Convert.FromHexString(vector.TagHex);
        var cipher = new byte[plain.Length];
        var tag = new byte[TagBytes];
        var knownAnswerPlain = new byte[plain.Length];
        var roundTripPlain = new byte[plain.Length];
        var changedCipher = Changed(expectedCipher);
        var changedTag = Changed(expectedTag);
        var changedAad = Changed(aad);
        try
        {
            using var aes = new AesGcm(key, TagBytes);
            aes.Encrypt(nonce, plain, cipher, tag, aad);
            // Decrypt the independent published answer, not just output from this encrypt call.
            aes.Decrypt(nonce, expectedCipher, expectedTag, knownAnswerPlain, aad);
            aes.Decrypt(nonce, cipher, tag, roundTripPlain, aad);
            return new(vector.Case, plain.Length, aad.Length,
                cipher.SequenceEqual(expectedCipher), tag.SequenceEqual(expectedTag),
                knownAnswerPlain.SequenceEqual(plain), roundTripPlain.SequenceEqual(plain),
                Rejects(aes, nonce, changedCipher, expectedTag, aad),
                Rejects(aes, nonce, expectedCipher, changedTag, aad),
                Rejects(aes, nonce, expectedCipher, expectedTag, changedAad));
        }
        finally
        {
            foreach (var buffer in new[] { key, nonce, plain, aad, expectedCipher, expectedTag,
                cipher, tag, knownAnswerPlain, roundTripPlain, changedCipher, changedTag, changedAad })
                CryptographicOperations.ZeroMemory(buffer);
        }
    }

    private static byte[] Changed(byte[] original)
    {
        var changed = original.Length == 0 ? new byte[1] : original.ToArray();
        changed[0] ^= 1;
        return changed;
    }

    private static bool Rejects(AesGcm aes, byte[] nonce, byte[] cipher, byte[] tag, byte[] aad)
    {
        var output = new byte[cipher.Length];
        try
        {
            aes.Decrypt(nonce, cipher, tag, output, aad);
            return false;
        }
        catch (AuthenticationTagMismatchException) { return true; }
        finally { CryptographicOperations.ZeroMemory(output); }
    }
}
