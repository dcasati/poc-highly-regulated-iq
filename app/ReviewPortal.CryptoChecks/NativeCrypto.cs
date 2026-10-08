using System.Runtime.InteropServices;

namespace ReviewPortal.CryptoChecks;

// Only the public OpenSSL 3 ABI is used. No provider-load or property-set APIs are bound.
public sealed class NativeCrypto : IDisposable
{
    private readonly nint library;

    public NativeCrypto()
    {
        if (!OperatingSystem.IsLinux() || !HasExpected64BitAbi)
            throw new PlatformNotSupportedException("Unsupported OpenSSL operating environment or structure layout.");
        library = NativeLibrary.Load("libcrypto.so.3");
    }

    public static bool HasExpected64BitAbi
        => nint.Size == 8 && Marshal.SizeOf<Dispatch>() == 16
            && Marshal.OffsetOf<Dispatch>(nameof(Dispatch.Function)) == 8
            && Marshal.SizeOf<Param>() == 40
            && Marshal.OffsetOf<Param>(nameof(Param.Type)) == 8
            && Marshal.OffsetOf<Param>(nameof(Param.Data)) == 16
            && Marshal.OffsetOf<Param>(nameof(Param.Size)) == 24
            && Marshal.OffsetOf<Param>(nameof(Param.ReturnSize)) == 32;

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate nint PointerInt(int value);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate nint Pointer1(nint value);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int Int1(nint value);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void Free1(nint value);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ProviderCallback(nint provider, nint data);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DoAll(nint context, ProviderCallback callback, nint data);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate nint Fetch(nint context, [MarshalAs(UnmanagedType.LPUTF8Str)] string name, nint properties);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int GetParams(nint provider, [In, Out] Param[] parameters);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate nint NewContext(nint context, nint key, nint properties);

    [StructLayout(LayoutKind.Sequential)]
    private struct Dispatch { public int Id; public nint Function; }
    [StructLayout(LayoutKind.Sequential)]
    private struct Param
    {
        public nint Key;
        public uint Type;
        public nint Data;
        public nuint Size;
        public nuint ReturnSize;
    }

    private T Bind<T>(string name) where T : Delegate
        => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(library, name));
    private static string? Text(nint pointer) => pointer == 0 ? null : Marshal.PtrToStringUTF8(pointer);
    private string? ProviderName(nint provider)
        => provider == 0 ? null : Text(Bind<Pointer1>("OSSL_PROVIDER_get0_name")(provider));

    public NativeEvidence Observe()
    {
        var result = new NativeEvidence
        {
            OpenSslVersion = Text(Bind<PointerInt>("OpenSSL_version")(0)),
            DefaultFipsPropertyEnabled = Bind<Int1>("EVP_default_properties_is_fips_enabled")(0) == 1
        };
        var providers = new List<nint>();
        ProviderCallback callback = (provider, _) =>
        {
            // Exceptions must not unwind through a native callback.
            try
            {
                if (providers.Count >= 64) return 0;
                providers.Add(provider);
                return 1;
            }
            catch { return 0; }
        };
        if (Bind<DoAll>("OSSL_PROVIDER_do_all")(0, callback, 0) != 1)
            throw new InvalidOperationException("Provider enumeration failed.");
        GC.KeepAlive(callback);
        // Do not execute self-tests while OpenSSL holds its provider-enumeration locks.
        // These handles remain owned by the process default context; this harness never unloads providers.
        foreach (var provider in providers)
        {
            var ids = new List<int>();
            var dispatch = Bind<Pointer1>("OSSL_PROVIDER_get0_dispatch")(provider);
            if (dispatch == 0) throw new InvalidOperationException("Provider dispatch unavailable.");
            var terminated = false;
            for (var i = 0; i < 128; i++)
            {
                var item = Marshal.PtrToStructure<Dispatch>(dispatch + i * Marshal.SizeOf<Dispatch>());
                if (item.Id == 0) { terminated = true; break; }
                if (item.Function != 0) ids.Add(item.Id);
            }
            if (!terminated) throw new InvalidOperationException("Provider dispatch exceeded bound.");
            var hasDispatch = EvidencePolicy.HasSelfTestDispatch(ids);
            var hasApi = NativeLibrary.TryGetExport(library, "OSSL_PROVIDER_self_test", out var api);
            var name = ProviderName(provider) ?? "unknown";
            var version = StringParameter(provider, "version");
            var status = StatusParameter(provider);
            // OpenSSL returns 1 even with no dispatch. Never report that no-op as a self-test.
            int? selfTest = hasApi && hasDispatch
                ? Marshal.GetDelegateForFunctionPointer<Int1>(api)(provider) : null;
            result.Providers.Add(new(name, version, status, hasApi, hasDispatch, selfTest));
        }
        if (result.Providers.Any(p => p.SelfTestResult is not null and not 1 || p.Status != 1))
            return result;
        ObserveFetch(result, "AES-256-GCM", "EVP_CIPHER");
        ObserveFetch(result, "AES-128-GCM", "EVP_CIPHER");
        ObserveFetch(result, "SHA256", "EVP_MD");
        ObserveFetch(result, "RSA", "EVP_SIGNATURE");
        ObserveFetch(result, "RSA", "EVP_KEYMGMT");
        // RAND_get0_public observes OpenSSL's current public DRBG, not .NET's OS RNG path.
        var context = Bind<Pointer1>("RAND_get0_public")(0);
        if (context == 0) throw new InvalidOperationException("Public DRBG unavailable.");
        var random = Bind<Pointer1>("EVP_RAND_CTX_get0_rand")(context);
        if (random == 0) throw new InvalidOperationException("Public DRBG algorithm unavailable.");
        result.SelectedProviders["OpenSslPublicDrbg"] = ProviderName(Bind<Pointer1>("EVP_RAND_get0_provider")(random))
            ?? throw new InvalidOperationException("DRBG provider unavailable.");
        return result;
    }

    private void ObserveFetch(NativeEvidence result, string algorithm, string prefix)
    {
        var fetched = Bind<Fetch>(prefix + "_fetch")(0, algorithm, 0);
        if (fetched == 0) throw new InvalidOperationException("Default-context algorithm fetch failed.");
        try
        {
            result.SelectedProviders[prefix + ":" + algorithm] =
                ProviderName(Bind<Pointer1>(prefix + "_get0_provider")(fetched))
                ?? throw new InvalidOperationException("Fetched provider unavailable.");
        }
        finally { Bind<Free1>(prefix + "_free")(fetched); }
    }

    private string? StringParameter(nint provider, string key)
    {
        var name = Marshal.StringToCoTaskMemUTF8(key);
        var buffer = Marshal.AllocHGlobal(nint.Size);
        try
        {
            Marshal.WriteIntPtr(buffer, 0);
            Param[] parameters = [new() { Key = name, Type = 6, Data = buffer, ReturnSize = nuint.MaxValue }, new()];
            if (Bind<GetParams>("OSSL_PROVIDER_get_params")(provider, parameters) != 1)
                throw new InvalidOperationException("Provider metadata query failed.");
            return Text(Marshal.ReadIntPtr(buffer));
        }
        finally { Marshal.FreeCoTaskMem(name); Marshal.FreeHGlobal(buffer); }
    }

    private int? StatusParameter(nint provider)
    {
        var name = Marshal.StringToCoTaskMemUTF8("status");
        var buffer = Marshal.AllocHGlobal(sizeof(int));
        try
        {
            Marshal.WriteInt32(buffer, -1);
            Param[] parameters = [new() { Key = name, Type = 1, Data = buffer, Size = sizeof(int), ReturnSize = nuint.MaxValue }, new()];
            if (Bind<GetParams>("OSSL_PROVIDER_get_params")(provider, parameters) != 1)
                throw new InvalidOperationException("Provider status query failed.");
            return parameters[0].ReturnSize == nuint.MaxValue ? null : Marshal.ReadInt32(buffer);
        }
        finally { Marshal.FreeCoTaskMem(name); Marshal.FreeHGlobal(buffer); }
    }

    public string? KeyProvider(nint key) => ProviderName(Bind<Pointer1>("EVP_PKEY_get0_provider")(key));

    public string? VerifyContextProvider(nint key)
    {
        var context = Bind<NewContext>("EVP_PKEY_CTX_new_from_pkey")(0, key, 0);
        if (context == 0) throw new InvalidOperationException("Verification context unavailable.");
        try
        {
            if (Bind<Int1>("EVP_PKEY_verify_init")(context) <= 0)
                throw new InvalidOperationException("Verification initialization failed.");
            return ProviderName(Bind<Pointer1>("EVP_PKEY_CTX_get0_provider")(context));
        }
        finally { Bind<Free1>("EVP_PKEY_CTX_free")(context); }
    }

    public void Dispose() => NativeLibrary.Free(library);
}
