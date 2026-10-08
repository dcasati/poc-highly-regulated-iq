using System.Globalization;
using System.Net;

namespace ReviewPortal.CryptoChecks;

public sealed record Options(string? TlsHost, int TlsPort, int TimeoutSeconds, int TlsTimeoutSeconds)
{
    public static Options Parse(string[] args)
    {
        string? host = null;
        var port = 443;
        var timeout = 45;
        var tlsTimeout = 10;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        for (var i = 0; i < args.Length; i++)
        {
            var name = args[i];
            if (!seen.Add(name) || ++i >= args.Length)
                throw new ArgumentException("Invalid or duplicate option.");
            var value = args[i];
            switch (name)
            {
                case "--tls-host":
                    if (!IsHost(value)) throw new ArgumentException("Invalid TLS hostname.");
                    host = value;
                    break;
                case "--tls-port": port = Number(value, 1, 65535); break;
                case "--timeout-seconds": timeout = Number(value, 5, 120); break;
                case "--tls-timeout-seconds": tlsTimeout = Number(value, 1, 30); break;
                default: throw new ArgumentException("Unknown option.");
            }
        }
        if (host is null && (seen.Contains("--tls-port") || seen.Contains("--tls-timeout-seconds")))
            throw new ArgumentException("TLS options require an explicit hostname.");
        if (host is not null && tlsTimeout >= timeout)
            throw new ArgumentException("TLS timeout must be less than the overall deadline.");
        return new(host, port, timeout, tlsTimeout);
    }

    private static int Number(string value, int min, int max)
        => int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var result)
            && result >= min && result <= max ? result : throw new ArgumentException("Invalid numeric option.");

    public static bool IsHost(string value)
    {
        if (value.Length is < 1 or > 253 || value.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '.' and not '-'))
            return false;
        if (IPAddress.TryParse(value, out _)) return false;
        return value.Split('.').All(label => label.Length is >= 1 and <= 63
            && char.IsAsciiLetterOrDigit(label[0]) && char.IsAsciiLetterOrDigit(label[^1]));
    }
}
