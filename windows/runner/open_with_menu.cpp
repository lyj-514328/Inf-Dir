#include "open_with_menu.h"

#include <shlobj.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <commoncontrols.h>
#include <gdiplus.h>

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

namespace {

struct AssocHandlerEntry {
    int32_t id;
    std::wstring label;
    std::vector<unsigned char> iconPng;
    IAssocHandler* handler = nullptr;
};

struct AssocHandlerState {
    std::wstring filePath;
    std::vector<AssocHandlerEntry> entries;

    void Reset() {
        for (auto& entry : entries) {
            if (entry.handler)
                entry.handler->Release();
        }
        entries.clear();
        filePath.clear();
    }
};

AssocHandlerState g_assocHandlers;

void AppendInt32(std::vector<unsigned char>& buffer, int32_t value) {
    buffer.insert(
        buffer.end(),
        reinterpret_cast<unsigned char*>(&value),
        reinterpret_cast<unsigned char*>(&value) + sizeof(value));
}

void AppendWString(std::vector<unsigned char>& buffer, const std::wstring& value) {
    AppendInt32(buffer, static_cast<int32_t>(value.size()));
    if (!value.empty()) {
        const auto* bytes = reinterpret_cast<const unsigned char*>(value.data());
        buffer.insert(buffer.end(), bytes, bytes + value.size() * sizeof(wchar_t));
    }
}

void AppendBytes(
    std::vector<unsigned char>& buffer,
    const std::vector<unsigned char>& value) {
    AppendInt32(buffer, static_cast<int32_t>(value.size()));
    if (!value.empty())
        buffer.insert(buffer.end(), value.begin(), value.end());
}

bool GetPngEncoder(CLSID* pngClsid) {
    static bool initialized = false;
    static bool available = false;
    static ULONG_PTR token = 0;
    static CLSID clsid = {};
    if (!initialized) {
        initialized = true;
        Gdiplus::GdiplusStartupInput input;
        if (Gdiplus::GdiplusStartup(&token, &input, nullptr) == Gdiplus::Ok) {
            UINT count = 0;
            UINT size = 0;
            if (Gdiplus::GetImageEncodersSize(&count, &size) == Gdiplus::Ok &&
                size > 0) {
                std::vector<unsigned char> buffer(size);
                auto* codecs =
                    reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
                if (Gdiplus::GetImageEncoders(count, size, codecs) ==
                    Gdiplus::Ok) {
                    for (UINT index = 0; index < count; index++) {
                        if (wcscmp(codecs[index].MimeType, L"image/png") == 0) {
                            clsid = codecs[index].Clsid;
                            available = true;
                            break;
                        }
                    }
                }
            }
        }
    }
    if (available && pngClsid)
        *pngClsid = clsid;
    return available;
}

std::vector<unsigned char> IconToPng(HICON icon, int iconSize) {
    std::vector<unsigned char> result;
    CLSID pngClsid = {};
    if (!icon || iconSize <= 0 || !GetPngEncoder(&pngClsid))
        return result;

    BITMAPINFO info = {};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = iconSize;
    info.bmiHeader.biHeight = -iconSize;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;

    unsigned char* pixels = nullptr;
    HDC screenDc = GetDC(nullptr);
    HBITMAP bitmap = CreateDIBSection(
        screenDc,
        &info,
        DIB_RGB_COLORS,
        reinterpret_cast<void**>(&pixels),
        nullptr,
        0);
    ReleaseDC(nullptr, screenDc);
    if (!bitmap || !pixels) {
        if (bitmap) DeleteObject(bitmap);
        return result;
    }
    memset(pixels, 0, static_cast<size_t>(iconSize) * iconSize * 4);

    HDC memoryDc = CreateCompatibleDC(nullptr);
    HGDIOBJ previous = SelectObject(memoryDc, bitmap);
    DrawIconEx(
        memoryDc,
        0,
        0,
        icon,
        iconSize,
        iconSize,
        0,
        nullptr,
        DI_NORMAL);
    SelectObject(memoryDc, previous);
    DeleteDC(memoryDc);

    Gdiplus::Bitmap pngBitmap(
        iconSize,
        iconSize,
        iconSize * 4,
        PixelFormat32bppARGB,
        pixels);
    IStream* stream = nullptr;
    if (CreateStreamOnHGlobal(nullptr, TRUE, &stream) == S_OK) {
        if (pngBitmap.Save(stream, &pngClsid, nullptr) == Gdiplus::Ok) {
            STATSTG stat = {};
            if (stream->Stat(&stat, STATFLAG_NONAME) == S_OK &&
                stat.cbSize.QuadPart > 0 &&
                stat.cbSize.QuadPart < 1024 * 1024) {
                result.resize(static_cast<size_t>(stat.cbSize.QuadPart));
                LARGE_INTEGER start = {};
                stream->Seek(start, STREAM_SEEK_SET, nullptr);
                ULONG read = 0;
                if (stream->Read(
                        result.data(),
                        static_cast<ULONG>(result.size()),
                        &read) != S_OK) {
                    result.clear();
                } else {
                    result.resize(read);
                }
            }
        }
        stream->Release();
    }
    DeleteObject(bitmap);
    return result;
}

std::vector<unsigned char> ImageFileToPng(
    const wchar_t* imagePath,
    int iconSize) {
    std::vector<unsigned char> result;
    CLSID pngClsid = {};
    if (!imagePath || !*imagePath || iconSize <= 0 ||
        !GetPngEncoder(&pngClsid)) {
        return result;
    }

    Gdiplus::Bitmap source(imagePath);
    if (source.GetLastStatus() != Gdiplus::Ok ||
        source.GetWidth() == 0 || source.GetHeight() == 0) {
        return result;
    }

    Gdiplus::Bitmap destination(
        iconSize,
        iconSize,
        PixelFormat32bppARGB);
    if (destination.GetLastStatus() != Gdiplus::Ok)
        return result;

    Gdiplus::Graphics graphics(&destination);
    graphics.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
    graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);
    graphics.Clear(Gdiplus::Color(0, 0, 0, 0));

    const double scale = (std::min)(
        static_cast<double>(iconSize) / source.GetWidth(),
        static_cast<double>(iconSize) / source.GetHeight());
    const int width = (std::max)(
        1,
        static_cast<int>(source.GetWidth() * scale + 0.5));
    const int height = (std::max)(
        1,
        static_cast<int>(source.GetHeight() * scale + 0.5));
    const int x = (iconSize - width) / 2;
    const int y = (iconSize - height) / 2;
    if (graphics.DrawImage(&source, x, y, width, height) != Gdiplus::Ok)
        return result;

    IStream* stream = nullptr;
    if (CreateStreamOnHGlobal(nullptr, TRUE, &stream) == S_OK) {
        if (destination.Save(stream, &pngClsid, nullptr) == Gdiplus::Ok) {
            STATSTG stat = {};
            if (stream->Stat(&stat, STATFLAG_NONAME) == S_OK &&
                stat.cbSize.QuadPart > 0 &&
                stat.cbSize.QuadPart < 1024 * 1024) {
                result.resize(static_cast<size_t>(stat.cbSize.QuadPart));
                LARGE_INTEGER start = {};
                stream->Seek(start, STREAM_SEEK_SET, nullptr);
                ULONG read = 0;
                if (stream->Read(
                        result.data(),
                        static_cast<ULONG>(result.size()),
                        &read) != S_OK) {
                    result.clear();
                } else {
                    result.resize(read);
                }
            }
        }
        stream->Release();
    }
    return result;
}

int ImageListForSize(int iconSize) {
    if (iconSize <= GetSystemMetrics(SM_CXSMICON)) return SHIL_SYSSMALL;
    if (iconSize <= 32) return SHIL_LARGE;
    if (iconSize <= 48) return SHIL_EXTRALARGE;
    return SHIL_JUMBO;
}

std::vector<unsigned char> LoadIconPath(
    const wchar_t* iconPath,
    int iconIndex,
    int iconSize) {
    std::vector<unsigned char> result;
    if (!iconPath || !*iconPath || iconSize <= 0)
        return result;

    // Packaged apps commonly resolve to a PNG asset rather than an icon
    // resource in an executable or DLL.
    result = ImageFileToPng(iconPath, iconSize);
    if (!result.empty())
        return result;

    HICON icon = nullptr;
    const int cachedIndex =
        Shell_GetCachedImageIndexW(iconPath, iconIndex, 0);
    if (cachedIndex >= 0) {
        IImageList* imageList = nullptr;
        if (SUCCEEDED(SHGetImageList(
                ImageListForSize(iconSize),
                IID_IImageList,
                reinterpret_cast<void**>(&imageList))) &&
            imageList) {
            imageList->GetIcon(cachedIndex, ILD_TRANSPARENT, &icon);
            imageList->Release();
        }
    }

    if (!icon) {
        SHDefExtractIconW(
            iconPath,
            iconIndex,
            0,
            iconSize > 16 ? &icon : nullptr,
            iconSize <= 16 ? &icon : nullptr,
            MAKELONG(iconSize, iconSize));
    }
    if (icon) {
        result = IconToPng(icon, iconSize);
        DestroyIcon(icon);
    }
    return result;
}

std::vector<unsigned char> LoadIconReference(
    const std::wstring& iconReference,
    int iconSize) {
    if (iconReference.empty() || iconSize <= 0)
        return {};

    if (iconReference[0] == L'@') {
        std::vector<wchar_t> resolvedPath(32768, L'\0');
        if (SUCCEEDED(SHLoadIndirectString(
                iconReference.c_str(),
                resolvedPath.data(),
                static_cast<UINT>(resolvedPath.size()),
                nullptr)) &&
            resolvedPath[0]) {
            auto result = LoadIconPath(resolvedPath.data(), 0, iconSize);
            if (!result.empty())
                return result;
        }
    }

    std::vector<wchar_t> reference(
        iconReference.begin(), iconReference.end());
    reference.push_back(L'\0');
    const int iconIndex = PathParseIconLocationW(reference.data());
    PathUnquoteSpacesW(reference.data());

    std::vector<wchar_t> expandedPath(32768, L'\0');
    const DWORD expandedLength = ExpandEnvironmentStringsW(
        reference.data(),
        expandedPath.data(),
        static_cast<DWORD>(expandedPath.size()));
    const wchar_t* iconPath =
        expandedLength > 0 && expandedLength <= expandedPath.size()
        ? expandedPath.data()
        : reference.data();
    return LoadIconPath(iconPath, iconIndex, iconSize);
}

std::vector<unsigned char> LoadHandlerIcon(
    IAssocHandler* handler,
    int iconSize) {
    std::vector<unsigned char> result;
    if (!handler || iconSize <= 0)
        return result;

    LPWSTR iconPath = nullptr;
    int iconIndex = 0;
    HRESULT hr = handler->GetIconLocation(&iconPath, &iconIndex);
    if (FAILED(hr) || !iconPath || !*iconPath) {
        if (iconPath) CoTaskMemFree(iconPath);
        iconPath = nullptr;
        iconIndex = 0;
        if (FAILED(handler->GetName(&iconPath)) || !iconPath || !*iconPath) {
            if (iconPath) CoTaskMemFree(iconPath);
            return result;
        }
    }

    if (iconPath[0] == L'@') {
        std::vector<wchar_t> resolvedPath(32768, L'\0');
        if (SUCCEEDED(SHLoadIndirectString(
                iconPath,
                resolvedPath.data(),
                static_cast<UINT>(resolvedPath.size()),
                nullptr)) &&
            resolvedPath[0]) {
            result = LoadIconPath(resolvedPath.data(), 0, iconSize);
        }
        CoTaskMemFree(iconPath);
        if (!result.empty())
            return result;
        iconPath = nullptr;
        iconIndex = 0;
        if (FAILED(handler->GetName(&iconPath)) || !iconPath || !*iconPath) {
            if (iconPath) CoTaskMemFree(iconPath);
            return result;
        }
    }

    result = LoadIconPath(iconPath, iconIndex, iconSize);
    CoTaskMemFree(iconPath);
    return result;
}

std::wstring QueryAssociationString(
    const std::wstring& extension,
    ASSOCSTR value) {
    DWORD length = 0;
    const ASSOCF flags = ASSOCF_NOTRUNCATE;
    AssocQueryStringW(
        flags, value, extension.c_str(), nullptr, nullptr, &length);
    if (length <= 1)
        return L"";

    std::vector<wchar_t> buffer(length, L'\0');
    if (FAILED(AssocQueryStringW(
            flags,
            value,
            extension.c_str(),
            nullptr,
            buffer.data(),
            &length)) ||
        !buffer[0]) {
        return L"";
    }
    return buffer.data();
}

std::vector<unsigned char> LoadDefaultOpenAppIcon(
    const std::wstring& extension,
    int iconSize) {
    auto iconReference = QueryAssociationString(
        extension, ASSOCSTR_APPICONREFERENCE);
    auto result = LoadIconReference(iconReference, iconSize);
    if (!result.empty())
        return result;

    // Older Win32 registrations may expose only the executable.
    const auto executable = QueryAssociationString(
        extension, ASSOCSTR_EXECUTABLE);
    return LoadIconReference(executable, iconSize);
}

std::wstring ExtensionFromPath(const wchar_t* filePath) {
    if (!filePath)
        return L"";
    const wchar_t* lastSeparator = wcsrchr(filePath, L'\\');
    const wchar_t* lastForwardSeparator = wcsrchr(filePath, L'/');
    if (!lastSeparator ||
        (lastForwardSeparator && lastForwardSeparator > lastSeparator)) {
        lastSeparator = lastForwardSeparator;
    }
    const wchar_t* extension = wcsrchr(filePath, L'.');
    if (!extension || (lastSeparator && extension < lastSeparator) ||
        !extension[1]) {
        return L"";
    }
    return extension;
}

bool ContainsHandler(
    const std::vector<AssocHandlerEntry>& entries,
    const std::wstring& label,
    IAssocHandler* candidate) {
    LPWSTR candidateName = nullptr;
    candidate->GetName(&candidateName);
    for (const auto& entry : entries) {
        if (_wcsicmp(entry.label.c_str(), label.c_str()) != 0)
            continue;
        LPWSTR existingName = nullptr;
        entry.handler->GetName(&existingName);
        const bool same = existingName && candidateName &&
            _wcsicmp(existingName, candidateName) == 0;
        if (existingName) CoTaskMemFree(existingName);
        if (same) {
            if (candidateName) CoTaskMemFree(candidateName);
            return true;
        }
    }
    if (candidateName) CoTaskMemFree(candidateName);
    return false;
}

HRESULT CreateFileDataObject(const wchar_t* filePath, IDataObject** dataObject) {
    if (!filePath || !*filePath || !dataObject)
        return E_INVALIDARG;
    *dataObject = nullptr;

    IShellItem* shellItem = nullptr;
    HRESULT hr = SHCreateItemFromParsingName(
        filePath,
        nullptr,
        IID_IShellItem,
        reinterpret_cast<void**>(&shellItem));
    if (SUCCEEDED(hr)) {
        hr = shellItem->BindToHandler(
            nullptr,
            BHID_DataObject,
            IID_IDataObject,
            reinterpret_cast<void**>(dataObject));
        shellItem->Release();
    }
    return hr;
}

} // namespace

extern "C" __declspec(dllexport)
unsigned char* GetOpenWithMenuEntriesW(
    const wchar_t* filePath,
    int iconSize,
    int* outSize) {
    if (!filePath || !*filePath || !outSize)
        return nullptr;
    *outSize = 0;
    g_assocHandlers.Reset();

    const std::wstring extension = ExtensionFromPath(filePath);
    if (extension.empty())
        return nullptr;

    const int resolvedIconSize = std::clamp(iconSize, 16, 256);
    const auto defaultAppIcon = LoadDefaultOpenAppIcon(
        extension, resolvedIconSize);

    IEnumAssocHandlers* enumerator = nullptr;
    HRESULT hr = SHAssocEnumHandlers(
        extension.c_str(),
        ASSOC_FILTER_RECOMMENDED,
        &enumerator);
    if (SUCCEEDED(hr) && enumerator) {
        IAssocHandler* handler = nullptr;
        ULONG fetched = 0;
        while (enumerator->Next(1, &handler, &fetched) == S_OK &&
               fetched == 1 && handler) {
            LPWSTR uiName = nullptr;
            hr = handler->GetUIName(&uiName);
            if (SUCCEEDED(hr) && uiName && *uiName) {
                const std::wstring label(uiName);
                if (!ContainsHandler(g_assocHandlers.entries, label, handler)) {
                    g_assocHandlers.entries.push_back({
                        static_cast<int32_t>(g_assocHandlers.entries.size() + 1),
                        label,
                        LoadHandlerIcon(handler, resolvedIconSize),
                        handler,
                    });
                    handler = nullptr;
                }
            }
            if (uiName) CoTaskMemFree(uiName);
            if (handler) {
                handler->Release();
                handler = nullptr;
            }
        }
        if (handler)
            handler->Release();
        enumerator->Release();
    }

    if (defaultAppIcon.empty() && g_assocHandlers.entries.empty())
        return nullptr;
    g_assocHandlers.filePath = filePath;

    std::vector<unsigned char> buffer;
    AppendInt32(
        buffer,
        static_cast<int32_t>(g_assocHandlers.entries.size()));
    AppendBytes(buffer, defaultAppIcon);
    for (const auto& entry : g_assocHandlers.entries) {
        AppendInt32(buffer, 0);
        AppendInt32(buffer, entry.id);
        AppendInt32(buffer, 1);
        AppendWString(buffer, entry.label);
        AppendBytes(buffer, entry.iconPng);
    }

    auto* result = static_cast<unsigned char*>(CoTaskMemAlloc(buffer.size()));
    if (!result) {
        g_assocHandlers.Reset();
        return nullptr;
    }
    memcpy(result, buffer.data(), buffer.size());
    *outSize = static_cast<int>(buffer.size());
    return result;
}

extern "C" __declspec(dllexport)
void FreeOpenWithMenuEntries(unsigned char* ptr) {
    if (ptr) CoTaskMemFree(ptr);
}

extern "C" __declspec(dllexport)
HRESULT InvokeOpenWithMenuEntry(int commandId) {
    if (commandId <= 0 ||
        commandId > static_cast<int>(g_assocHandlers.entries.size()) ||
        g_assocHandlers.filePath.empty()) {
        return E_INVALIDARG;
    }

    IDataObject* dataObject = nullptr;
    HRESULT hr = CreateFileDataObject(
        g_assocHandlers.filePath.c_str(),
        &dataObject);
    if (FAILED(hr) || !dataObject)
        return FAILED(hr) ? hr : E_FAIL;

    IAssocHandler* handler =
        g_assocHandlers.entries[static_cast<size_t>(commandId - 1)].handler;
    __try {
        hr = handler->Invoke(dataObject);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        hr = E_FAIL;
    }
    dataObject->Release();
    g_assocHandlers.Reset();
    return hr;
}
