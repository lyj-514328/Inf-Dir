namespace mupdf_view;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string? file = null;
        WindowPlacement? placement = null;
        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i];
            if (arg == WindowPlacement.Argument)
            {
                if (placement is not null)
                {
                    Console.Error.WriteLine($"[mupdf-view] duplicate option: {WindowPlacement.Argument}");
                    return 1;
                }
                if (i + 1 >= args.Length)
                {
                    Console.Error.WriteLine($"[mupdf-view] {WindowPlacement.Argument} requires a JSON value");
                    return 1;
                }
                try
                {
                    placement = WindowPlacement.FromJson(args[++i]);
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"[mupdf-view] {ex.Message}");
                    return 1;
                }
            }
            else if (arg.StartsWith('-') && arg != "-")
            {
                Console.Error.WriteLine($"[mupdf-view] unknown option: {arg}");
                return 1;
            }
            else
            {
                if (file is not null)
                {
                    Console.Error.WriteLine($"[mupdf-view] unexpected argument: {arg}");
                    return 1;
                }
                file = arg;
            }
        }

        if (file is null)
        {
            Console.Error.WriteLine(
                $"Usage: mupdf-view.exe <FILE> [{WindowPlacement.Argument} <JSON>]");
            return 1;
        }
        if (!File.Exists(file))
        {
            Console.Error.WriteLine($"[mupdf-view] file does not exist: {file}");
            return 1;
        }

        ApplicationConfiguration.Initialize();
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.Run(new ViewerForm(file, placement));
        return 0;
    }
}
