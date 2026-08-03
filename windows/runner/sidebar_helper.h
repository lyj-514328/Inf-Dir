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

// Enumerate cloud drive sync roots via the official CfAPI registry:
// HKLM\...\Explorer\SyncRootManager (any compliant provider: OneDrive,
// Baidu Netdisk, Dropbox, ...). Name comes from DisplayNameResource,
// path from UserSyncRoots keyed by the current user's SID.
// Returns a flat buffer layout:
//   [count: int32]
//   for each item:
//     [nameLen: int32] [nameChars: wchar_t[]] [pathLen: int32] [pathChars: wchar_t[]]
// Returns NULL on failure. *outSize receives total byte count.
// Caller must free with FreeSidebarItems().
__declspec(dllexport)
unsigned char* GetCloudDriveRoots(int* outSize);

// Free any buffer allocated by the above functions.
__declspec(dllexport)
void FreeSidebarItems(unsigned char* ptr);

// Lightweight check: returns 1 if [path] has at least one subdirectory
// (excluding . and ..), 0 if not or on error.
__declspec(dllexport)
int ProbeDirectoryHasChildren(const wchar_t* path);

#ifdef __cplusplus
}
#endif
