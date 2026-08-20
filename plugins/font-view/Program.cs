using System.Text.Json;
using System.Text.Json.Serialization;

namespace InfDir.FontView;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args is ["--self-test"])
        {
            try { FontPreparation.SelfTest(); return 0; }
            catch (Exception exception) { Console.Error.WriteLine(exception); return 1; }
        }

        if (!TryParse(args, out string? file, out WindowPlacement? placement, out string? error))
        {
            MessageBox.Show(error, "字体查看器", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }
        ApplicationConfiguration.Initialize();
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.Run(new FontViewerForm(file!, placement));
        return 0;
    }

    private static bool TryParse(
        string[] args,
        out string? file,
        out WindowPlacement? placement,
        out string? error)
    {
        file = null;
        placement = null;
        error = null;
        for (int index = 0; index < args.Length; index++)
        {
            if (args[index] == "--window-placement")
            {
                if (placement is not null || index + 1 >= args.Length)
                {
                    error = "--window-placement 需要且只能指定一个 JSON 参数。";
                    return false;
                }
                try { placement = WindowPlacement.Parse(args[++index]); }
                catch (Exception exception) { error = exception.Message; return false; }
            }
            else if (args[index].StartsWith('-'))
            {
                error = $"未知参数：{args[index]}";
                return false;
            }
            else if (file is null) file = args[index];
            else { error = $"多余参数：{args[index]}"; return false; }
        }
        if (file is null || !File.Exists(file))
        {
            error = file is null ? "用法：font-view.exe <FONT_FILE>" : $"文件不存在：{file}";
            return false;
        }
        return true;
    }
}

internal sealed class WindowPlacement
{
    public int Version { get; init; }
    public int X { get; init; }
    public int Y { get; init; }
    [JsonPropertyName("clientWidth")] public int ClientWidth { get; init; }
    [JsonPropertyName("clientHeight")] public int ClientHeight { get; init; }
    public bool Maximized { get; init; }

    public static WindowPlacement Parse(string json)
    {
        var value = JsonSerializer.Deserialize<WindowPlacement>(json)
            ?? throw new FormatException("窗口位置参数为空。");
        if (value.Version != 2 || value.ClientWidth < 64 || value.ClientHeight < 64)
            throw new FormatException("窗口位置参数无效。");
        return value;
    }
}
