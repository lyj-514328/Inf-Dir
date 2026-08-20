using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

if (args.Length != 1)
{
    Console.Error.WriteLine("Usage: wic-decoder.exe <image>");
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
