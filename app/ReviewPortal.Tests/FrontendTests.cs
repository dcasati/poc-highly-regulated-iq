using System.Text.RegularExpressions;
using Xunit;

namespace ReviewPortal.Tests;

public sealed class FrontendTests
{
    private static string Source(string name) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "FrontendSources", name));

    [Fact]
    public void WorkspaceKeepsNeutralBrandingAndLocalBrowserAssets()
    {
        var html = Source("index.html");
        Assert.Contains("<title>Private document review</title>", html);
        Assert.Contains("Secure application services", html);
        Assert.Contains("Synthetic test use only", html);
        foreach (Match attribute in Regex.Matches(html, "(?:src|href)=\"([^\"]+)\""))
            Assert.True(attribute.Groups[1].Value.StartsWith('/') ||
                attribute.Groups[1].Value.StartsWith('#'));
        var ids = Regex.Matches(html, "\\bid=\"([^\"]+)\"")
            .Select(match => match.Groups[1].Value).ToArray();
        Assert.Equal(ids.Length, ids.Distinct().Count());
        foreach (var id in new[] { "signin", "notice", "upload", "pdf", "refresh", "cases",
            "state", "original", "retry", "review", "fields", "approve", "chat", "question",
            "answer", "references" })
            Assert.Contains(id, ids);
    }

    [Fact]
    public void ReviewRemainsAccessibleAndKeepsValueAndEvidenceColumnsSeparate()
    {
        var html = Source("index.html");
        var css = Source("style.css");
        var script = Source("portal.js");
        Assert.Contains("class=\"skip-link\" href=\"#main-content\"", html);
        Assert.Contains("id=\"main-content\" tabindex=\"-1\"", html);
        Assert.Contains("""scope="col">Value to confirm""", html);
        Assert.Contains("table-layout: fixed", css);
        Assert.Contains(".column-value { width: 35%; }", css);
        Assert.Contains("[hidden] { display: none !important; }", css);
        Assert.Contains("""name.scope = "row";""", script);
        Assert.Contains("""value.dataset.label = "Value to confirm";""", script);
        Assert.Contains("""confirm.dataset.label = "Confirmed";""", script);
        Assert.Contains("if (version === snapshot.version && previous === id) return;", script);
    }

    [Fact]
    public void CasePollingUpdatesTheApplicationListWithoutResettingHumanReview()
    {
        var script = Source("portal.js");
        Assert.Contains("button.dataset.caseId = item.id;", script);
        Assert.Contains("button.dataset.caseId === id", script);
        Assert.Contains("snapshot.case.status", script);
        Assert.Contains("""button.setAttribute("aria-current", "true")""", script);
        Assert.Contains("""input.disabled = snapshot.case.status !== "NeedsReview";""", script);
        Assert.Contains("""checkbox.required = true""", script);
    }
}
