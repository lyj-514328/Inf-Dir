using System.Text;

namespace InfDir.EmailParse;

internal static class SelfTests
{
    public static int Run()
    {
        var root = Path.Combine(Path.GetTempPath(), $"inf-dir-email-parse-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            ParserReadsEml(root);
            ParserReadsEmlx(root);
            ParserReadsLegacyCodePageEml(root);
            ReportContainsAttachmentsAndFiles(root);
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"email-parse self-test failed: {exception.Message}");
            return 1;
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static void ParserReadsEml(string root)
    {
        var path = Path.Combine(root, "sample.eml");
        File.WriteAllText(path, SampleEml, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));

        var parsed = EmailParser.Parse(path);
        Assert(parsed.Document.Subject == "Viewer test", "EML subject");
        Assert(parsed.Document.From.Single().Address == "alice@example.com", "EML sender");
        Assert(parsed.Document.TextBody?.Contains("Plain body", StringComparison.Ordinal) == true, "EML body");
        Assert(parsed.Attachments.Single().Info.Name == "_CON.txt", "EML attachment name safety");
        Assert(Encoding.UTF8.GetString(parsed.Attachments.Single().Data) == "attachment", "EML attachment bytes");
    }

    private static void ParserReadsEmlx(string root)
    {
        var path = Path.Combine(root, "sample.emlx");
        var message = Encoding.UTF8.GetBytes(SampleEml);
        var prefix = Encoding.ASCII.GetBytes($"{message.Length}\n");
        var trailer = Encoding.UTF8.GetBytes("<?xml version=\"1.0\"?><plist></plist>");
        File.WriteAllBytes(path, [.. prefix, .. message, .. trailer]);

        var parsed = EmailParser.Parse(path);
        Assert(parsed.Document.Subject == "Viewer test", "EMLX subject");
        Assert(parsed.Attachments.Count == 1, "EMLX attachment count");
    }

    private static void ParserReadsLegacyCodePageEml(string root)
    {
        // Regression guard: legacy code pages (Big5 = CP950) require the
        // CodePagesEncodingProvider that Program.Main registers.
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var big5 = Encoding.GetEncoding("big5");
        var body = big5.GetBytes("中文測試正文");
        var path = Path.Combine(root, "big5.eml");
        File.WriteAllBytes(path, [
            .. Encoding.ASCII.GetBytes(
                "From: legacy@example.com\r\n" +
                "Subject: =?big5?B?" + Convert.ToBase64String(big5.GetBytes("中文主旨")) + "?=\r\n" +
                "MIME-Version: 1.0\r\n" +
                "Content-Type: text/plain; charset=big5\r\n" +
                "Content-Transfer-Encoding: 8BIT\r\n\r\n"),
            .. body,
        ]);

        var parsed = EmailParser.Parse(path);
        Assert(parsed.Document.Subject == "中文主旨", "Big5 subject");
        Assert(parsed.Document.TextBody?.Contains("中文測試正文") == true, "Big5 body");
    }

    private static void ReportContainsAttachmentsAndFiles(string root)
    {
        var emlPath = Path.Combine(root, "report-sample.eml");
        File.WriteAllText(emlPath, SampleEml, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        var staging = Path.Combine(root, "staging");
        Directory.CreateDirectory(staging);

        ReportWriter.Write(EmailParser.Parse(emlPath), staging);

        var report = File.ReadAllText(Path.Combine(staging, ReportWriter.ReportFileName));
        Assert(report.Contains("\"sourceFileName\":\"report-sample.eml\""), "report camelCase fields");
        Assert(report.Contains("\"attachments\":["), "report attachment list");
        Assert(!report.Contains("\"htmlBody\"", StringComparison.Ordinal), "null fields omitted");
        var attachmentBytes = File.ReadAllBytes(Path.Combine(
            staging,
            ReportWriter.AttachmentsDirectoryName,
            "0"));
        Assert(Encoding.UTF8.GetString(attachmentBytes) == "attachment", "attachment file bytes");
    }

    private static void Assert(bool condition, string name)
    {
        if (!condition)
        {
            throw new InvalidOperationException($"Self-test failed: {name}");
        }
    }

    private const string SampleEml = """
        From: Alice <alice@example.com>
        To: Bob <bob@example.com>
        Subject: Viewer test
        Date: Thu, 20 Aug 2026 10:00:00 +0800
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="inf-dir-boundary"

        --inf-dir-boundary
        Content-Type: text/plain; charset=utf-8

        Plain body
        --inf-dir-boundary
        Content-Type: text/plain; name="../CON.txt"
        Content-Disposition: attachment; filename="../CON.txt"
        Content-Transfer-Encoding: base64

        YXR0YWNobWVudA==
        --inf-dir-boundary--
        """;
}
