namespace InfDir.ProjectView;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args is ["--self-test"])
        {
            try { ProjectModel.SelfTest(); return 0; }
            catch (Exception exception) { Console.Error.WriteLine(exception); return 1; }
        }

        if (!CommandLine.TryParse(args, out string? file, out WindowPlacement? placement, out string? error))
        {
            MessageBox.Show(error, "Project 查看器", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }

        ProjectModel model;
        try
        {
            model = ProjectModel.Load(file!);
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                $"无法打开工程文件：{exception.Message}",
                "Project 查看器",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }

        ApplicationConfiguration.Initialize();
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.Run(new ProjectViewerForm(model, placement));
        return 0;
    }
}
