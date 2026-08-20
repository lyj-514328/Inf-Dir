using System.Text.Json;
using System.Text.Json.Serialization;

namespace mupdf_view;

public sealed class WindowPlacement
{
    public const string Argument = "--window-placement";
    private const uint ProtocolVersion = 2;
    private const uint MinimumExtent = 64;

    public int X { get; init; }
    public int Y { get; init; }
    public uint ClientWidth { get; init; }
    public uint ClientHeight { get; init; }
    public bool Maximized { get; init; }

    private sealed class WirePlacement
    {
        public uint version { get; init; }
        public int x { get; init; }
        public int y { get; init; }
        [JsonPropertyName("clientWidth")]
        public uint clientWidth { get; init; }
        [JsonPropertyName("clientHeight")]
        public uint clientHeight { get; init; }
        public bool maximized { get; init; }
    }

    public static WindowPlacement FromJson(string value)
    {
        var wire = JsonSerializer.Deserialize<WirePlacement>(value)
            ?? throw new FormatException("invalid window placement: empty payload");
        if (wire.version != ProtocolVersion)
        {
            throw new FormatException($"unsupported window placement version: {wire.version}");
        }
        if (wire.clientWidth < MinimumExtent || wire.clientHeight < MinimumExtent)
        {
            throw new FormatException(
                $"window placement must be at least {MinimumExtent}x{MinimumExtent}");
        }
        return new WindowPlacement
        {
            X = wire.x,
            Y = wire.y,
            ClientWidth = wire.clientWidth,
            ClientHeight = wire.clientHeight,
            Maximized = wire.maximized,
        };
    }
}
