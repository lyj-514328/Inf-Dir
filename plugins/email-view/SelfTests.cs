using System.Text;

namespace InfDir.EmailView;

internal static class SelfTests
{
    public static int Run()
    {
        var root = Path.Combine(Path.GetTempPath(), $"inf-dir-email-view-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            ParserReadsEml(root);
            ParserReadsEmlx(root);
            PlacementRequiresProtocolV2();
            return 0;
        }
        catch
        {
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

    private static void PlacementRequiresProtocolV2()
    {
        var valid = new[]
        {
            "sample.eml",
            CommandLine.PlacementArgument,
            "{\"version\":2,\"x\":10,\"y\":20,\"clientWidth\":800,\"clientHeight\":600,\"maximized\":false}",
        };
        Assert(CommandLine.TryParse(valid, out _, out var placement, out _), "valid placement");
        Assert(placement?.ClientWidth == 800, "placement width");

        var unknownField = new[]
        {
            "sample.eml",
            CommandLine.PlacementArgument,
            "{\"version\":2,\"x\":10,\"y\":20,\"clientWidth\":800,\"clientHeight\":600,\"extra\":true}",
        };
        Assert(!CommandLine.TryParse(unknownField, out _, out _, out _), "unknown placement field");
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
