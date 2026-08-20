using System.Text.Json.Serialization;

namespace InfDir.EmailView;

internal sealed class ParsedEmail
{
    public required EmailDocument Document { get; init; }
    public required IReadOnlyList<EmailAttachment> Attachments { get; init; }

    public static ParsedEmail Error(string sourcePath, string message)
    {
        return new ParsedEmail
        {
            Document = new EmailDocument
            {
                SourceFileName = Path.GetFileName(sourcePath),
                SourcePath = sourcePath,
                Error = message,
            },
            Attachments = [],
        };
    }
}

internal sealed class EmailDocument
{
    public string SourceFileName { get; init; } = "";
    public string SourcePath { get; init; } = "";
    public string Subject { get; init; } = "";
    public IReadOnlyList<EmailAddress> From { get; init; } = [];
    public IReadOnlyList<EmailAddress> To { get; init; } = [];
    public IReadOnlyList<EmailAddress> Cc { get; init; } = [];
    public IReadOnlyList<EmailAddress> Bcc { get; init; } = [];
    public string? Date { get; init; }
    public string? HtmlBody { get; init; }
    public string? TextBody { get; init; }
    public IReadOnlyList<EmailAttachmentInfo> Attachments { get; init; } = [];
    public string? Error { get; init; }
}

internal sealed class EmailAddress
{
    public string Name { get; init; } = "";
    public string Address { get; init; } = "";
}

internal sealed class EmailAttachmentInfo
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required string ContentType { get; init; }
    public required long Size { get; init; }
    public bool Inline { get; init; }
    public string? ContentId { get; init; }
}

internal sealed class EmailAttachment
{
    public required EmailAttachmentInfo Info { get; init; }

    [JsonIgnore]
    public required byte[] Data { get; init; }
}
