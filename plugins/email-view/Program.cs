namespace InfDir.EmailView;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--self-test")
        {
            return SelfTests.Run();
        }

        if (!CommandLine.TryParse(args, out var input, out var placement, out var error))
        {
            MessageBox.Show(
                error,
                "Email View",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 2;
        }

        var parsed = EmailParser.ParseSafely(input!);

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new EmailViewerForm(parsed, placement));
        return 0;
    }
}
