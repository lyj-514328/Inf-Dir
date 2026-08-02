#include "file_icon.h"
#include <shlobj.h>
#include <shobjidl.h>
#include <commoncontrols.h>
#include <objbase.h>
#include <gdiplus.h>
#include <propsys.h>
#include <propvarutil.h>
#include <string>

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

extern "C" __declspec(dllexport)
unsigned char* GetFileIconPngW(const wchar_t* path, int size, int* outSize) {
    if (!path || !outSize || size <= 0) return nullptr;
    *outSize = 0;
    if (!EnsureGdiplus()) return nullptr;

    // Ensure COM is initialized on this thread
    bool comInitialized = false;
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(hr)) return nullptr;
    comInitialized = (hr == S_OK);

    // Create IShellItem and query IShellItemImageFactory
    // Normalize virtual Shell paths: "::{CLSID}" -> "shell:::{CLSID}"
    std::wstring parsingPath = path;
    if (parsingPath.substr(0, 3) == L"::{") {
        parsingPath = L"shell:" + parsingPath;
    }

    IShellItemImageFactory* factory = nullptr;
    hr = SHCreateItemFromParsingName(parsingPath.c_str(), nullptr, IID_IShellItemImageFactory, (void**)&factory);
    if (FAILED(hr) || !factory) {
        if (comInitialized) CoUninitialize();
        return nullptr;
    }

    // Get HBITMAP at requested size (icon-only, no thumbnail)
    HBITMAP hBitmap = nullptr;
    hr = factory->GetImage({size, size}, SIIGBF_ICONONLY | SIIGBF_BIGGERSIZEOK, &hBitmap);
    factory->Release();
    if (FAILED(hr) || !hBitmap) {
        if (comInitialized) CoUninitialize();
        return nullptr;
    }

    // Get bitmap info
    BITMAP bm = {};
    if (!GetObject(hBitmap, sizeof(bm), &bm) || bm.bmWidth <= 0 || bm.bmHeight <= 0) {
        DeleteObject(hBitmap);
        if (comInitialized) CoUninitialize();
        return nullptr;
    }

    // Flip rows: HBITMAP is bottom-up, GDI+ Bitmap expects top-down
    int rowBytes = abs(bm.bmWidthBytes);
    int height = bm.bmHeight;
    int width = bm.bmWidth;
    BYTE* flippedBits = (BYTE*)malloc(rowBytes * height);
    if (!flippedBits) {
        DeleteObject(hBitmap);
        if (comInitialized) CoUninitialize();
        return nullptr;
    }

    BYTE* srcBits = (BYTE*)bm.bmBits;
    for (int y = 0; y < height; y++) {
        memcpy(flippedBits + (height - 1 - y) * rowBytes,
               srcBits + y * rowBytes,
               rowBytes);
    }

    // Create GDI+ bitmap from the flipped 32-bit ARGB pixel data
    Gdiplus::Bitmap bmp(width, height, rowBytes, PixelFormat32bppARGB, flippedBits);

    // Save to PNG via IStream
    IStream* stm = nullptr;
    if (CreateStreamOnHGlobal(nullptr, TRUE, &stm) != S_OK) {
        free(flippedBits);
        DeleteObject(hBitmap);
        if (comInitialized) CoUninitialize();
        return nullptr;
    }

    if (bmp.Save(stm, &g_pngClsid) != Gdiplus::Ok) {
        stm->Release();
        free(flippedBits);
        DeleteObject(hBitmap);
        if (comInitialized) CoUninitialize();
        return nullptr;
    }

    // Read stream data into CoTaskMem-allocated buffer
    HGLOBAL hg = nullptr;
    GetHGlobalFromStream(stm, &hg);
    SIZE_T sz = GlobalSize(hg);
    void* src = GlobalLock(hg);

    unsigned char* buf = (unsigned char*)CoTaskMemAlloc(sz);
    if (buf) {
        memcpy(buf, src, sz);
        *outSize = (int)sz;
    }

    GlobalUnlock(hg);
    stm->Release();
    free(flippedBits);
    DeleteObject(hBitmap);
    if (comInitialized) CoUninitialize();
    return buf;
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

// -- Cloud placeholder sync status (IPropertyStore) --------------------
// Returns -1 when the item is not a cloud placeholder (property absent).
// Non-negative values map to STORAGE_PROVIDER_ITEM_SYNC_STATUS /
// CloudDriveSyncStatus: 0-5 folder states, 6 = NotSynced, 8 = FileOnline,
// 9 = FileSync, 14 = FileOffline, 15 = FileOfflinePinned.

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
        PROPERTYKEY pk;
        if (SUCCEEDED(PSGetPropertyKeyFromName(L"System.FilePlaceholderStatus", &pk))) {
            PROPVARIANT pv;
            PropVariantInit(&pv);
            if (SUCCEEDED(pps->GetValue(pk, &pv)) && pv.vt == VT_UI4) {
                status = (int)pv.ulVal;
            }
            PropVariantClear(&pv);
        }
        pps->Release();
    }

    if (comInitialized) CoUninitialize();
    return status;
}
