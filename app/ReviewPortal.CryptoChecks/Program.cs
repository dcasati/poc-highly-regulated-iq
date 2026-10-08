using System.Text.Json;
using ReviewPortal.CryptoChecks;

Options options;
try { options = Options.Parse(args); }
catch (ArgumentException)
{
    Console.WriteLine("""{"qualified":false,"error":"invalid-arguments","usage":"[--timeout-seconds 5..120] [--tls-host DNS_HOST [--tls-port 1..65535] [--tls-timeout-seconds 1..30]]"}""");
    return EvidencePolicy.InvalidArguments;
}

var report = new Evidence();
if (!OperatingSystem.IsLinux())
{
    report.Errors.Add("unsupported-platform-linux-required");
    Emit(report);
    return EvidencePolicy.Unsupported;
}

// A hard process deadline also bounds blocking native operations/self-tests. Run only as an isolated diagnostic.
using var deadline = new Timer(_ =>
{
    Console.WriteLine("""{"qualified":false,"error":"overall-diagnostic-deadline-exceeded","partialEvidenceDiscarded":true}""");
    Environment.Exit(EvidencePolicy.Failed);
}, null, TimeSpan.FromSeconds(options.TimeoutSeconds), Timeout.InfiniteTimeSpan);

var stage = "load-libcrypto.so.3";
try
{
    using var native = new NativeCrypto();
    stage = "observe-native-default-context";
    report.Native = native.Observe();
    if (!report.Native.Providers.Any(p => p.Name == "symcryptprovider"))
        report.Errors.Add("expected-symcryptprovider-not-active");
    foreach (var provider in report.Native.Providers)
    {
        if (provider.Status != 1) report.Errors.Add("provider-status-missing-or-not-operational:" + provider.Name);
        if (provider.Version is null) report.Errors.Add("provider-version-unavailable:" + provider.Name);
        if (provider.SelfTestResult is not null and not 1) report.Errors.Add("provider-self-test-failed:" + provider.Name);
        if (!provider.SelfTestDispatchAvailable)
            report.Limitations.Add("No on-demand self-test dispatch: " + provider.Name + "; automatic SymCrypt self-tests are not attested here.");
        if (!provider.SelfTestApiAvailable)
            report.Errors.Add("provider-self-test-api-unavailable:" + provider.Name);
    }
    if (report.Errors.Count == 0)
    {
        stage = "managed-aes-gcm256-probes";
        report.Encryption = EncryptionChecks.Run();
        if (!EvidencePolicy.EncryptionChecksPassed(report.Encryption))
            report.Errors.Add("managed-aes-gcm256-functional-check-failed");
        stage = "managed-functional-and-rsa-provider-probes";
        report.Managed = Probes.Managed(native);
        if (!EvidencePolicy.ManagedChecksPassed(report.Managed))
            report.Errors.Add("managed-functional-check-failed");
    }
    report.Limitations.Add("Imported RSA key may be legacy (null provider); separate verify-context initialization is a surrogate, not a trace of .NET's disposed context.");
    if (options.TlsHost is not null && report.Errors.Count == 0)
    {
        try
        {
            report.Tls = await Probes.Tls(options);
            if (!EvidencePolicy.TlsChecksPassed(report.Tls)) report.Errors.Add("tls-check-failed");
        }
        catch (Exception exception)
        {
            report.Errors.Add("tls-probe-failed:" + exception.GetType().Name);
        }
    }
    else report.Limitations.Add("TLS not requested or skipped after failure; no TLS connection made by this harness.");
    stage = "mapped-module-receipts";
    Probes.ModuleReceipts(report);
    stage = "candidate-configuration-receipts";
    Probes.ConfigurationReceipts(report);
}
catch (Exception exception)
{
    // Native/cloud exception messages can contain secrets or endpoint details.
    report.Errors.Add(stage + "-failed:" + exception.GetType().Name);
}
deadline.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
Emit(report);
return EvidencePolicy.ExitCode(report, linux: true);

static void Emit(Evidence report)
    => Console.WriteLine(JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
