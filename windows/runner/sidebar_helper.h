#pragma once
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Enumerate Windows Shell Quick Access items (pinned + frequent folders).
// Returns a flat buffer layout:
//   [count: int32]
//   for each item:
//     [nameLen: int32] [nameChars: wchar_t[]] [pathLen: int32] [pathChars: wchar_t[]]
// Returns NULL on failure. *outSize receives total byte count.
// Caller must free with FreeSidebarItems().
__declspec(dllexport)
unsigned char* GetQuickAccessItems(int* outSize);

// Get a drive's friendly name (e.g. "Local Disk") and file system type.
// Returns a buffer:
//   [friendlyNameLen: int32] [friendlyNameChars: wchar_t[]]
//   [fsTypeLen: int32] [fsTypeChars: wchar_t[]]
// Returns NULL on failure. Caller must free with FreeSidebarItems().
__declspec(dllexport)
unsigned char* GetDriveInfo(const wchar_t* driveRoot, int* outSize);

// Free any buffer allocated by the above functions.
__declspec(dllexport)
void FreeSidebarItems(unsigned char* ptr);

#ifdef __cplusplus
}
#endif
