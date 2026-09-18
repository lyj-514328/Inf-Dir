using System.Text;

namespace InfDir.EmailParse;

internal static class Program
{
    private static int Main(string[] args)
    {
        // MsgReader and MimeKit resolve legacy mail code pages (Big5, GB2312,
        // Windows-1252, ...) through Encoding.GetEncoding, which only works
        // after the CodePages provider is registered.
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

        if (args.Length == 1 && args[0] == "--self-test")
        {
            return SelfTests.Run();
        }

        if (!TryParse(args, out var file, out var output, out var error))
        {
            Console.Error.WriteLine($"email-parse: {error}");
            return 2;
        }

        var parsed = EmailParser.ParseSafely(file!);
        try
        {
            ReportWriter.Write(parsed, output!);
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"email-parse: cannot write report: {exception.Message}");
            return 3;
        }

        return 0;
    }

    private static bool TryParse(
        string[] args,
        out string? file,
        out string? output,
        out string error)
    {
        file = null;
        output = null;
        error = "";

        for (var index = 0; index < args.Length; index++)
        {
            if (args[index] == "--out")
            {
                if (output is not null || index + 1 >= args.Length)
                {
                    error = "--out requires exactly one directory argument.";
                    return false;
                }
                output = args[++index];
            }
            else if (args[index].StartsWith('-'))
            {
                error = $"unknown option: {args[index]}";
                return false;
            }
            else if (file is null)
            {
                file = args[index];
            }
            else
            {
                error = $"unexpected argument: {args[index]}";
                return false;
            }
        }

        if (file is null || output is null)
        {
            error = "usage: email-parse.exe <EMAIL_FILE> --out <STAGING_DIR>";
            return false;
        }
        if (!Directory.Exists(output))
        {
            error = $"output directory does not exist: {output}";
            return false;
        }
        return true;
    }
}
