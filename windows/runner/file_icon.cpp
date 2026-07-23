#include "file_icon.h"
#include <shlobj.h>
#include <shobjidl.h>
#include <objbase.h>
#include <gdiplus.h>

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
    IShellItemImageFactory* factory = nullptr;
    hr = SHCreateItemFromParsingName(path, nullptr, IID_IShellItemImageFactory, (void**)&factory);
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
