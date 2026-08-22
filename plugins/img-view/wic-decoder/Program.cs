using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Media;
using System.Windows.Media.Imaging;

// WICComponentType::WICDecoder.
const uint WicDecoder = 0x00000001;

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

// Enumerate every WIC decoder component registered with Windows via
// IWICImagingFactory::CreateComponentEnumerator(WICDecoder).
//
// The enumerator is driven through its raw vtable instead of an RCW: a
// ComImport wrapper for IEnumUnknown misbehaves in the .NET runtime when the
// enumerator arrives through an out interface parameter, while the component
// objects themselves marshal fine as RCWs.
static unsafe int ListWicDecoders()
{
    try
    {
        var factory = (IWICImagingFactory)Activator.CreateInstance(
            Type.GetTypeFromCLSID(WicConstants.ClsidWicImagingFactory)!)!;

        // 0 = WICComponentEnumerateDefault (enabled components only).
        int hr = factory.CreateComponentEnumerator(WicDecoder, 0, out IntPtr enumerator);
        if (hr < 0)
        {
            Console.Error.WriteLine($"CreateComponentEnumerator failed: 0x{hr:X8}");
            return 1;
        }

        var decoders = new List<DecoderEntry>();
        var vtbl = *(void***)enumerator;
        var next = (delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr*, uint*, int>)vtbl[3];
        while (true)
        {
            IntPtr item = 0;
            uint fetched = 0;
            hr = next(enumerator, 1, &item, &fetched);
            if (hr != 0 || fetched == 0)
            {
                break; // S_OK or S_FALSE -> end of enumeration
            }

            try
            {
                var info = (IWICComponentInfo)Marshal.GetObjectForIUnknown(item);
                var entry = new DecoderEntry();
                if (info.GetCLSID(out entry.Clsid) < 0)
                {
                    continue; // broken component, skip
                }

                entry.Name = WicString(info.GetFriendlyName);
                if (entry.Name.Length == 0)
                {
                    entry.Name = $"{{{entry.Clsid}}}";
                }
                entry.Version = WicString(info.GetVersion);

                if (info is IWICBitmapCodecInfo codec)
                {
                    if (codec.GetContainerFormat(out Guid container) >= 0)
                    {
                        entry.Format = WicConstants.ContainerNames.TryGetValue(container, out string? fmt)
                            ? fmt
                            : $"{{{container}}}";
                    }
                    entry.Extensions = WicString(codec.GetFileExtensions);
                }
                decoders.Add(entry);
            }
            catch (COMException)
            {
                // Component that refuses to be inspected; keep enumerating.
            }
            finally
            {
                Marshal.Release(item);
            }
        }

        ((delegate* unmanaged[Stdcall]<IntPtr, uint>)vtbl[2])(enumerator); // Release

        decoders.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase));
        foreach (var decoder in decoders)
        {
            Console.WriteLine(
                $"{decoder.Name}\t{decoder.Format}\t{decoder.Version}\t{{{decoder.Clsid}}}\t{decoder.Extensions}");
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

// WIC string getters (GetFriendlyName/GetVersion/GetFileExtensions) report the
// required buffer length (including the NUL terminator) when called with a
// zero-sized buffer; read them in two passes.
static string WicString(WicStringGetter get)
{
    get(0, IntPtr.Zero, out uint len);
    if (len <= 1)
    {
        return "";
    }

    var buffer = Marshal.AllocCoTaskMem((int)len * sizeof(char));
    try
    {
        get(len, buffer, out _);
        return Marshal.PtrToStringUni(buffer) ?? "";
    }
    finally
    {
        Marshal.FreeCoTaskMem(buffer);
    }
}

static class WicConstants
{
    // CLSID_WICImagingFactory (class id; the interface IID is EC5EC8A9-...
    // and lives on the IWICImagingFactory ComImport attribute).
    public static readonly Guid ClsidWicImagingFactory = new("cacaf262-9370-4615-a13b-9f5539da4c0a");

    // WICGUID_ContainerFormat* for well-known containers, so the listing stays
    // readable; unknown formats fall back to their raw GUID.
    public static readonly IReadOnlyDictionary<Guid, string> ContainerNames = new Dictionary<Guid, string>
    {
        [new Guid("0AF1D87E-FCFE-4188-BDEB-A7906471CBE3")] = "BMP",
        [new Guid("1B7CFAF4-713F-473C-BBCD-6137425FAEAF")] = "PNG",
        [new Guid("A3A860C4-338F-4C17-919A-FBA4B5628F21")] = "ICO",
        [new Guid("0444F35F-587C-4570-9646-64DCD8F17573")] = "CUR",
        [new Guid("19E4A5AA-5662-4FC5-A0C0-1758028E1057")] = "JPEG",
        [new Guid("163BCC30-E2E9-4F0B-961D-A3E9FDB788A3")] = "TIFF",
        [new Guid("1F8A5601-7D4D-4CBD-9C82-1BC8D4EEB9A5")] = "GIF",
        [new Guid("57A37CAA-367A-4540-916B-F183C5093A4B")] = "JPEG-XR",
        [new Guid("9967CB95-2E85-4AC8-8CA2-83D7CCD425C9")] = "DDS",
        [new Guid("F3FF6D0D-38C0-41C4-B1FE-1F3824F17B84")] = "DNG",
        [new Guid("E1E62521-6787-405B-A339-500715B5763F")] = "HEIF",
        [new Guid("E094B0E2-67F2-45B3-B0EA-115337CA7CF3")] = "WebP",
        [new Guid("FE99CE60-F19C-433C-A3AE-00ACEFA9CA21")] = "RAW",
        [new Guid("FEC14E3F-427A-4736-AAE6-27ED84F69322")] = "JPEG-XL",
    };
}

sealed class DecoderEntry
{
    public string Name = "";
    public string Format = "";
    public string Version = "";
    public string Extensions = "";
    public Guid Clsid;
}

// IWICComponentInfo (23BC3F0A-698B-4357-886B-F24D50671334).
// Method order follows wincodec.h; keep it intact.
[ComImport, Guid("23BC3F0A-698B-4357-886B-F24D50671334"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IWICComponentInfo
{
    [PreserveSig] int GetComponentType(out uint pType);
    [PreserveSig] int GetCLSID(out Guid pclsid);
    [PreserveSig] int GetSigningStatus(out uint pStatus);
    [PreserveSig] int GetAuthor(uint cchAuthor, IntPtr wzAuthor, out uint pcchActual);
    [PreserveSig] int GetVendorGUID(out Guid pguidVendor);
    [PreserveSig] int GetVersion(uint cchVersion, IntPtr wzVersion, out uint pcchActual);
    [PreserveSig] int GetSpecVersion(uint cchSpecVersion, IntPtr wzSpecVersion, out uint pcchActual);
    [PreserveSig] int GetFriendlyName(uint cchFriendlyName, IntPtr wzFriendlyName, out uint pcchActual);
}

// IWICBitmapCodecInfo (E87A44C4-B76E-4C47-8B09-298EB12A2714), flattened:
// base IWICComponentInfo methods first, then its own, in wincodec.h order.
[ComImport, Guid("E87A44C4-B76E-4C47-8B09-298EB12A2714"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IWICBitmapCodecInfo
{
    [PreserveSig] int GetComponentType(out uint pType);
    [PreserveSig] int GetCLSID(out Guid pclsid);
    [PreserveSig] int GetSigningStatus(out uint pStatus);
    [PreserveSig] int GetAuthor(uint cchAuthor, IntPtr wzAuthor, out uint pcchActual);
    [PreserveSig] int GetVendorGUID(out Guid pguidVendor);
    [PreserveSig] int GetVersion(uint cchVersion, IntPtr wzVersion, out uint pcchActual);
    [PreserveSig] int GetSpecVersion(uint cchSpecVersion, IntPtr wzSpecVersion, out uint pcchActual);
    [PreserveSig] int GetFriendlyName(uint cchFriendlyName, IntPtr wzFriendlyName, out uint pcchActual);
    [PreserveSig] int GetContainerFormat(out Guid pguidContainerFormat);
    [PreserveSig] int GetPixelFormats(uint cFormats, IntPtr pguidPixelFormats, out uint pcActual);
    [PreserveSig] int GetColorManagementVersion(uint cch, IntPtr wz, out uint pcchActual);
    [PreserveSig] int GetDeviceManufacturer(uint cch, IntPtr wz, out uint pcchActual);
    [PreserveSig] int GetDeviceModels(uint cch, IntPtr wz, out uint pcchActual);
    [PreserveSig] int GetMimeTypes(uint cch, IntPtr wz, out uint pcchActual);
    [PreserveSig] int GetFileExtensions(uint cch, IntPtr wz, out uint pcchActual);
    [PreserveSig] int DoesSupportAnimation(out int pfSupportAnimation);
    [PreserveSig] int DoesSupportChromakey(out int pfSupportChromakey);
    [PreserveSig] int DoesSupportLossless(out int pfSupportLossless);
    [PreserveSig] int DoesSupportMultiframe(out int pfSupportMultiframe);
    [PreserveSig] int MatchesMimeType(IntPtr wzMimeType, out int pfMatches);
}

// IWICImagingFactory (ec5ec8a9-c395-4314-9c77-54d7a935ff70).
// Only the first 21 slots matter here: CreateComponentEnumerator is slot 21
// and everything before it must keep its exact position.
[ComImport, Guid("ec5ec8a9-c395-4314-9c77-54d7a935ff70"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IWICImagingFactory
{
    [PreserveSig] int CreateDecoderFromFilename(IntPtr wzFilename, IntPtr pguidVendor,
        uint dwDesiredAccess, int metadataOptions, out IntPtr ppIDecoder);
    [PreserveSig] int CreateDecoderFromStream(IntPtr pIStream, IntPtr pguidVendor,
        int metadataOptions, out IntPtr ppIDecoder);
    [PreserveSig] int CreateDecoderFromFileHandle(IntPtr hFile, IntPtr pguidVendor,
        int metadataOptions, out IntPtr ppIDecoder);
    [PreserveSig] int CreateComponentInfo(ref Guid clsidComponent, out IWICComponentInfo ppIInfo);
    [PreserveSig] int CreateDecoder(ref Guid guidContainerFormat, IntPtr pguidVendor,
        out IntPtr ppIDecoder);
    [PreserveSig] int CreateEncoder(ref Guid guidContainerFormat, IntPtr pguidVendor,
        out IntPtr ppIEncoder);
    [PreserveSig] int CreatePalette(out IntPtr ppIPalette);
    [PreserveSig] int CreateFormatConverter(out IntPtr ppIFormatConverter);
    [PreserveSig] int CreateBitmapScaler(out IntPtr ppIBitmapScaler);
    [PreserveSig] int CreateBitmapClipper(out IntPtr ppIBitmapClipper);
    [PreserveSig] int CreateBitmapFlipRotator(out IntPtr ppIBitmapFlipRotator);
    [PreserveSig] int CreateStream(out IntPtr ppIWICStream);
    [PreserveSig] int CreateColorContext(out IntPtr ppIWICColorContext);
    [PreserveSig] int CreateColorTransformer(out IntPtr ppIWICColorTransform);
    [PreserveSig] int CreateBitmap(uint uiWidth, uint uiHeight, ref Guid pixelFormat,
        int option, out IntPtr ppIBitmap);
    [PreserveSig] int CreateBitmapFromSource(IntPtr pIBitmapSource, int option, out IntPtr ppIBitmap);
    [PreserveSig] int CreateBitmapFromSourceRect(IntPtr pIBitmapSource, uint x, uint y,
        uint width, uint height, out IntPtr ppIBitmap);
    [PreserveSig] int CreateBitmapFromMemory(uint uiWidth, uint uiHeight, ref Guid pixelFormat,
        uint cbStride, uint cbBufferSize, IntPtr pbBuffer, out IntPtr ppIBitmap);
    [PreserveSig] int CreateBitmapFromHBITMAP(IntPtr hBitmap, IntPtr hPalette,
        int options, out IntPtr ppIBitmap);
    [PreserveSig] int CreateBitmapFromHICON(IntPtr hIcon, out IntPtr ppIBitmap);
    [PreserveSig] int CreateComponentEnumerator(uint componentTypes, uint options,
        out IntPtr ppIEnumUnknown);
    [PreserveSig] int CreateFastMetadataEncoderFromDecoder(IntPtr pIDecoder, out IntPtr ppIFastEncoder);
    [PreserveSig] int CreateFastMetadataEncoderFromFrameDecode(IntPtr pIFrameDecoder, out IntPtr ppIFastEncoder);
    [PreserveSig] int CreateQueryWriter(ref Guid guidMetadataFormat, IntPtr pguidVendor, out IntPtr ppIQueryWriter);
    [PreserveSig] int CreateQueryWriterFromReader(IntPtr pIQueryReader, IntPtr pguidVendor, out IntPtr ppIQueryWriter);
}

delegate int WicStringGetter(uint cch, IntPtr wz, out uint pcchActual);
