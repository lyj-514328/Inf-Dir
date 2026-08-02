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

// Returns the shell overlay icon (e.g. shortcut arrow, OneDrive badge) as PNG
// bytes. Enumerates IShellIconOverlayIdentifier handlers in priority order and
// returns the first matching overlay. Returns NULL if no overlay applies.
__declspec(dllexport)
unsigned char* GetFileOverlayPngW(const wchar_t* path, int size, int* outSize);

// Returns the cloud placeholder sync status for a file/folder.
// Reads System.FilePlaceholderStatus via IPropertyStore.
// Returns -1 if the item is not a cloud placeholder or on failure.
// Non-negative values map to CloudDriveSyncStatus (0-5 folder states,
// 6 = NotSynced, 8 = FileOnline, 9 = FileSync, 14/15 = FileOffline).
__declspec(dllexport)
int GetFileCloudStatusW(const wchar_t* path);

__declspec(dllexport)
void FreeIconPngW(unsigned char* ptr);

#ifdef __cplusplus
}
#endif
