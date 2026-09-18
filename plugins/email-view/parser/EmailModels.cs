using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace InfDir.EmailParse;

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
    public EmailAddress[] From { get; init; } = [];
    public EmailAddress[] To { get; init; } = [];
    public EmailAddress[] Cc { get; init; } = [];
    public EmailAddress[] Bcc { get; init; } = [];
    public string? Date { get; init; }
    public string? HtmlBody { get; init; }
    public string? TextBody { get; init; }
    public EmailAttachmentInfo[] Attachments { get; init; } = [];
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

[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(EmailDocument))]
internal partial class EmailJsonContext : JsonSerializerContext
{
}

internal static class ReportWriter
{
    public const string ReportFileName = "report.json";
    public const string AttachmentsDirectoryName = "attachments";

    /// <summary>
    /// Writes report.json plus one attachments/&lt;id&gt; file per attachment into
    /// the staging directory that the Rust shell serves.
    /// </summary>
    public static void Write(ParsedEmail email, string stagingDirectory)
    {
        var attachmentsDirectory = Path.Combine(stagingDirectory, AttachmentsDirectoryName);
        Directory.CreateDirectory(attachmentsDirectory);
        foreach (var attachment in email.Attachments)
        {
            File.WriteAllBytes(
                Path.Combine(attachmentsDirectory, attachment.Info.Id),
                attachment.Data);
        }

        var json = JsonSerializer.Serialize(email.Document, EmailJsonContext.Default.EmailDocument);
        File.WriteAllText(
            Path.Combine(stagingDirectory, ReportFileName),
            json,
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }
}
