using System.Text.Json;
using System.Text.Json.Serialization;

namespace InfDir.EmailView;

internal static class CommandLine
{
    internal const string PlacementArgument = "--window-placement";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
    };

    public static bool TryParse(
        string[] args,
        out string? input,
        out WindowPlacement? placement,
        out string error)
    {
        input = null;
        placement = null;
        error = "";

        for (var index = 0; index < args.Length; index++)
        {
            var argument = args[index];
            if (argument == PlacementArgument)
            {
                if (++index >= args.Length)
                {
                    error = $"{PlacementArgument} requires a JSON value.";
                    return false;
                }

                try
                {
                    placement = JsonSerializer.Deserialize<WindowPlacement>(args[index], JsonOptions);
                }
                catch (JsonException exception)
                {
                    error = $"Invalid window placement: {exception.Message}";
                    return false;
                }

                if (placement is null || !placement.IsValid)
                {
                    error = "Window placement must use protocol version 2 and a client size of at least 64 x 64.";
                    return false;
                }

                continue;
            }

            if (argument.StartsWith("--", StringComparison.Ordinal))
            {
                error = $"Unknown option: {argument}";
                return false;
            }

            if (input is not null)
            {
                error = "Only one email file can be opened at a time.";
                return false;
            }

            try
            {
                input = Path.GetFullPath(argument);
            }
            catch (Exception exception) when (exception is ArgumentException or NotSupportedException)
            {
                error = $"Invalid file path: {exception.Message}";
                return false;
            }
        }

        if (input is null)
        {
            error = "Usage: email-view.exe <email-file> [--window-placement <JSON>]";
            return false;
        }

        return true;
    }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed class WindowPlacement
{
    [JsonPropertyName("version")]
    public int Version { get; init; }

    [JsonPropertyName("x")]
    public int X { get; init; }

    [JsonPropertyName("y")]
    public int Y { get; init; }

    [JsonPropertyName("clientWidth")]
    public int ClientWidth { get; init; }

    [JsonPropertyName("clientHeight")]
    public int ClientHeight { get; init; }

    [JsonPropertyName("maximized")]
    public bool Maximized { get; init; }

    [JsonIgnore]
    public bool IsValid => Version == 2 && ClientWidth >= 64 && ClientHeight >= 64;
}
