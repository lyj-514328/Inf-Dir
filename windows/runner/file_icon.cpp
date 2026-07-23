#include "file_icon.h"
#include <shlobj.h>
#include <commctrl.h>
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
int GetFileIconIndexW(const wchar_t* path, DWORD fileAttributes) {
    SHFILEINFOW sfi = {};
    HIMAGELIST hil = (HIMAGELIST)SHGetFileInfoW(
        path, fileAttributes, &sfi, sizeof(sfi),
        SHGFI_SYSICONINDEX | SHGFI_SMALLICON | SHGFI_USEFILEATTRIBUTES);
    return hil ? sfi.iIcon : -1;
}

extern "C" __declspec(dllexport)
unsigned char* GetIconPngByIndexW(int iconIndex, int* outSize) {
    if (iconIndex < 0 || !outSize) return nullptr;
    *outSize = 0;
    if (!EnsureGdiplus()) return nullptr;

    // Obtain the system small-image-list handle
    SHFILEINFOW sfi = {};
    HIMAGELIST hil = (HIMAGELIST)SHGetFileInfoW(
        L".txt", 0, &sfi, sizeof(sfi),
        SHGFI_SYSICONINDEX | SHGFI_SMALLICON | SHGFI_USEFILEATTRIBUTES);
    if (!hil) return nullptr;

    HICON hIcon = ImageList_GetIcon(hil, iconIndex, ILD_NORMAL);
    if (!hIcon) return nullptr;

    // Get icon dimensions
    ICONINFO ii = {};
    if (!GetIconInfo(hIcon, &ii)) {
        DestroyIcon(hIcon);
        return nullptr;
    }
    BITMAP bm = {};
    GetObject(ii.hbmColor, sizeof(bm), &bm);
    int w = bm.bmWidth;
    int h = bm.bmHeight;
    if (ii.hbmColor) DeleteObject(ii.hbmColor);
    if (ii.hbmMask) DeleteObject(ii.hbmMask);
    if (w <= 0 || h <= 0) { w = 16; h = 16; }

    // Draw icon onto a 32-bit ARGB bitmap for correct alpha
    Gdiplus::Bitmap bmp(w, h, PixelFormat32bppARGB);
    {
        Gdiplus::Graphics graphics(&bmp);
        graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
        HDC hdc = graphics.GetHDC();
        DrawIconEx(hdc, 0, 0, hIcon, w, h, 0, nullptr, DI_NORMAL);
        graphics.ReleaseHDC(hdc);
    }
    DestroyIcon(hIcon);

    IStream* stm = nullptr;
    if (CreateStreamOnHGlobal(nullptr, TRUE, &stm) != S_OK) return nullptr;

    if (bmp.Save(stm, &g_pngClsid) != Gdiplus::Ok) {
        stm->Release();
        return nullptr;
    }

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
    return buf;
}

extern "C" __declspec(dllexport)
void FreeIconPngW(unsigned char* ptr) {
    if (ptr) CoTaskMemFree(ptr);
}
