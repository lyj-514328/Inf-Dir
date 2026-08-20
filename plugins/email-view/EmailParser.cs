using MimeKit;
using MimeKit.Tnef;
using MsgReader.Outlook;
using OutlookAttachment = MsgReader.Outlook.Storage.Attachment;
using OutlookMessage = MsgReader.Outlook.Storage.Message;
using OutlookRecipient = MsgReader.Outlook.Storage.Recipient;
using OutlookSender = MsgReader.Outlook.Storage.Sender;

namespace InfDir.EmailView;

internal static class EmailParser
{
    private static readonly HashSet<string> ReservedWindowsNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    };

    public static ParsedEmail ParseSafely(string path)
    {
        try
        {
            return Parse(path);
        }
        catch (Exception exception)
        {
            return ParsedEmail.Error(path, FriendlyError(path, exception));
        }
    }

    internal static ParsedEmail Parse(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("The email file no longer exists.", path);
        }

        return Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".eml" => ParseMime(MimeMessage.Load(path), path),
            ".emlx" => ParseEmlx(path),
            ".msg" or ".oft" => ParseOutlook(path),
            ".dat" => ParseTnef(path),
            _ => throw new NotSupportedException("This email format is not supported."),
        };
    }

    private static ParsedEmail ParseEmlx(string path)
    {
        var data = File.ReadAllBytes(path);
        var newline = Array.IndexOf(data, (byte)'\n');
        if (newline < 1 || newline > 32)
        {
            throw new FormatException("The EMLX length header is missing or invalid.");
        }

        var headerLength = newline;
        if (data[newline - 1] == '\r')
        {
            headerLength--;
        }

        var header = System.Text.Encoding.ASCII.GetString(data, 0, headerLength).Trim();
        if (!long.TryParse(header, out var messageLength) ||
            messageLength <= 0 ||
            messageLength > data.LongLength - newline - 1 ||
            messageLength > int.MaxValue)
        {
            throw new FormatException("The EMLX message length is invalid.");
        }

        using var stream = new MemoryStream(data, newline + 1, (int)messageLength, writable: false);
        return ParseMime(MimeMessage.Load(stream), path);
    }

    private static ParsedEmail ParseTnef(string path)
    {
        using var stream = File.OpenRead(path);
        using var part = new TnefPart
        {
            Content = new MimeContent(stream, ContentEncoding.Default),
        };
        return ParseMime(part.ConvertToMessage(), path);
    }

    private static ParsedEmail ParseMime(MimeMessage message, string path)
    {
        var attachments = new List<EmailAttachment>();
        foreach (var entity in message.BodyParts)
        {
            switch (entity)
            {
                case MimePart part when part.IsAttachment || !string.IsNullOrWhiteSpace(part.ContentId):
                    {
                        if (part.Content is null)
                        {
                            break;
                        }
                        using var output = new MemoryStream();
                        part.Content.DecodeTo(output);
                        AddAttachment(
                            attachments,
                            part.FileName,
                            part.ContentType.MimeType,
                            output.ToArray(),
                            !part.IsAttachment || !string.IsNullOrWhiteSpace(part.ContentId),
                            part.ContentId);
                        break;
                    }
                case MessagePart part when part.IsAttachment:
                    {
                        if (part.Message is null)
                        {
                            break;
                        }
                        using var output = new MemoryStream();
                        part.Message.WriteTo(output);
                        AddAttachment(
                            attachments,
                            part.ContentDisposition?.FileName ?? part.ContentType.Name ?? "message.eml",
                            "message/rfc822",
                            output.ToArray(),
                            inline: false,
                            contentId: part.ContentId);
                        break;
                    }
            }
        }

        var date = message.Date == default ? null : message.Date.ToString("O");
        return Complete(
            path,
            message.Subject,
            MapAddresses(message.From.Mailboxes),
            MapAddresses(message.To.Mailboxes),
            MapAddresses(message.Cc.Mailboxes),
            MapAddresses(message.Bcc.Mailboxes),
            date,
            message.HtmlBody,
            message.TextBody,
            attachments);
    }

    private static ParsedEmail ParseOutlook(string path)
    {
        using var message = new OutlookMessage(path);
        var attachments = new List<EmailAttachment>();
        foreach (var item in message.Attachments)
        {
            switch (item)
            {
                case OutlookAttachment attachment:
                    {
                        var contentId = attachment.ContentId;
                        AddAttachment(
                            attachments,
                            attachment.FileName,
                            string.IsNullOrWhiteSpace(attachment.MimeType)
                                ? MimeTypes.GetMimeType(attachment.FileName ?? "attachment.bin")
                                : attachment.MimeType,
                            attachment.Data ?? [],
                            attachment.IsInline || !string.IsNullOrWhiteSpace(contentId),
                            contentId);
                        break;
                    }
                case OutlookMessage embeddedMessage:
                    {
                        using var output = new MemoryStream();
                        embeddedMessage.Save(output);
                        var name = embeddedMessage.FileName;
                        if (string.IsNullOrWhiteSpace(name))
                        {
                            name = string.IsNullOrWhiteSpace(embeddedMessage.Subject)
                                ? "attached-message.msg"
                                : $"{embeddedMessage.Subject}.msg";
                        }
                        AddAttachment(
                            attachments,
                            name,
                            "application/vnd.ms-outlook",
                            output.ToArray(),
                            inline: false,
                            contentId: null);
                        break;
                    }
            }
        }

        var recipients = message.Recipients;
        return Complete(
            path,
            message.Subject,
            MapSender(message.Sender),
            MapRecipients(recipients, RecipientType.To),
            MapRecipients(recipients, RecipientType.Cc),
            MapRecipients(recipients, RecipientType.Bcc),
            (message.SentOn ?? message.ReceivedOn)?.ToString("O"),
            message.BodyHtml,
            message.BodyText,
            attachments);
    }

    private static ParsedEmail Complete(
        string path,
        string? subject,
        IReadOnlyList<EmailAddress> from,
        IReadOnlyList<EmailAddress> to,
        IReadOnlyList<EmailAddress> cc,
        IReadOnlyList<EmailAddress> bcc,
        string? date,
        string? htmlBody,
        string? textBody,
        List<EmailAttachment> attachments)
    {
        return new ParsedEmail
        {
            Document = new EmailDocument
            {
                SourceFileName = Path.GetFileName(path),
                SourcePath = path,
                Subject = subject?.Trim() ?? "",
                From = from,
                To = to,
                Cc = cc,
                Bcc = bcc,
                Date = date,
                HtmlBody = string.IsNullOrWhiteSpace(htmlBody) ? null : htmlBody,
                TextBody = string.IsNullOrWhiteSpace(textBody) ? null : textBody,
                Attachments = attachments.Select(attachment => attachment.Info).ToArray(),
            },
            Attachments = attachments,
        };
    }

    private static void AddAttachment(
        List<EmailAttachment> attachments,
        string? name,
        string? contentType,
        byte[] data,
        bool inline,
        string? contentId)
    {
        var id = attachments.Count.ToString(System.Globalization.CultureInfo.InvariantCulture);
        var fallbackName = $"attachment-{attachments.Count + 1}";
        var safeName = SanitizeFileName(name, fallbackName);
        var normalizedContentId = contentId?.Trim().Trim('<', '>');
        var info = new EmailAttachmentInfo
        {
            Id = id,
            Name = safeName,
            ContentType = string.IsNullOrWhiteSpace(contentType) ? "application/octet-stream" : contentType,
            Size = data.LongLength,
            Inline = inline,
            ContentId = string.IsNullOrWhiteSpace(normalizedContentId) ? null : normalizedContentId,
        };
        attachments.Add(new EmailAttachment { Info = info, Data = data });
    }

    private static string SanitizeFileName(string? value, string fallback)
    {
        var candidate = string.IsNullOrWhiteSpace(value) ? fallback : Path.GetFileName(value);
        var invalid = Path.GetInvalidFileNameChars();
        candidate = new string(candidate.Select(character => invalid.Contains(character) ? '_' : character).ToArray())
            .Trim()
            .TrimEnd('.');
        if (string.IsNullOrWhiteSpace(candidate))
        {
            return fallback;
        }

        if (candidate.Length > 180)
        {
            var extension = Path.GetExtension(candidate);
            candidate = candidate[..Math.Max(1, 180 - extension.Length)] + extension;
        }

        if (ReservedWindowsNames.Contains(Path.GetFileNameWithoutExtension(candidate)))
        {
            candidate = $"_{candidate}";
        }
        return candidate;
    }

    private static IReadOnlyList<EmailAddress> MapAddresses(IEnumerable<MailboxAddress> addresses)
    {
        return addresses.Select(address => new EmailAddress
        {
            Name = address.Name ?? "",
            Address = address.Address ?? "",
        }).ToArray();
    }

    private static IReadOnlyList<EmailAddress> MapSender(OutlookSender? sender)
    {
        if (sender is null)
        {
            return [];
        }

        return [new EmailAddress { Name = sender.DisplayName ?? "", Address = sender.Email ?? "" }];
    }

    private static IReadOnlyList<EmailAddress> MapRecipients(
        IEnumerable<OutlookRecipient> recipients,
        RecipientType type)
    {
        return recipients
            .Where(recipient => recipient.Type == type)
            .Select(recipient => new EmailAddress
            {
                Name = recipient.DisplayName ?? "",
                Address = recipient.Email ?? "",
            })
            .ToArray();
    }

    private static string FriendlyError(string path, Exception exception)
    {
        if (Path.GetExtension(path).Equals(".dat", StringComparison.OrdinalIgnoreCase))
        {
            return "该 .dat 文件不是可识别的 TNEF 邮件。当前版本会临时把所有 .dat 交给邮件查看器。";
        }

        return exception switch
        {
            FileNotFoundException => "文件已不存在。",
            UnauthorizedAccessException => "没有权限读取该文件。",
            NotSupportedException => exception.Message,
            _ => $"无法解析邮件：{exception.Message}",
        };
    }
}
