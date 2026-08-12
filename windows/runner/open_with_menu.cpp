#include "open_with_menu.h"

#include <shlobj.h>
#include <shobjidl.h>
#include <gdiplus.h>

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

namespace {

// This CLSID is declared by the Windows Shell API, but is absent from some
// recent SDK header variants. It is the documented Shell Open With handler.
const CLSID kOpenWithMenuClsid = {
    0x09799afb, 0xad67, 0x11d1, {0xab, 0xcd, 0x00, 0xc0, 0x4f, 0xc3, 0x09, 0x36}};

struct OpenWithMenuState {
    IContextMenu* contextMenu = nullptr;
    HMENU menu = nullptr;

    void Reset() {
        if (menu) {
            DestroyMenu(menu);
            menu = nullptr;
        }
        if (contextMenu) {
            contextMenu->Release();
            contextMenu = nullptr;
        }
    }
};

OpenWithMenuState g_openWithMenu;

struct OpenWithEntry {
    int32_t kind;
    int32_t commandId;
    int32_t enabled;
    std::wstring label;
    std::vector<unsigned char> iconPng;
};

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
            if (Gdiplus::GetImageEncodersSize(&count, &size) == Gdiplus::Ok && size > 0) {
                std::vector<unsigned char> buffer(size);
                auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
                if (Gdiplus::GetImageEncoders(count, size, codecs) == Gdiplus::Ok) {
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
    if (available && pngClsid) *pngClsid = clsid;
    return available;
}

std::vector<unsigned char> PixelsToPng(
    int width,
    int height,
    int stride,
    unsigned char* pixels) {
    std::vector<unsigned char> result;
    if (width <= 0 || height <= 0 || stride < width * 4 || !pixels)
        return result;

    CLSID pngClsid = {};
    if (!GetPngEncoder(&pngClsid))
        return result;

    Gdiplus::Bitmap bitmap(
        width,
        height,
        stride,
        PixelFormat32bppARGB,
        pixels);
    if (bitmap.GetLastStatus() != Gdiplus::Ok)
        return result;

    IStream* stream = nullptr;
    if (CreateStreamOnHGlobal(nullptr, TRUE, &stream) != S_OK)
        return result;
    if (bitmap.Save(stream, &pngClsid, nullptr) == Gdiplus::Ok) {
        STATSTG stat = {};
        if (stream->Stat(&stat, STATFLAG_NONAME) == S_OK &&
            stat.cbSize.QuadPart > 0 && stat.cbSize.QuadPart < 1024 * 1024) {
            result.resize(static_cast<size_t>(stat.cbSize.QuadPart));
            LARGE_INTEGER start = {};
            stream->Seek(start, STREAM_SEEK_SET, nullptr);
            ULONG read = 0;
            if (stream->Read(result.data(), static_cast<ULONG>(result.size()), &read) != S_OK)
                result.clear();
            else
                result.resize(read);
        }
    }
    stream->Release();
    return result;
}

// Shell menu bitmaps use premultiplied BGRA. Constructing a GDI+ Bitmap
// directly from HBITMAP drops that alpha on some app icons, leaving their
// transparent area filled with the bitmap's RGB background.
std::vector<unsigned char> BitmapToPng(HBITMAP bitmapHandle) {
    std::vector<unsigned char> result;
    if (!bitmapHandle || bitmapHandle == HBMMENU_CALLBACK)
        return result;

    // Values below HBMMENU_MBAR_CLOSE are predefined menu glyph constants,
    // not real GDI bitmap handles.
    if (reinterpret_cast<UINT_PTR>(bitmapHandle) <=
        reinterpret_cast<UINT_PTR>(HBMMENU_MBAR_CLOSE)) {
        return result;
    }

    BITMAP bitmap = {};
    if (!GetObjectW(bitmapHandle, sizeof(bitmap), &bitmap) ||
        bitmap.bmWidth <= 0 || bitmap.bmHeight == 0) {
        return result;
    }

    const int width = bitmap.bmWidth;
    const int height = std::abs(bitmap.bmHeight);
    const int stride = width * 4;
    std::vector<unsigned char> pixels(static_cast<size_t>(stride) * height);
    BITMAPINFO info = {};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;

    HDC screenDc = GetDC(nullptr);
    const int rows = GetDIBits(
        screenDc,
        bitmapHandle,
        0,
        height,
        pixels.data(),
        &info,
        DIB_RGB_COLORS);
    ReleaseDC(nullptr, screenDc);
    if (rows != height)
        return result;

    bool hasNonZeroAlpha = false;
    bool hasPartialAlpha = false;
    bool canBePremultiplied = true;
    for (size_t offset = 0; offset < pixels.size(); offset += 4) {
        const unsigned char alpha = pixels[offset + 3];
        hasNonZeroAlpha |= alpha != 0;
        hasPartialAlpha |= alpha != 0 && alpha != 255;
        if (alpha != 0 && alpha != 255 &&
            (pixels[offset] > alpha ||
             pixels[offset + 1] > alpha ||
             pixels[offset + 2] > alpha)) {
            canBePremultiplied = false;
        }
    }

    // Files uses Bitmap.MakeTransparent() here. Shell sometimes returns an
    // opaque menu bitmap whose top-left pixel is a color key (Todoist, for
    // example, uses the current blue menu background). Preserve real alpha,
    // but apply the same corner-color rule when the bitmap has no partial
    // alpha channel.
    const unsigned char keyBlue = pixels[0];
    const unsigned char keyGreen = pixels[1];
    const unsigned char keyRed = pixels[2];
    for (size_t offset = 0; offset < pixels.size(); offset += 4) {
        unsigned char& blue = pixels[offset];
        unsigned char& green = pixels[offset + 1];
        unsigned char& red = pixels[offset + 2];
        unsigned char& alpha = pixels[offset + 3];
        if (!hasPartialAlpha) {
            if (blue == keyBlue && green == keyGreen && red == keyRed) {
                blue = green = red = alpha = 0;
            } else if (!hasNonZeroAlpha) {
                alpha = 255;
            }
        } else if (alpha == 0) {
            blue = green = red = 0;
        } else if (canBePremultiplied && alpha < 255) {
            blue = static_cast<unsigned char>(
                std::min(255, (static_cast<int>(blue) * 255 + alpha / 2) / alpha));
            green = static_cast<unsigned char>(
                std::min(255, (static_cast<int>(green) * 255 + alpha / 2) / alpha));
            red = static_cast<unsigned char>(
                std::min(255, (static_cast<int>(red) * 255 + alpha / 2) / alpha));
        }
    }
    return PixelsToPng(width, height, stride, pixels.data());
}

struct RenderSurface {
    HDC dc = nullptr;
    HBITMAP bitmap = nullptr;
    HGDIOBJ previous = nullptr;
    unsigned char* pixels = nullptr;
    int width = 0;
    int height = 0;

    bool Create(int requestedWidth, int requestedHeight, unsigned char background) {
        width = requestedWidth;
        height = requestedHeight;
        BITMAPINFO info = {};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = width;
        info.bmiHeader.biHeight = -height;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;

        HDC screenDc = GetDC(nullptr);
        bitmap = CreateDIBSection(
            screenDc,
            &info,
            DIB_RGB_COLORS,
            reinterpret_cast<void**>(&pixels),
            nullptr,
            0);
        ReleaseDC(nullptr, screenDc);
        if (!bitmap || !pixels)
            return false;

        dc = CreateCompatibleDC(nullptr);
        if (!dc)
            return false;
        previous = SelectObject(dc, bitmap);
        for (int index = 0; index < width * height; index++) {
            pixels[index * 4] = background;
            pixels[index * 4 + 1] = background;
            pixels[index * 4 + 2] = background;
            pixels[index * 4 + 3] = 255;
        }
        return true;
    }

    ~RenderSurface() {
        if (dc && previous)
            SelectObject(dc, previous);
        if (dc)
            DeleteDC(dc);
        if (bitmap)
            DeleteObject(bitmap);
    }
};

bool DrawCallbackMenuItem(
    IContextMenu2* contextMenu,
    HMENU menu,
    const MENUITEMINFOW& info,
    RenderSurface* surface) {
    if (!contextMenu || !menu || !surface || !surface->dc)
        return false;

    DRAWITEMSTRUCT draw = {};
    draw.CtlType = ODT_MENU;
    draw.itemID = info.wID;
    draw.itemAction = ODA_DRAWENTIRE;
    if (info.fState & MFS_CHECKED) draw.itemState |= ODS_CHECKED;
    if (info.fState & MFS_DEFAULT) draw.itemState |= ODS_DEFAULT;
    if (info.fState & (MFS_DISABLED | MFS_GRAYED))
        draw.itemState |= ODS_DISABLED | ODS_GRAYED;
    draw.hwndItem = reinterpret_cast<HWND>(menu);
    draw.hDC = surface->dc;
    draw.rcItem = {0, 0, surface->width, surface->height};
    draw.itemData = info.dwItemData;
    return SUCCEEDED(contextMenu->HandleMenuMsg(
        WM_DRAWITEM,
        0,
        reinterpret_cast<LPARAM>(&draw)));
}

std::vector<unsigned char> CallbackBitmapToPng(
    IContextMenu2* contextMenu,
    HMENU menu,
    const MENUITEMINFOW& info) {
    std::vector<unsigned char> result;
    if (!contextMenu)
        return result;

    MEASUREITEMSTRUCT measure = {};
    measure.CtlType = ODT_MENU;
    measure.itemID = info.wID;
    measure.itemData = info.dwItemData;
    contextMenu->HandleMenuMsg(
        WM_MEASUREITEM,
        0,
        reinterpret_cast<LPARAM>(&measure));

    const int height = std::max(
        static_cast<int>(measure.itemHeight),
        std::max(16, GetSystemMetrics(SM_CYMENU)));
    const int width = std::max(
        static_cast<int>(measure.itemWidth),
        height * 8);
    RenderSurface black;
    RenderSurface white;
    if (!black.Create(width, height, 0) ||
        !white.Create(width, height, 255) ||
        !DrawCallbackMenuItem(contextMenu, menu, info, &black) ||
        !DrawCallbackMenuItem(contextMenu, menu, info, &white)) {
        return result;
    }

    // The handler draws the complete native row. Only inspect the check/icon
    // gutter, so the command label never becomes part of the exported image.
    const int gutterWidth = std::min(
        width,
        std::max(
            height + GetSystemMetrics(SM_CXEDGE) * 2,
            GetSystemMetrics(SM_CXMENUCHECK) + GetSystemMetrics(SM_CXEDGE) * 4));
    std::vector<unsigned char> reconstructed(
        static_cast<size_t>(gutterWidth) * height * 4);
    int left = gutterWidth;
    int top = height;
    int right = -1;
    int bottom = -1;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < gutterWidth; x++) {
            const size_t source = (static_cast<size_t>(y) * width + x) * 4;
            const size_t target = (static_cast<size_t>(y) * gutterWidth + x) * 4;
            int transparency = 0;
            for (int channel = 0; channel < 3; channel++) {
                transparency += std::clamp(
                    static_cast<int>(white.pixels[source + channel]) -
                        static_cast<int>(black.pixels[source + channel]),
                    0,
                    255);
            }
            const int alpha = 255 - transparency / 3;
            reconstructed[target + 3] = static_cast<unsigned char>(alpha);
            if (alpha <= 2) {
                reconstructed[target] = 0;
                reconstructed[target + 1] = 0;
                reconstructed[target + 2] = 0;
                continue;
            }
            for (int channel = 0; channel < 3; channel++) {
                reconstructed[target + channel] = static_cast<unsigned char>(
                    std::min(
                        255,
                        (static_cast<int>(black.pixels[source + channel]) * 255 +
                         alpha / 2) /
                            alpha));
            }
            left = std::min(left, x);
            top = std::min(top, y);
            right = std::max(right, x);
            bottom = std::max(bottom, y);
        }
    }
    if (right < left || bottom < top)
        return result;

    left = std::max(0, left - 1);
    top = std::max(0, top - 1);
    right = std::min(gutterWidth - 1, right + 1);
    bottom = std::min(height - 1, bottom + 1);
    const int croppedWidth = right - left + 1;
    const int croppedHeight = bottom - top + 1;
    const int croppedStride = croppedWidth * 4;
    std::vector<unsigned char> cropped(
        static_cast<size_t>(croppedStride) * croppedHeight);
    for (int y = 0; y < croppedHeight; y++) {
        memcpy(
            cropped.data() + static_cast<size_t>(y) * croppedStride,
            reconstructed.data() +
                (static_cast<size_t>(y + top) * gutterWidth + left) * 4,
            croppedStride);
    }
    return PixelsToPng(
        croppedWidth,
        croppedHeight,
        croppedStride,
        cropped.data());
}

std::wstring ReadMenuLabel(HMENU menu, UINT index) {
    constexpr UINT kLabelBufferLength = 256;
    MENUITEMINFOW info = {};
    info.cbSize = sizeof(info);
    info.fMask = MIIM_STRING;
    std::vector<wchar_t> buffer(kLabelBufferLength, L'\0');
    info.dwTypeData = buffer.data();
    info.cch = kLabelBufferLength;
    if (!GetMenuItemInfoW(menu, index, TRUE, &info))
        return L"";

    std::wstring label(buffer.data(), info.cch);
    std::wstring normalized;
    normalized.reserve(label.size());
    for (size_t i = 0; i < label.size(); i++) {
        if (label[i] != L'&') {
            normalized.push_back(label[i]);
        } else if (i + 1 < label.size() && label[i + 1] == L'&') {
            normalized.push_back(L'&');
            i++;
        }
    }
    return normalized;
}

HRESULT CreateOpenWithMenu(const wchar_t* filePath, OpenWithMenuState* state) {
    if (!filePath || !*filePath || !state)
        return E_INVALIDARG;

    IContextMenu* contextMenu = nullptr;
    IShellExtInit* shellExtInit = nullptr;
    IContextMenu2* contextMenu2 = nullptr;
    IShellItem* shellItem = nullptr;
    IDataObject* dataObject = nullptr;
    HMENU menu = nullptr;
    HMENU submenu = nullptr;

    HRESULT hr = CoCreateInstance(
        kOpenWithMenuClsid,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_IContextMenu,
        reinterpret_cast<void**>(&contextMenu));
    if (FAILED(hr)) goto cleanup;

    hr = contextMenu->QueryInterface(IID_IShellExtInit, reinterpret_cast<void**>(&shellExtInit));
    if (FAILED(hr)) goto cleanup;
    hr = contextMenu->QueryInterface(IID_IContextMenu2, reinterpret_cast<void**>(&contextMenu2));
    if (FAILED(hr)) goto cleanup;

    hr = SHCreateItemFromParsingName(
        filePath,
        nullptr,
        IID_IShellItem,
        reinterpret_cast<void**>(&shellItem));
    if (FAILED(hr)) goto cleanup;
    hr = shellItem->BindToHandler(
        nullptr,
        BHID_DataObject,
        IID_IDataObject,
        reinterpret_cast<void**>(&dataObject));
    if (FAILED(hr)) goto cleanup;
    hr = shellExtInit->Initialize(nullptr, dataObject, nullptr);
    if (FAILED(hr)) goto cleanup;

    menu = CreatePopupMenu();
    if (!menu) {
        hr = HRESULT_FROM_WIN32(GetLastError());
        goto cleanup;
    }
    hr = contextMenu->QueryContextMenu(menu, 0, 1, 0x7fff, CMF_NORMAL);
    if (FAILED(hr)) goto cleanup;

    submenu = GetSubMenu(menu, 0);
    if (!submenu) {
        hr = E_FAIL;
        goto cleanup;
    }
    hr = contextMenu2->HandleMenuMsg(
        WM_INITMENUPOPUP,
        reinterpret_cast<WPARAM>(submenu),
        0);
    if (FAILED(hr)) goto cleanup;

    state->contextMenu = contextMenu;
    state->menu = menu;
    contextMenu = nullptr;
    menu = nullptr;

cleanup:
    if (menu) DestroyMenu(menu);
    if (dataObject) dataObject->Release();
    if (shellItem) shellItem->Release();
    if (contextMenu2) contextMenu2->Release();
    if (shellExtInit) shellExtInit->Release();
    if (contextMenu) contextMenu->Release();
    return hr;
}

std::vector<OpenWithEntry> EnumerateEntries(
    HMENU submenu,
    IContextMenu* contextMenu) {
    std::vector<OpenWithEntry> entries;
    const int count = GetMenuItemCount(submenu);
    bool lastWasSeparator = true;
    IContextMenu2* contextMenu2 = nullptr;
    if (contextMenu) {
        contextMenu->QueryInterface(
            IID_IContextMenu2,
            reinterpret_cast<void**>(&contextMenu2));
    }

    for (int index = 0; index < count; index++) {
        MENUITEMINFOW info = {};
        info.cbSize = sizeof(info);
        info.fMask =
            MIIM_FTYPE | MIIM_ID | MIIM_STATE | MIIM_BITMAP | MIIM_DATA;
        if (!GetMenuItemInfoW(submenu, index, TRUE, &info))
            continue;

        if (info.fType & MFT_SEPARATOR) {
            if (!lastWasSeparator) {
                entries.push_back({1, 0, 0, L"", {}});
                lastWasSeparator = true;
            }
            continue;
        }

        const std::wstring label = ReadMenuLabel(submenu, index);
        if (label.empty() || info.wID == 0)
            continue;
        std::vector<unsigned char> iconPng;
        if (info.hbmpItem == HBMMENU_CALLBACK) {
            iconPng = CallbackBitmapToPng(contextMenu2, submenu, info);
        } else {
            iconPng = BitmapToPng(info.hbmpItem);
        }
        entries.push_back({
            0,
            static_cast<int32_t>(info.wID),
            (info.fState & (MFS_DISABLED | MFS_GRAYED)) == 0 ? 1 : 0,
            label,
            std::move(iconPng),
        });
        lastWasSeparator = false;
    }

    if (!entries.empty() && entries.back().kind == 1)
        entries.pop_back();
    if (contextMenu2)
        contextMenu2->Release();
    return entries;
}

} // namespace

extern "C" __declspec(dllexport)
unsigned char* GetOpenWithMenuEntriesW(const wchar_t* filePath, int* outSize) {
    if (!outSize) return nullptr;
    *outSize = 0;
    g_openWithMenu.Reset();

    const HRESULT hr = CreateOpenWithMenu(filePath, &g_openWithMenu);
    if (FAILED(hr) || !g_openWithMenu.menu)
        return nullptr;

    const HMENU submenu = GetSubMenu(g_openWithMenu.menu, 0);
    if (!submenu) {
        g_openWithMenu.Reset();
        return nullptr;
    }
    const auto entries = EnumerateEntries(submenu, g_openWithMenu.contextMenu);
    if (entries.empty()) {
        g_openWithMenu.Reset();
        return nullptr;
    }

    std::vector<unsigned char> buffer;
    AppendInt32(buffer, static_cast<int32_t>(entries.size()));
    for (const auto& entry : entries) {
        AppendInt32(buffer, entry.kind);
        AppendInt32(buffer, entry.commandId);
        AppendInt32(buffer, entry.enabled);
        AppendWString(buffer, entry.label);
        AppendBytes(buffer, entry.iconPng);
    }

    auto* result = static_cast<unsigned char*>(CoTaskMemAlloc(buffer.size()));
    if (!result) {
        g_openWithMenu.Reset();
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
HRESULT InvokeOpenWithMenuEntry(int commandId, HWND hwnd) {
    if (commandId <= 0 || !g_openWithMenu.contextMenu)
        return E_INVALIDARG;

    CMINVOKECOMMANDINFOEX command = {};
    command.cbSize = sizeof(command);
    command.fMask = CMIC_MASK_UNICODE;
    command.hwnd = hwnd;
    command.lpVerb = MAKEINTRESOURCEA(commandId - 1);
    command.lpVerbW = MAKEINTRESOURCEW(commandId - 1);
    command.nShow = SW_SHOWNORMAL;

    HRESULT hr = E_FAIL;
    __try {
        hr = g_openWithMenu.contextMenu->InvokeCommand(
            reinterpret_cast<LPCMINVOKECOMMANDINFO>(&command));
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        hr = E_FAIL;
    }
    g_openWithMenu.Reset();
    return hr;
}
