using Xunit;

namespace ReviewPortal.Tests;

public sealed class ContainerImageTests
{
    [Fact]
    public void RuntimeUsesSuppliedImageAndRunsAsNonRoot()
    {
        var docker = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "PolicySources", "Dockerfile"));
        var runtime = docker[docker.IndexOf("FROM ${RUNTIME_IMAGE} AS runtime", StringComparison.Ordinal)..];
        Assert.Contains("COPY --from=build /out .", runtime);
        Assert.Contains("USER 1654:1654", runtime);
        Assert.Contains("ENV ASPNETCORE_HTTP_PORTS=8080", runtime);
        Assert.Contains("""ENTRYPOINT ["dotnet", "ReviewPortal.dll"]""", runtime);
        Assert.DoesNotContain("OPENSSL_CONF", runtime);
    }
}
