using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

if (args.Length == 1 && args[0] is "--list" or "-l")
{
    return ListWicDecoders();
}

if (args.Length != 1)
{
    Console.Error.WriteLine("Usage: wic-decoder.exe <image>");
    Console.Error.WriteLine("       wic-decoder.exe --list    enumerate WIC decoders");
    return 2;
}

try
{
    var decoder = BitmapDecoder.Create(
        new Uri(Path.GetFullPath(args[0]), UriKind.Absolute),
        BitmapCreateOptions.PreservePixelFormat,
        BitmapCacheOption.OnLoad);
    if (decoder.Frames.Count == 0)
    {
        throw new InvalidDataException("WIC returned no frames.");
    }

    var encoder = new PngBitmapEncoder();
    encoder.Frames.Add(BitmapFrame.Create(decoder.Frames[0]));
    using var png = new MemoryStream();
    encoder.Save(png);
    Console.OpenStandardOutput().Write(png.GetBuffer(), 0, checked((int)png.Length));
    return 0;
}
catch (Exception error)
{
    Console.Error.WriteLine(error.ToString());
    return 1;
}

// Enumerate every WIC decoder component registered with Windows.
// Windows.Graphics.Imaging exposes the WIC registry directly through
// BitmapDecoder.GetDecoderInformationEnumerator(); note that the WPF
// BitmapDecoder above decodes a single file, so the WinRT one is used
// fully qualified here.
static int ListWicDecoders()
{
    try
    {
        var decoders = Windows.Graphics.Imaging.BitmapDecoder
            .GetDecoderInformationEnumerator()
            .OrderBy(codec => codec.FriendlyName, StringComparer.OrdinalIgnoreCase)
            .ToList();
        foreach (var codec in decoders)
        {
            Console.WriteLine(
                $"{codec.FriendlyName}\t{{{codec.CodecId}}}\t{string.Join(",", codec.FileExtensions)}");
        }
        Console.Error.WriteLine($"{decoders.Count} decoder(s) listed.");
        return 0;
    }
    catch (Exception error)
    {
        Console.Error.WriteLine(error.ToString());
        return 1;
    }
}
