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
            "chat-messages", "chat-empty", "chat-send", "chat-stop", "chat-new" })
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

    [Fact]
    public void AnswerFormattingUsesLocalDomRenderingAndKeepsUntrustedTextInert()
    {
        var script = Source("report.js");
        var html = Source("index.html");
        Assert.True(html.IndexOf("/report.js", StringComparison.Ordinal) <
            html.IndexOf("/portal.js", StringComparison.Ordinal));
        Assert.Contains("ReviewReport.render", Source("chat.js"));
        Assert.Contains("document.createTextNode", script);
        Assert.Contains("element.textContent = text", script);
        Assert.Contains("sources.has(id)", script);
        Assert.Contains("source.element.open = true", script);
        Assert.Contains("Reviewed field record", script);
        Assert.DoesNotContain("innerHTML", script);
        Assert.DoesNotContain("insertAdjacentHTML", script);
        Assert.DoesNotContain("eval(", script);
    }

    [Fact]
    public void ConversationIsTabLocalBoundedAndUsesCaseScopedRequests()
    {
        var script = Source("chat.js");
        var html = Source("index.html");
        Assert.Contains("CaseChat.create", Source("portal.js"));
        Assert.Contains("""role="log" aria-label="Application conversation" """, html);
        Assert.Contains("turns.slice(-6)", script);
        Assert.Contains("> 48000", script);
        Assert.Contains("question.length > 4000", script);
        Assert.Contains("12000", script);
        Assert.Contains("generation !== currentGeneration || caseId !== currentCase", script);
        Assert.Contains("controller.signal.aborted", script);
        Assert.Contains("new AbortController()", script);
        Assert.Contains("!event.isComposing", script);
        Assert.Contains("JSON.stringify({ question, history: context })", script);
        Assert.DoesNotContain("localStorage", script);
        Assert.DoesNotContain("sessionStorage", script);
        Assert.DoesNotContain("innerHTML", script);
    }
}
