using Azure.Core;
using ReviewPortal;
using System.Net;
using System.Text;
using System.Text.Json;
using Xunit;

namespace ReviewPortal.Tests;

public sealed class InferenceBoundaryTests
{
    private const string Owner = PortalFactory.Tenant;
    private static readonly Guid Id = Guid.Parse("22222222-2222-2222-2222-222222222222");
    private static readonly ReviewCase Item = new(Id, Owner, "synthetic.pdf", DateTimeOffset.UtcNow, "Approved",
        Fields: [new("Name", "UNREVIEWED_ORIGINAL", "Human correction", .5, "UNTRUSTED_SOURCE", true)]);

    private static object Reference(string id = "r1", string? caseId = null, string? owner = null,
        object? content = null) => new { id, sourceData = new
        {
            case_id = caseId ?? Id.ToString("D"), owner_id = owner ?? Owner,
            content = content ?? "Name: Synthetic applicant", arbitrary = "SOURCE_METADATA_INJECTION"
        }, arbitrary = "REFERENCE_ENVELOPE_INJECTION" };

    private static string Evidence(params object[] references) => JsonSerializer.Serialize(new
    {
        references = references.Length == 0 ? [Reference()] : references,
        response = "RESPONSE_ENVELOPE_INJECTION",
        activity = new[] { new { message = "ACTIVITY_ENVELOPE_INJECTION" } },
        extra = "ROOT_ENVELOPE_INJECTION"
    });

    private static string Completion(string answer = "Synthetic applicant", string[]? citations = null,
        string finish = "stop", object? refusal = null, object? toolCalls = null)
    {
        var message = new Dictionary<string, object>
        {
            ["role"] = "assistant",
            ["content"] = JsonSerializer.Serialize(new { answer, citations = citations ?? ["r1"] })
        };
        if (refusal is not null) message["refusal"] = refusal;
        if (toolCalls is not null) message["tool_calls"] = toolCalls;
        return JsonSerializer.Serialize(new { choices = new[] { new { finish_reason = finish, message } } });
    }

    // Valid completions omit tool_calls entirely, rather than supplying even an empty tool contract.
    private static string ValidCompletion(string answer = "Synthetic applicant", string[]? citations = null) =>
        JsonSerializer.Serialize(new { choices = new[] { new { finish_reason = "stop",
            message = new { role = "assistant", content = JsonSerializer.Serialize(new
                { answer, citations = citations ?? ["r1"] }) } } } });

    [Fact]
    public async Task OnlyValidatedSourceContentAndReviewedValuesEnterModelContext()
    {
        var handler = new Handler(Evidence(), ValidCompletion());
        var credential = new Credential();
        var result = JsonSerializer.SerializeToElement(await Cloud(handler, credential).Chat(Item, "Name?", CancellationToken.None));
        var input = handler.Bodies[1].GetProperty("messages")[1].GetProperty("content").GetString()!;
        Assert.Contains("Name: Synthetic applicant", input);
        Assert.Contains("Human correction", input);
        foreach (var marker in new[] { "SOURCE_METADATA_INJECTION", "REFERENCE_ENVELOPE_INJECTION",
            "RESPONSE_ENVELOPE_INJECTION", "ACTIVITY_ENVELOPE_INJECTION", "ROOT_ENVELOPE_INJECTION",
            "UNREVIEWED_ORIGINAL", "UNTRUSTED_SOURCE" })
            Assert.DoesNotContain(marker, input);
        Assert.Equal("Synthetic applicant [r1]", result.GetProperty("answer").GetString());
        Assert.Equal("r1", result.GetProperty("references")[0].GetProperty("id").GetString());
        Assert.Equal("ACTIVITY_ENVELOPE_INJECTION", result.GetProperty("activity")[0].GetProperty("message").GetString());
        Assert.Equal(["https://search.azure.com/.default", "https://ai.azure.com/.default"],
            credential.Scopes);
        Assert.False(handler.Bodies[1].TryGetProperty("tools", out _));
    }

    public static IEnumerable<object[]> InvalidEvidence()
    {
        yield return ["null"];
        yield return ["{"];
        yield return ["""{"references":null}"""];
        yield return ["""{"references":{}}"""];
        yield return ["""{"references":[]}"""];
        yield return [Evidence(Reference(owner: Guid.NewGuid().ToString("D")))];
        yield return [Evidence(Reference(caseId: Guid.NewGuid().ToString("D")))];
        yield return [Evidence(Reference(content: 42))];
        yield return [Evidence(Reference(content: " "))];
        yield return [Evidence(Reference(content: new string('a', 20001)))];
        yield return [Evidence(Reference(), Reference())];
        yield return [Evidence(Enumerable.Range(0, 11).Select(i => Reference($"r{i}")).ToArray())];
        yield return [Evidence(Reference("r1", content: new string('a', 10001)),
            Reference("r2", content: new string('a', 10000)))];
        foreach (var id in new[] { "", "bad[id]", "bad id", "é", new string('r', 65) })
            yield return [Evidence(Reference(id))];
        yield return ["""{"references":[{"id":"r1","sourceData":{"case_id":null,"owner_id":true,"content":"x"}}]}"""];
        yield return ["""{"references":[{"id":"r1"}]}"""];
        yield return ["""{"references":[{"id":"r1","sourceData":[]}]}"""];
        yield return ["""{"references":[false]}"""];
        yield return [Evidence().Replace("\"activity\":[", "\"activity\":null,\"unused\":[")];
        yield return [Evidence().Replace("\"activity\":[{", "\"activity\":[{\"error\":{\"code\":\"403\"},")];
        yield return [Evidence().Replace("\"references\":", "\"error\":{\"code\":\"failed\"},\"references\":")];
        yield return [Evidence().Replace("\"references\":", "\"references\":[],\"references\":")];
        yield return [Evidence().Replace("\"id\":\"r1\"", "\"id\":\"r1\",\"id\":\"r2\"")];
        yield return [Evidence().Replace("\"content\":\"Name: Synthetic applicant\"", "\"content\":\"Name: Synthetic applicant\",\"content\":\"injected\"")];
    }

    [Theory]
    [MemberData(nameof(InvalidEvidence))]
    public async Task InvalidEvidenceFailsBeforeInference(string evidence)
    {
        var handler = new Handler(evidence, ValidCompletion());
        await Assert.ThrowsAsync<InvalidOperationException>(() => Cloud(handler).Chat(Item, "Name?", CancellationToken.None));
        Assert.Single(handler.Bodies);
    }

    public static IEnumerable<object[]> InvalidCompletions()
    {
        yield return ["{"];
        yield return ["[]"];
        yield return ["""{"choices":[]}"""];
        yield return ["""{"choices":[{},{}]}"""];
        yield return [Completion(finish: "length")];
        yield return [Completion(finish: "content_filter")];
        yield return [Completion(finish: "tool_calls")];
        yield return [Completion(refusal: "Cannot answer")];
        yield return [Completion(toolCalls: Array.Empty<object>())];
        yield return [ValidCompletion().Replace("\"role\":\"assistant\"", "\"tool_calls\":null,\"role\":\"assistant\"")];
        yield return [Completion(toolCalls: new[] { new { function = new { name = "exfiltrate" } } })];
        yield return [ValidCompletion(citations: ["unknown"])];
        yield return [ValidCompletion(citations: ["r1", "r1"])];
        yield return [ValidCompletion(citations: [])];
        yield return [ValidCompletion(answer: "Fabricated [unknown] citation")];
        yield return [ValidCompletion(answer: "Known [r1] belongs only in structured citations")];
        yield return [ValidCompletion(answer: "Forged source (ref_id: fake)")];
        yield return [ValidCompletion(answer: "Forged source (REF_ID: fake)")];
        yield return [ValidCompletion(answer: " ")];
        yield return [ValidCompletion(answer: new string('a', 12001))];
        yield return [ValidCompletion(answer: new string('a', 11999))];
        yield return [RawContent("""{"answer":"x","citations":["r1"],"extra":"arbitrary"}""")];
        yield return [RawContent("""{"answer":"x","answer":"ambiguous","citations":["r1"]}""")];
        yield return [RawContent("""{"answer":"x","citations":[42]}""")];
        yield return [RawContent("""{"answer":"x","citations":null}""")];
        yield return [RawContent("""{"answer":"x","citations":["r1"]""")];
        yield return [RawContent("""{"answer":false,"citations":["r1"]}""")];
        yield return [RawContent("null")];
        yield return [RawContent(new string('a', 16001))];
        yield return ["""{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":null}}]}"""];
        yield return ["""{"choices":[{"finish_reason":"stop","message":{"role":"tool","content":"x"}}]}"""];
    }

    private static string RawContent(string content) => JsonSerializer.Serialize(new
    {
        choices = new[] { new { finish_reason = "stop", message = new { role = "assistant", content } } }
    });

    [Theory]
    [MemberData(nameof(InvalidCompletions))]
    public async Task InvalidCompletionCannotLeakAnAnswer(string completion)
    {
        var handler = new Handler(Evidence(), completion);
        await Assert.ThrowsAsync<InvalidOperationException>(() => Cloud(handler).Chat(Item, "Name?", CancellationToken.None));
        Assert.Equal(2, handler.Bodies.Count);
    }

    [Fact]
    public async Task OptionalActivityIsEmptyAndMultipleCurrentCitationsAreRendered()
    {
        var evidence = JsonSerializer.Serialize(new { references = new[] { Reference(), Reference("r2") } });
        var result = JsonSerializer.SerializeToElement(await Cloud(new Handler(evidence,
            ValidCompletion(citations: ["r2", "r1"]))).Chat(Item, "Name?", CancellationToken.None));
        Assert.Equal("Synthetic applicant [r2] [r1]", result.GetProperty("answer").GetString());
        Assert.Equal(0, result.GetProperty("activity").GetArrayLength());
    }

    [Fact]
    public async Task TenReferencesAndExactEvidenceBudgetAreAccepted()
    {
        var references = Enumerable.Range(0, 10).Select(i => Reference($"r{i}", content: new string('x', 2000))).ToArray();
        var result = JsonSerializer.SerializeToElement(await Cloud(new Handler(Evidence(references),
            ValidCompletion(citations: ["r9"]))).Chat(Item, "Name?", CancellationToken.None));
        Assert.Equal(10, result.GetProperty("references").GetArrayLength());
        Assert.Equal("Synthetic applicant [r9]", result.GetProperty("answer").GetString());
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task UnknownLengthResponseIsReadOnlyUpToBoundary(bool inference)
    {
        var handler = new Handler(inference ? Evidence() : new string(' ', 256 * 1024 + 1),
            inference ? new string(' ', 128 * 1024 + 1) : ValidCompletion()) { StreamResponses = true };
        await Assert.ThrowsAsync<InvalidOperationException>(() => Cloud(handler).Chat(Item, "Name?", CancellationToken.None));
        Assert.Equal(inference ? 2 : 1, handler.Bodies.Count);
        Assert.InRange(handler.LastStream!.BytesRead, 1, (inference ? 128 : 256) * 1024 + 1);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task DeclaredOversizedEnvelopeIsRejected(bool inference)
    {
        var handler = new Handler(inference ? Evidence() : new string(' ', 256 * 1024 + 1),
            inference ? new string(' ', 128 * 1024 + 1) : ValidCompletion());
        await Assert.ThrowsAsync<InvalidOperationException>(() => Cloud(handler).Chat(Item, "Name?", CancellationToken.None));
        Assert.Equal(inference ? 2 : 1, handler.Bodies.Count);
    }

    [Theory]
    [InlineData(false, HttpStatusCode.PartialContent)]
    [InlineData(false, HttpStatusCode.InternalServerError)]
    [InlineData(true, HttpStatusCode.TooManyRequests)]
    [InlineData(true, HttpStatusCode.PartialContent)]
    public async Task PartialAndCloudErrorsFailClosed(bool inference, HttpStatusCode status)
    {
        var handler = new Handler(Evidence(), ValidCompletion()) { ErrorAt = inference ? 2 : 1, Status = status };
        var error = await Assert.ThrowsAsync<HttpRequestException>(() => Cloud(handler).Chat(Item, "Name?", CancellationToken.None));
        Assert.Equal(status, error.StatusCode);
        Assert.Equal(inference ? 2 : 1, handler.Bodies.Count);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    public async Task DependencyTimeoutDoesNotReturnAnAnswer(int step)
    {
        var handler = new Handler(Evidence(), ValidCompletion()) { TimeoutAt = step };
        await Assert.ThrowsAsync<TaskCanceledException>(() => Cloud(handler).Chat(Item, "Name?", CancellationToken.None));
        Assert.Equal(step, handler.Bodies.Count);
    }

    [Fact]
    public async Task OversizedHumanFieldsFailBeforeCloudCalls()
    {
        var handler = new Handler(Evidence(), ValidCompletion());
        await Assert.ThrowsAsync<InvalidOperationException>(() => Cloud(handler).Chat(Item with
            { Fields = [new("Name", "", new string('a', 4001), null, null, true)] }, "Name?", CancellationToken.None));
        Assert.Empty(handler.Bodies);
    }

    [Fact]
    public async Task MixedReviewedAndUnreviewedStateFailsBeforeCloudCalls()
    {
        var handler = new Handler(Evidence(), ValidCompletion());
        await Assert.ThrowsAsync<InvalidOperationException>(() => Cloud(handler).Chat(Item with
            { Fields = [Item.Fields![0], new("Other", "", "UNREVIEWED_FIELD", null, null)] },
            "Name?", CancellationToken.None));
        Assert.Empty(handler.Bodies);
    }

    [Fact]
    public async Task CallerCancellationDoesNotStartRetrieval()
    {
        var handler = new Handler(Evidence(), ValidCompletion());
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Cloud(handler).Chat(Item, "Name?", cancelled.Token));
        Assert.Empty(handler.Bodies);
    }

    [Fact]
    public void OversizedDeploymentNameIsRejected() =>
        Assert.Throws<InvalidOperationException>(() => (ReviewTests.Options with { ChatDeployment = new string('d', 65) }).Validate());

    [Theory]
    [InlineData("https://foundry.services.ai.azure.com/api/projects/review")]
    [InlineData("https://account.openai.azure.com/openai/v1")]
    [InlineData("https://account.openai.azure.com?key=x")]
    [InlineData("https://account.openai.azure.com#fragment")]
    [InlineData("https://account.openai.azure.com:444")]
    [InlineData("https://account.openai.azure.com.attacker.example")]
    [InlineData("https://user@account.openai.azure.com")]
    public void InferenceEndpointCannotBeAProjectOrAlternateAuthority(string endpoint) =>
        Assert.Throws<InvalidOperationException>(() => (ReviewTests.Options with { OpenAIEndpoint = endpoint }).Validate());

    [Theory]
    [InlineData("")]
    [InlineData("deployment/name")]
    [InlineData("deployment?api-key=x")]
    public void InvalidDeploymentNameIsRejected(string deployment) =>
        Assert.Throws<InvalidOperationException>(() => (ReviewTests.Options with { ChatDeployment = deployment }).Validate());

    private static CloudServices Cloud(Handler handler, Credential? credential = null) =>
        new(new HttpClient(handler), credential ?? new Credential(), ReviewTests.Options);

    private sealed class Credential : TokenCredential
    {
        public List<string> Scopes { get; } = [];
        public override AccessToken GetToken(TokenRequestContext context, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Scopes.AddRange(context.Scopes);
            return new("synthetic-token", DateTimeOffset.UtcNow.AddMinutes(5));
        }
        public override ValueTask<AccessToken> GetTokenAsync(TokenRequestContext context, CancellationToken cancellationToken) =>
            ValueTask.FromResult(GetToken(context, cancellationToken));
    }

    private sealed class Handler(string evidence, string completion) : HttpMessageHandler
    {
        public List<JsonElement> Bodies { get; } = [];
        public bool StreamResponses { get; init; }
        public CountingStream? LastStream { get; private set; }
        public int ErrorAt { get; init; }
        public HttpStatusCode Status { get; init; }
        public int TimeoutAt { get; init; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct));
            Bodies.Add(json.RootElement.Clone());
            if (TimeoutAt == Bodies.Count) throw new TaskCanceledException("Synthetic timeout");
            var text = Bodies.Count == 1 ? evidence : completion;
            HttpContent content = new StringContent(text, Encoding.UTF8, "application/json");
            if (StreamResponses)
            {
                LastStream = new CountingStream(Encoding.UTF8.GetBytes(text));
                content = new StreamContent(LastStream);
            }
            return new HttpResponseMessage(ErrorAt == Bodies.Count ? Status : HttpStatusCode.OK) { Content = content };
        }
    }

    private sealed class CountingStream(byte[] bytes) : Stream
    {
        private readonly MemoryStream inner = new(bytes);
        public int BytesRead { get; private set; }
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override int Read(byte[] buffer, int offset, int count)
        {
            var read = inner.Read(buffer, offset, count);
            BytesRead += read;
            return read;
        }
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var read = inner.Read(buffer.Span);
            BytesRead += read;
            return ValueTask.FromResult(read);
        }
        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        protected override void Dispose(bool disposing)
        {
            if (disposing) inner.Dispose();
            base.Dispose(disposing);
        }
    }
}
