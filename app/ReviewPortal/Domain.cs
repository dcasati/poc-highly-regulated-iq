using System.Text.Json;

namespace ReviewPortal;

public sealed record PortalOptions
{
    public required string TenantId { get; init; }
    public required string ClientId { get; init; }
    public required string ApiAudience { get; init; }
    public required string ApiScope { get; init; }
    public required string BlobEndpoint { get; init; }
    public required string ContentEndpoint { get; init; }
    public required string SearchEndpoint { get; init; }
    public required string OpenAIEndpoint { get; init; }
    public required string ChatDeployment { get; init; }
    public required string AnalyzerId { get; init; }
    public required string KnowledgeBase { get; init; }
    public required string KnowledgeSource { get; init; }
    public required string[] FieldNames { get; init; }
    public string OriginalContainer { get; init; } = "originals";
    public string StateContainer { get; init; } = "review-state";
    public string ApprovedContainer { get; init; } = "approved";
    public string EvidenceContainer { get; init; } = "reviewed-evidence";
    public string ProcessingLocation { get; init; } = "geography";
    public string? ManagedIdentityClientId { get; init; }
    public double ConfidenceThreshold { get; init; } = 0.9;
    public long MaxUploadBytes { get; init; } = 20 * 1024 * 1024;

    public void Validate()
    {
        if (!Guid.TryParse(TenantId, out _) || !Guid.TryParse(ClientId, out _) ||
            string.IsNullOrWhiteSpace(ApiAudience) || string.IsNullOrWhiteSpace(ApiScope) ||
            FieldNames.Length == 0 || FieldNames.Distinct().Count() != FieldNames.Length ||
            FieldNames.Any(string.IsNullOrWhiteSpace) ||
            ConfidenceThreshold is < 0 or > 1 || MaxUploadBytes is < 1024 or > 200 * 1024 * 1024 ||
            !new[] { "geography", "dataZone" }.Contains(ProcessingLocation))
            throw new InvalidOperationException("Invalid portal identity, extraction or upload configuration.");
        foreach (var endpoint in new[] { BlobEndpoint, ContentEndpoint, SearchEndpoint, OpenAIEndpoint })
            if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
                !string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
                throw new InvalidOperationException("Service endpoints must be HTTPS URLs without credentials or query strings.");
        var inferenceEndpoint = new Uri(OpenAIEndpoint);
        if (!inferenceEndpoint.Host.EndsWith(".openai.azure.com", StringComparison.OrdinalIgnoreCase) ||
            inferenceEndpoint.AbsolutePath != "/" || inferenceEndpoint.Port != 443)
            throw new InvalidOperationException("OpenAIEndpoint must be an Azure OpenAI account HTTPS root endpoint.");
        foreach (var name in new[] { ChatDeployment, AnalyzerId, KnowledgeBase, KnowledgeSource })
            if (string.IsNullOrWhiteSpace(name) || name.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '-' and not '_' and not '.'))
                throw new InvalidOperationException("Invalid service object name.");
        if (ChatDeployment.Length > 64)
            throw new InvalidOperationException("Chat deployment names must be at most 64 characters.");
        if (AnalyzerId.Length > 64 || AnalyzerId.Contains('-'))
            throw new InvalidOperationException("Custom Content Understanding analyzer IDs must be at most 64 characters without hyphens.");
    }
}

public sealed record ExtractedField(string Name, string OriginalValue, string Value, double? Confidence,
    string? Source, bool Reviewed = false)
{
    public bool NeedsAttention(double threshold) =>
        string.IsNullOrWhiteSpace(Value) || !Confidence.HasValue || Confidence < threshold;
}

public sealed record ReviewCase(Guid Id, string OwnerId, string FileName, DateTimeOffset CreatedAt,
    string Status, string? Operation = null, IReadOnlyList<ExtractedField>? Fields = null,
    string? ReviewerId = null, DateTimeOffset? ReviewedAt = null, string? FailureCode = null,
    DateTimeOffset? AnalysisStartedAt = null, string? OriginalSha256 = null);

public sealed record CaseSnapshot(ReviewCase Case, string Version);
public sealed record ReviewInput(Dictionary<string, string>? Values, string? Version);
public sealed record ChatMessage(string? Role, string? Content);
public sealed record ChatInput(string? Question, IReadOnlyList<ChatMessage?>? History = null);

public static class ChatContextRules
{
    public const int MaxQuestionCharacters = 4000;
    public const int MaxHistoryMessages = 12;
    public const int MaxUserMessageCharacters = 4000;
    public const int MaxAssistantMessageCharacters = 12000;
    public const int MaxHistoryCharacters = 48000;

    public static string? ValidationError(string? question, IReadOnlyList<ChatMessage?>? history)
    {
        if (string.IsNullOrWhiteSpace(question) || question.Length > MaxQuestionCharacters)
            return $"Enter a question of 1-{MaxQuestionCharacters} characters.";
        if (history is null) return null;
        if (history.Count > MaxHistoryMessages || history.Count % 2 != 0)
            return $"History must contain at most {MaxHistoryMessages} messages in complete user/assistant pairs.";
        var total = 0;
        for (var index = 0; index < history.Count; index++)
        {
            var message = history[index];
            var expectedRole = index % 2 == 0 ? "user" : "assistant";
            if (message is null || message.Role != expectedRole)
                return "History must alternate user then assistant, starting with user and ending with assistant.";
            var limit = expectedRole == "user" ? MaxUserMessageCharacters : MaxAssistantMessageCharacters;
            if (string.IsNullOrWhiteSpace(message.Content) || message.Content.Length > limit)
                return $"Each history {expectedRole} message must contain 1-{limit} characters.";
            total += message.Content.Length;
        }
        return total > MaxHistoryCharacters
            ? $"History must contain at most {MaxHistoryCharacters} characters in total."
            : null;
    }
}

public static class ReviewRules
{
    public static IReadOnlyList<ExtractedField> Extract(JsonElement result, IEnumerable<string> names)
    {
        if (result.ValueKind != JsonValueKind.Object ||
            !result.TryGetProperty("result", out var payload) || payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("contents", out var contents) || contents.ValueKind != JsonValueKind.Array)
            throw new InvalidOperationException("Analysis response has no document contents.");
        var documents = contents.EnumerateArray().ToArray();
        return names.Select(name =>
        {
            var matches = documents.Where(d => d.TryGetProperty("fields", out var fields) &&
                fields.TryGetProperty(name, out _)).Select(d => d.GetProperty("fields").GetProperty(name)).ToArray();
            if (matches.Length != 1)
                return new ExtractedField(name, "", "", null, matches.Length > 1 ? "Multiple conflicting segments; inspect original." : null);
            var field = matches[0];
            var value = field.EnumerateObject().FirstOrDefault(p => p.Name.StartsWith("value", StringComparison.Ordinal));
            var text = value.Value.ValueKind == JsonValueKind.Undefined ? "" :
                value.Value.ValueKind == JsonValueKind.String ? value.Value.GetString() ?? "" : value.Value.GetRawText();
            double? confidence = field.TryGetProperty("confidence", out var score) && score.ValueKind == JsonValueKind.Number && score.TryGetDouble(out var number)
                && double.IsFinite(number) && number is >= 0 and <= 1 ? number : null;
            return new ExtractedField(name, text, text, confidence,
                field.TryGetProperty("source", out var source) ? source.GetString() : null);
        }).ToArray();
    }

    public static ReviewCase Approve(ReviewCase item, ReviewInput input, string reviewer)
    {
        if (item.Status != "NeedsReview" || item.Fields is null || input.Values is null ||
            input.Values.Count != item.Fields.Count ||
            item.Fields.Any(f => !input.Values.ContainsKey(f.Name)) ||
            input.Values.Values.Any(v => v is null || v.Length > 4000))
            throw new InvalidOperationException("Review must explicitly confirm every configured field.");
        return item with
        {
            Status = "Publishing", ReviewerId = reviewer, ReviewedAt = DateTimeOffset.UtcNow,
            Fields = item.Fields.Select(f => f with { Value = input.Values[f.Name], Reviewed = true }).ToArray()
        };
    }

    public static string Filter(Guid caseId, string ownerId)
    {
        if (!Guid.TryParse(ownerId, out var owner))
            throw new InvalidOperationException("A tenant object ID is required.");
        return $"case_id eq '{caseId:D}' and owner_id eq '{owner:D}'";
    }

    public static Uri OperationUri(string location, string endpoint)
    {
        var expected = new Uri(endpoint.TrimEnd('/') + "/");
        if (!Uri.TryCreate(location, UriKind.Absolute, out var uri) ||
            uri.Scheme != "https" || uri.Authority != expected.Authority || !string.IsNullOrEmpty(uri.UserInfo) ||
            !uri.AbsolutePath.StartsWith("/contentunderstanding/", StringComparison.Ordinal))
            throw new InvalidOperationException("Unexpected analysis operation endpoint.");
        return uri;
    }
}
