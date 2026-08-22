#include "file_icon.h"
#include <shlobj.h>
#include <shobjidl.h>
#include <commoncontrols.h>
#include <objbase.h>
#include <gdiplus.h>
#include <propsys.h>
#include <propvarutil.h>
#include <string>

#include "shell_debug.h"
#include "shell_pidl.h"

// -- GDI+ lazy init ---------------------------------------------------

static bool g_gdiplusReady = false;
static ULONG_PTR g_gdiplusToken = 0;
static CLSID g_pngClsid = {};

static int FindPngEncoder() {
    UINT num = 0, size = 0;
    Gdiplus::GetImageEncodersSize(&num, &size);
    if (size == 0) return -1;
    auto* codecs = (Gdiplus::ImageCodecInfo*)malloc(size);
    if (!codecs) return -1;
    Gdiplus::GetImageEncoders(num, size, codecs);
    int found = -1;
    for (UINT i = 0; i < num; i++) {
        if (wcscmp(codecs[i].MimeType, L"image/png") == 0) {
            g_pngClsid = codecs[i].Clsid;
            found = 0;
            break;
        }
    }
    free(codecs);
    return found;
}

static bool EnsureGdiplus() {
    if (g_gdiplusReady) return true;
    Gdiplus::GdiplusStartupInput input;
    if (Gdiplus::GdiplusStartup(&g_gdiplusToken, &input, nullptr) != Gdiplus::Ok)
        return false;
    if (FindPngEncoder() < 0) return false;
    g_gdiplusReady = true;
    return true;
}

// -- Public API -------------------------------------------------------

static const int kInfDirImageIconOnly = 0x1;
static const int kInfDirImageThumbnailOnly = 0x2;
static const int kInfDirImageInCacheOnly = 0x4;

static unsigned char* BitmapToPng(HBITMAP hBitmap, int* outSize) {
    *outSize = 0;
    if (!hBitmap || !EnsureGdiplus()) return nullptr;

    BITMAP bm = {};
    if (!GetObject(hBitmap, sizeof(bm), &bm) || bm.bmWidth <= 0 || bm.bmHeight <= 0) {
        return nullptr;
    }
    if (!bm.bmBits) return nullptr;

    int rowBytes = abs(bm.bmWidthBytes);
    int height = bm.bmHeight;
    int width = bm.bmWidth;
    BYTE* flippedBits = (BYTE*)malloc(rowBytes * height);
    if (!flippedBits) return nullptr;

    BYTE* srcBits = (BYTE*)bm.bmBits;
    for (int y = 0; y < height; y++) {
        memcpy(flippedBits + (height - 1 - y) * rowBytes,
               srcBits + y * rowBytes,
               rowBytes);
    }

    Gdiplus::Bitmap bmp(width, height, rowBytes, PixelFormat32bppARGB, flippedBits);

    IStream* stm = nullptr;
    if (CreateStreamOnHGlobal(nullptr, TRUE, &stm) != S_OK) {
        free(flippedBits);
        return nullptr;
    }

    unsigned char* buf = nullptr;
    if (bmp.Save(stm, &g_pngClsid) == Gdiplus::Ok) {
        HGLOBAL hg = nullptr;
        GetHGlobalFromStream(stm, &hg);
        SIZE_T sz = GlobalSize(hg);
        void* src = GlobalLock(hg);
        buf = (unsigned char*)CoTaskMemAlloc(sz);
        if (buf) {
            memcpy(buf, src, sz);
            *outSize = (int)sz;
        }
        GlobalUnlock(hg);
    }

    stm->Release();
    free(flippedBits);
    return buf;
}

static int ToSiigbf(int flags) {
    int siigbf = SIIGBF_BIGGERSIZEOK;
    if (flags & kInfDirImageIconOnly) {
        siigbf |= SIIGBF_ICONONLY;
    } else {
        siigbf |= SIIGBF_RESIZETOFIT;
    }
    if (flags & kInfDirImageThumbnailOnly) siigbf |= SIIGBF_THUMBNAILONLY;
    if (flags & kInfDirImageInCacheOnly) siigbf |= SIIGBF_INCACHEONLY;
    return siigbf;
}

// Forward declaration: the fast PIDL path converts the Shell image-list icon
// through the same PNG encoder as the regular bitmap path below.
static unsigned char* IconToPng(HICON hIcon, int size, int* outSize);

// IShellItemImageFactory may enter a namespace extension while resolving a
// virtual item's image and block for several seconds. The system image list
// already contains the resolved icon index, so use that cache for icon-only
// requests and reserve GetImage for thumbnails/normal paths.
static unsigned char* GetPidlIconFromSystemImageList(
    const wchar_t* path, int size, int* outSize) {
    PIDLIST_ABSOLUTE pidl = nullptr;
    if (FAILED(InfDirGetPidlFromPath(path, &pidl)) || !pidl) return nullptr;

    SHFILEINFOW info = {};
    const UINT iconFlags = SHGFI_PIDL | SHGFI_SYSICONINDEX |
        (size <= 32 ? SHGFI_SMALLICON : SHGFI_LARGEICON);
    const DWORD_PTR result = SHGetFileInfoW(
        reinterpret_cast<LPCWSTR>(pidl), 0, &info, sizeof(info), iconFlags);
    if (!result) {
        CoTaskMemFree(pidl);
        return nullptr;
    }

    IImageList* imageList = nullptr;
    const int listType = size <= 32 ? SHIL_SMALL : SHIL_LARGE;
    HICON icon = nullptr;
    if (SUCCEEDED(SHGetImageList(listType, IID_IImageList,
                                 reinterpret_cast<void**>(&imageList))) &&
        imageList) {
        imageList->GetIcon(info.iIcon, ILD_TRANSPARENT, &icon);
        imageList->Release();
    }
    CoTaskMemFree(pidl);

    if (!icon) return nullptr;
    auto* png = IconToPng(icon, size, outSize);
    DestroyIcon(icon);
    return png;
}

static unsigned char* GetShellImagePng(
    const wchar_t* path, int size, int siigbfFlags, int* outSize) {
    if (!path || !outSize || size <= 0) return nullptr;
    *outSize = 0;
    if (!EnsureGdiplus()) return nullptr;

    bool comInitialized = false;
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(hr)) return nullptr;
    comInitialized = (hr == S_OK);

    if (InfDirIsPidlPath(path) && (siigbfFlags & SIIGBF_ICONONLY)) {
        auto* cachedIcon = GetPidlIconFromSystemImageList(path, size, outSize);
        if (cachedIcon) {
            if (comInitialized) CoUninitialize();
            return cachedIcon;
        }
    }

    IShellItemImageFactory* factory = nullptr;
    IShellItem* shellItem = nullptr;
    hr = InfDirCreateShellItemFromPath(path, &shellItem);
    if (SUCCEEDED(hr) && shellItem) {
        hr = shellItem->QueryInterface(IID_PPV_ARGS(&factory));
        shellItem->Release();
    }
    if (FAILED(hr) || !factory) {
        InfDirShellLog(L"icon resolve failed path=" + std::wstring(path) + L" hr=0x" +
                       std::to_wstring(static_cast<unsigned long>(hr)));
        if (comInitialized) CoUninitialize();
        return nullptr;
    }

    HBITMAP hBitmap = nullptr;
    hr = factory->GetImage({size, size}, siigbfFlags, &hBitmap);
    factory->Release();
    if (FAILED(hr) || !hBitmap) {
        InfDirShellLog(L"icon image failed path=" + std::wstring(path) + L" hr=0x" +
                       std::to_wstring(static_cast<unsigned long>(hr)));
        if (comInitialized) CoUninitialize();
        return nullptr;
    }

    unsigned char* buf = BitmapToPng(hBitmap, outSize);
    DeleteObject(hBitmap);
    if (comInitialized) CoUninitialize();
    return buf;
}

extern "C" __declspec(dllexport)
unsigned char* GetFileIconPngW(const wchar_t* path, int size, int* outSize) {
    auto* result = GetShellImagePng(
        path, size, SIIGBF_ICONONLY | SIIGBF_BIGGERSIZEOK, outSize);
    if (path) {
        InfDirShellLog(L"icon request path=" + std::wstring(path) +
                       L" size=" + std::to_wstring(size) + L" resultBytes=" +
                       std::to_wstring(result && outSize ? *outSize : 0));
    }
    return result;
}

extern "C" __declspec(dllexport)
unsigned char* GetFileImagePngW(
    const wchar_t* path, int size, int flags, int* outSize) {
    if (!path || !outSize || size <= 0) return nullptr;
    *outSize = 0;

    const bool thumbnailOnly = (flags & kInfDirImageThumbnailOnly) != 0;
    const bool cacheOnly = (flags & kInfDirImageInCacheOnly) != 0;
    if (thumbnailOnly && !cacheOnly) {
        unsigned char* cached = GetShellImagePng(
            path, size, ToSiigbf(flags | kInfDirImageInCacheOnly), outSize);
        if (cached) return cached;
        *outSize = 0;
    }
    return GetShellImagePng(path, size, ToSiigbf(flags), outSize);
}

extern "C" __declspec(dllexport)
void FreeIconPngW(unsigned char* ptr) {
    if (ptr) CoTaskMemFree(ptr);
}

// -- HICON to 32-bit top-down HBITMAP to PNG -------------------------

static unsigned char* IconToPng(HICON hIcon, int size, int* outSize) {
    *outSize = 0;
    if (!hIcon || !EnsureGdiplus()) return nullptr;

    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = size;
    bmi.bmiHeader.biHeight = -size; // top-down
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    void* bits = nullptr;
    HDC screenDC = GetDC(nullptr);
    HBITMAP hBmp = CreateDIBSection(screenDC, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
    ReleaseDC(nullptr, screenDC);
    if (!hBmp) return nullptr;

    HDC memDC = CreateCompatibleDC(nullptr);
    HGDIOBJ old = SelectObject(memDC, hBmp);
    DrawIconEx(memDC, 0, 0, hIcon, size, size, 0, nullptr, DI_NORMAL);
    SelectObject(memDC, old);
    DeleteDC(memDC);

    // Top-down 32-bit ARGB, no row flip needed
    Gdiplus::Bitmap bmp(size, size, size * 4, PixelFormat32bppARGB, (BYTE*)bits);

    IStream* stm = nullptr;
    if (CreateStreamOnHGlobal(nullptr, TRUE, &stm) != S_OK) {
        DeleteObject(hBmp);
        return nullptr;
    }

    unsigned char* buf = nullptr;
    if (bmp.Save(stm, &g_pngClsid) == Gdiplus::Ok) {
        HGLOBAL hg = nullptr;
        GetHGlobalFromStream(stm, &hg);
        SIZE_T sz = GlobalSize(hg);
        void* src = GlobalLock(hg);
        buf = (unsigned char*)CoTaskMemAlloc(sz);
        if (buf) {
            memcpy(buf, src, sz);
            *outSize = (int)sz;
        }
        GlobalUnlock(hg);
    }

    stm->Release();
    DeleteObject(hBmp);
    return buf;
}

// -- Shell overlay (SHGetFileInfo + SHGFI_OVERLAYINDEX) ----------------
// Same approach as the Files app: let the shell resolve which overlay
// applies, then pull it from the system image list via the overlay index
// packed in the high byte of SHFILEINFO::iIcon.

extern "C" __declspec(dllexport)
unsigned char* GetFileOverlayPngW(const wchar_t* path, int size, int* outSize) {
    if (!path || !outSize || size <= 0) return nullptr;
    *outSize = 0;

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(hr)) return nullptr;
    bool comInitialized = (hr == S_OK);

    SHFILEINFOW sfi = {};
    DWORD_PTR result = SHGetFileInfoW(path, 0, &sfi, sizeof(sfi),
        SHGFI_OVERLAYINDEX | SHGFI_ICON | SHGFI_SYSICONINDEX | SHGFI_ICONLOCATION);
    if (!result) {
        if (comInitialized) CoUninitialize();
        return nullptr;
    }
    if (sfi.hIcon) DestroyIcon(sfi.hIcon);

    int overlayIdx = (int)(sfi.iIcon >> 24);
    if (overlayIdx == 0) {
        if (comInitialized) CoUninitialize();
        return nullptr;
    }

    unsigned char* png = nullptr;
    IImageList* piml = nullptr;
    if (SUCCEEDED(SHGetImageList(SHIL_LARGE, IID_IImageList, (void**)&piml)) && piml) {
        int overlayImageIdx = 0;
        if (SUCCEEDED(piml->GetOverlayImage(overlayIdx, &overlayImageIdx))) {
            HICON hOverlay = nullptr;
            if (SUCCEEDED(piml->GetIcon(overlayImageIdx, ILD_TRANSPARENT, &hOverlay)) && hOverlay) {
                png = IconToPng(hOverlay, size, outSize);
                DestroyIcon(hOverlay);
            }
        }
        piml->Release();
    }

    if (comInitialized) CoUninitialize();
    return png;
}

// -- Cloud sync status (IPropertyStore) ---------------------------------
// Semantic codes: -1 not cloud, 0 online only, 1 locally available,
// 2 pinned, 3 syncing, 4 excluded.

static bool ReadUintShellProperty(IPropertyStore* pps, const wchar_t* propName, UINT* out) {
    PROPERTYKEY pk;
    if (FAILED(PSGetPropertyKeyFromName(propName, &pk))) return false;
    PROPVARIANT pv;
    PropVariantInit(&pv);
    bool ok = false;
    if (SUCCEEDED(pps->GetValue(pk, &pv)) && pv.vt == VT_UI4) {
        *out = pv.ulVal;
        ok = true;
    }
    PropVariantClear(&pv);
    return ok;
}

extern "C" __declspec(dllexport)
int GetFileCloudStatusW(const wchar_t* path) {
    if (!path) return -1;

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(hr)) return -1;
    bool comInitialized = (hr == S_OK);

    int status = -1;

    IPropertyStore* pps = nullptr;
    hr = SHGetPropertyStoreFromParsingName(path, nullptr, GPS_DEFAULT, IID_PPV_ARGS(&pps));
    if (SUCCEEDED(hr) && pps) {
        UINT sps = 0, ph = 0;
        bool hasSps = ReadUintShellProperty(pps, L"System.StorageProviderState", &sps);
        bool hasPh = ReadUintShellProperty(pps, L"System.FilePlaceholderStatus", &ph);
        pps->Release();

        // Modern storage-provider state wins: it distinguishes "excluded"
        // (9), which the legacy placeholder status reports as plain
        // locally-available (14).
        if (hasSps) {
            switch (sps) {
                case 1: status = 0; break; // online only
                case 2: status = 1; break; // locally available
                case 3: status = 2; break; // pinned / always on device
                case 9: status = 4; break; // excluded from sync
                default: break;
            }
        }
        if (status < 0 && hasPh) {
            switch (ph) {
                case 8:  // FileOnline
                case 0:  // FolderOnline
                    status = 0; break;
                case 14: // FileOffline
                case 2:  // FolderOfflineFull
                case 1:  // FolderOfflinePartial
                case 5:  // FolderEmpty
                    status = 1; break;
                case 15: // FileOfflinePinned
                case 3:  // FolderOfflinePinned
                    status = 2; break;
                case 9:  // FileSync
                    status = 3; break;
                case 4:  // FolderExcluded
                    status = 4; break;
                default: break;
            }
        }
    }

    if (comInitialized) CoUninitialize();
    return status;
}
