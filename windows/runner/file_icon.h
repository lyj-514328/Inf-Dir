#pragma once
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns a file/folder icon as PNG bytes at the requested size.
// Uses IShellItemImageFactory for high-quality, alpha-channel-preserved icons.
// Returns a CoTaskMem-allocated buffer; caller must free with FreeIconPngW.
// Returns NULL on failure. *outSize receives the byte count.
__declspec(dllexport)
unsigned char* GetFileIconPngW(const wchar_t* path, int size, int* outSize);

// Same as GetFileIconPngW, but `flags` maps to IShellItemImageFactory options:
//   0x1 = SIIGBF_ICONONLY
//   0x2 = SIIGBF_THUMBNAILONLY
//   0x4 = SIIGBF_INCACHEONLY
// Without ICONONLY, Shell prefers a content thumbnail and falls back to an icon.
// Returns a CoTaskMem-allocated buffer; caller must free with FreeIconPngW.
__declspec(dllexport)
unsigned char* GetFileImagePngW(
    const wchar_t* path, int size, int flags, int* outSize);

// Returns the shell overlay icon (e.g. shortcut arrow, OneDrive badge) as PNG
// bytes. Enumerates IShellIconOverlayIdentifier handlers in priority order and
// returns the first matching overlay. Returns NULL if no overlay applies.
__declspec(dllexport)
unsigned char* GetFileOverlayPngW(const wchar_t* path, int size, int* outSize);

// Returns the cloud sync status for a file/folder as a semantic code:
//   -1 = not a cloud item
//    0 = online only ("Available when online")
//    1 = locally available
//    2 = pinned ("Always available on this device")
//    3 = syncing
//    4 = excluded from sync ("Excluded (not synced)")
// Prefers the modern System.StorageProviderState (1/2/3/9); falls back to the
// legacy System.FilePlaceholderStatus when the provider doesn't supply it.
// FilePlaceholderStatus alone cannot tell "excluded" from "locally available"
// (both report 14), which is why the modern property wins.
__declspec(dllexport)
int GetFileCloudStatusW(const wchar_t* path);

__declspec(dllexport)
void FreeIconPngW(unsigned char* ptr);

#ifdef __cplusplus
}
#endif
