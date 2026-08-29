#include <windows.h>
#include <wincodec.h>
#include <objidl.h>
#include <wrl/client.h>

#include <algorithm>
#include <fcntl.h>
#include <iomanip>
#include <iostream>
#include <io.h>
#include <sstream>
#include <string>
#include <vector>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "windowscodecs.lib")

using Microsoft::WRL::ComPtr;

namespace {

std::string HResultText(HRESULT hr) {
  std::ostringstream out;
  out << "0x" << std::uppercase << std::hex << std::setw(8) << std::setfill('0')
      << static_cast<unsigned long>(hr);
  return out.str();
}

std::string Utf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0,
                                         nullptr, nullptr);
  if (length <= 0) {
    return "<invalid UTF-16>";
  }
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length, nullptr,
                      nullptr);
  return result;
}

template <typename Getter>
std::wstring WicString(Getter getter) {
  UINT required = 0;
  HRESULT hr = getter(0, nullptr, &required);
  if (FAILED(hr) && hr != WINCODEC_ERR_INSUFFICIENTBUFFER) {
    return {};
  }
  if (required <= 1) {
    return {};
  }

  std::vector<wchar_t> buffer(required, L'\0');
  hr = getter(required, buffer.data(), &required);
  if (FAILED(hr)) {
    return {};
  }
  return std::wstring(buffer.data());
}

const char* ContainerName(const GUID& guid) {
  if (IsEqualGUID(guid, GUID_ContainerFormatBmp)) return "BMP";
  if (IsEqualGUID(guid, GUID_ContainerFormatPng)) return "PNG";
  if (IsEqualGUID(guid, GUID_ContainerFormatIco)) return "ICO";
  // WIC does not expose a named GUID_ContainerFormatCur constant in all SDKs.
  static const GUID kCur = {0x0444f35f, 0x587c, 0x4570,
                            {0x96, 0x46, 0x64, 0xdc, 0xd8, 0xf1, 0x75, 0x73}};
  if (IsEqualGUID(guid, kCur)) return "CUR";
  if (IsEqualGUID(guid, GUID_ContainerFormatJpeg)) return "JPEG";
  if (IsEqualGUID(guid, GUID_ContainerFormatTiff)) return "TIFF";
  if (IsEqualGUID(guid, GUID_ContainerFormatGif)) return "GIF";
  if (IsEqualGUID(guid, GUID_ContainerFormatWmp)) return "JPEG-XR";
  if (IsEqualGUID(guid, GUID_ContainerFormatDds)) return "DDS";
  // The built-in decoder advertises the DNG container with this legacy ADNG
  // GUID; retain the user-facing DNG name used by the former sidecar.
  if (IsEqualGUID(guid, GUID_ContainerFormatAdng)) return "DNG";
  if (IsEqualGUID(guid, GUID_ContainerFormatHeif)) return "HEIF";
  if (IsEqualGUID(guid, GUID_ContainerFormatWebp)) return "WebP";
  if (IsEqualGUID(guid, GUID_ContainerFormatRaw)) return "RAW";
  if (IsEqualGUID(guid, GUID_ContainerFormatJpegXL)) return "JPEG-XL";
  return nullptr;
}

std::string GuidText(const GUID& guid) {
  wchar_t buffer[64] = {};
  if (StringFromGUID2(guid, buffer, static_cast<int>(std::size(buffer))) == 0) {
    return "{unknown}";
  }
  return Utf8(buffer);
}

struct DecoderEntry {
  std::string name;
  std::string format;
  std::string version;
  std::string clsid;
  std::string extensions;
  std::string mime_types;
};

int ListDecoders() {
  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    std::cerr << "CoCreateInstance(IWICImagingFactory) failed: " << HResultText(hr)
              << '\n';
    return 1;
  }

  ComPtr<IEnumUnknown> enumerator;
  hr = factory->CreateComponentEnumerator(WICDecoder, WICComponentEnumerateDefault,
                                           &enumerator);
  if (FAILED(hr)) {
    std::cerr << "CreateComponentEnumerator(WICDecoder) failed: " << HResultText(hr)
              << '\n';
    return 1;
  }

  std::vector<DecoderEntry> decoders;
  while (true) {
    ComPtr<IUnknown> unknown;
    ULONG fetched = 0;
    hr = enumerator->Next(1, unknown.GetAddressOf(), &fetched);
    if (hr == S_FALSE || fetched == 0) {
      break;
    }
    if (FAILED(hr)) {
      std::cerr << "IEnumUnknown::Next failed: " << HResultText(hr) << '\n';
      break;
    }

    ComPtr<IWICBitmapDecoderInfo> info;
    if (FAILED(unknown.As(&info))) {
      continue;
    }

    GUID clsid = {};
    if (FAILED(info->GetCLSID(&clsid))) {
      continue;
    }
    const std::wstring name = WicString([&](UINT count, WCHAR* buffer, UINT* actual) {
      return info->GetFriendlyName(count, buffer, actual);
    });
    const std::wstring version = WicString([&](UINT count, WCHAR* buffer, UINT* actual) {
      return info->GetVersion(count, buffer, actual);
    });
    const std::wstring extensions = WicString([&](UINT count, WCHAR* buffer, UINT* actual) {
      return info->GetFileExtensions(count, buffer, actual);
    });
    const std::wstring mime_types = WicString([&](UINT count, WCHAR* buffer, UINT* actual) {
      return info->GetMimeTypes(count, buffer, actual);
    });

    GUID container = {};
    std::string format;
    if (SUCCEEDED(info->GetContainerFormat(&container))) {
      if (const char* known = ContainerName(container)) {
        format = known;
      } else {
        format = GuidText(container);
      }
    }

    decoders.push_back({
        Utf8(name).empty() ? GuidText(clsid) : Utf8(name),
        format,
        Utf8(version),
        GuidText(clsid),
        Utf8(extensions),
        Utf8(mime_types),
    });
  }

  std::sort(decoders.begin(), decoders.end(), [](const DecoderEntry& left,
                                                 const DecoderEntry& right) {
    return _stricmp(left.name.c_str(), right.name.c_str()) < 0;
  });
  for (const DecoderEntry& decoder : decoders) {
    std::cout << decoder.name << '\t' << decoder.format << '\t' << decoder.version << '\t'
              << decoder.clsid << '\t' << decoder.extensions << '\t' << decoder.mime_types
              << '\n';
  }
  std::cerr << decoders.size() << " decoder(s) listed.\n";
  return 0;
}

int WriteStreamToStdout(IStream* stream) {
  HGLOBAL handle = nullptr;
  HRESULT hr = GetHGlobalFromStream(stream, &handle);
  if (FAILED(hr) || handle == nullptr) {
    std::cerr << "GetHGlobalFromStream failed: " << HResultText(hr) << '\n';
    return 1;
  }

  const SIZE_T size = GlobalSize(handle);
  void* bytes = GlobalLock(handle);
  if (bytes == nullptr && size != 0) {
    std::cerr << "GlobalLock failed.\n";
    return 1;
  }
  const size_t written = std::fwrite(bytes, 1, static_cast<size_t>(size), stdout);
  GlobalUnlock(handle);
  if (written != static_cast<size_t>(size)) {
    std::cerr << "failed to write PNG bytes to stdout.\n";
    return 1;
  }
  return 0;
}

int DecodeToPng(const wchar_t* path) {
  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    std::cerr << "CoCreateInstance(IWICImagingFactory) failed: " << HResultText(hr)
              << '\n';
    return 1;
  }

  ComPtr<IWICBitmapDecoder> decoder;
  hr = factory->CreateDecoderFromFilename(path, nullptr, GENERIC_READ,
                                           WICDecodeMetadataCacheOnLoad, &decoder);
  if (FAILED(hr)) {
    std::cerr << "CreateDecoderFromFilename failed: " << HResultText(hr) << '\n';
    return 1;
  }

  UINT frame_count = 0;
  hr = decoder->GetFrameCount(&frame_count);
  if (FAILED(hr) || frame_count == 0) {
    std::cerr << "WIC returned no frames: " << HResultText(FAILED(hr) ? hr : E_FAIL) << '\n';
    return 1;
  }

  ComPtr<IWICBitmapFrameDecode> frame;
  hr = decoder->GetFrame(0, &frame);
  if (FAILED(hr)) {
    std::cerr << "GetFrame(0) failed: " << HResultText(hr) << '\n';
    return 1;
  }

  ComPtr<IWICFormatConverter> converter;
  hr = factory->CreateFormatConverter(&converter);
  if (FAILED(hr)) {
    std::cerr << "CreateFormatConverter failed: " << HResultText(hr) << '\n';
    return 1;
  }
  hr = converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGRA,
                             WICBitmapDitherTypeNone, nullptr, 0.0,
                             WICBitmapPaletteTypeCustom);
  if (FAILED(hr)) {
    std::cerr << "Format converter initialization failed: " << HResultText(hr) << '\n';
    return 1;
  }

  ComPtr<IStream> stream;
  hr = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  if (FAILED(hr)) {
    std::cerr << "CreateStreamOnHGlobal failed: " << HResultText(hr) << '\n';
    return 1;
  }

  ComPtr<IWICBitmapEncoder> encoder;
  hr = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
  if (FAILED(hr)) {
    std::cerr << "CreateEncoder(PNG) failed: " << HResultText(hr) << '\n';
    return 1;
  }
  hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
  if (FAILED(hr)) {
    std::cerr << "PNG encoder initialization failed: " << HResultText(hr) << '\n';
    return 1;
  }

  ComPtr<IWICBitmapFrameEncode> output_frame;
  ComPtr<IPropertyBag2> options;
  hr = encoder->CreateNewFrame(&output_frame, &options);
  if (FAILED(hr)) {
    std::cerr << "CreateNewFrame failed: " << HResultText(hr) << '\n';
    return 1;
  }
  hr = output_frame->Initialize(options.Get());
  if (FAILED(hr)) {
    std::cerr << "PNG frame initialization failed: " << HResultText(hr) << '\n';
    return 1;
  }

  UINT width = 0;
  UINT height = 0;
  hr = converter->GetSize(&width, &height);
  if (FAILED(hr)) {
    std::cerr << "GetSize failed: " << HResultText(hr) << '\n';
    return 1;
  }
  hr = output_frame->SetSize(width, height);
  if (FAILED(hr)) {
    std::cerr << "PNG frame SetSize failed: " << HResultText(hr) << '\n';
    return 1;
  }
  WICPixelFormatGUID pixel_format = GUID_WICPixelFormat32bppBGRA;
  hr = output_frame->SetPixelFormat(&pixel_format);
  if (FAILED(hr)) {
    std::cerr << "PNG frame SetPixelFormat failed: " << HResultText(hr) << '\n';
    return 1;
  }
  hr = output_frame->WriteSource(converter.Get(), nullptr);
  if (FAILED(hr)) {
    std::cerr << "PNG frame WriteSource failed: " << HResultText(hr) << '\n';
    return 1;
  }
  hr = output_frame->Commit();
  if (FAILED(hr)) {
    std::cerr << "PNG frame Commit failed: " << HResultText(hr) << '\n';
    return 1;
  }
  hr = encoder->Commit();
  if (FAILED(hr)) {
    std::cerr << "PNG encoder Commit failed: " << HResultText(hr) << '\n';
    return 1;
  }
  return WriteStreamToStdout(stream.Get());
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  _setmode(_fileno(stdout), _O_BINARY);

  if (argc == 2 && (std::wstring(argv[1]) == L"--list" || std::wstring(argv[1]) == L"-l")) {
    const HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hr)) {
      std::cerr << "CoInitializeEx failed: " << HResultText(hr) << '\n';
      return 1;
    }
    const int result = ListDecoders();
    CoUninitialize();
    return result;
  }

  if (argc != 2) {
    std::wcerr << L"Usage: wic-decoder.exe <image>\n"
               << L"       wic-decoder.exe --list    enumerate WIC decoders\n";
    return 2;
  }

  const HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(hr)) {
    std::cerr << "CoInitializeEx failed: " << HResultText(hr) << '\n';
    return 1;
  }
  const int result = DecodeToPng(argv[1]);
  CoUninitialize();
  return result;
}
