using System.Text.Json;
using System.Text.Json.Serialization;

namespace InfDir.ProjectView;

internal static class CommandLine
{
    public static bool TryParse(
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
            string argument = args[index];
            if (argument == "--window-placement")
            {
                if (placement is not null || index + 1 >= args.Length)
                {
                    error = "--window-placement 需要且只能指定一个 JSON 参数。";
                    return false;
                }
                try
                {
                    placement = WindowPlacement.Parse(args[++index]);
                }
                catch (Exception exception)
                {
                    error = exception.Message;
                    return false;
                }
            }
            else if (argument.StartsWith('-'))
            {
                error = $"未知参数：{argument}";
                return false;
            }
            else if (file is null)
            {
                file = argument;
            }
            else
            {
                error = $"多余参数：{argument}";
                return false;
            }
        }

        if (file is null || !File.Exists(file))
        {
            error = file is null ? "用法：project-view.exe <FILE>" : $"文件不存在：{file}";
            return false;
        }
        return true;
    }
}

internal sealed class WindowPlacement
{
    private const int MinimumExtent = 64;
    public int X { get; init; }
    public int Y { get; init; }
    [JsonPropertyName("clientWidth")]
    public int ClientWidth { get; init; }
    [JsonPropertyName("clientHeight")]
    public int ClientHeight { get; init; }
    public bool Maximized { get; init; }
    public int Version { get; init; }

    public static WindowPlacement Parse(string json)
    {
        var placement = JsonSerializer.Deserialize<WindowPlacement>(json)
            ?? throw new FormatException("窗口位置参数为空。");
        if (placement.Version != 2)
        {
            throw new FormatException($"不支持的窗口位置协议版本：{placement.Version}");
        }
        if (placement.ClientWidth < MinimumExtent || placement.ClientHeight < MinimumExtent)
        {
            throw new FormatException("窗口尺寸无效。");
        }
        return placement;
    }
}
