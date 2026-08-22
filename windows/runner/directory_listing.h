#pragma once
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Unified directory listing for regular paths and Shell virtual folders.
//
// Handles three cases automatically:
//   1. Regular filesystem path (e.g. "C:\Users\...")  -> FindFirstFile/FindNextFile
//   2. Shell virtual folder (e.g. "shell:RecycleBinFolder", "::{CLSID}")
//      -> SHParseDisplayName + BindToHandler(BHID_EnumItems)
//   3. My Computer / This PC -> enumerates drive roots
//
// Returns a flat buffer layout:
//   [count: int32]
//   for each item:
//     [nameLen: int32] [nameChars: wchar_t[]]          -- display name
//     [nameSortKeyLen: int32] [nameSortKey: byte[]]    -- Windows natural sort key
//     [pathLen: int32] [pathChars: wchar_t[]]          -- filesystem path, empty for Shell-only items
//     [shellIdLen: int32] [shellIdChars: wchar_t[]]    -- opaque Shell identity, if any
//     [isDirectory: int32]
//     [hasChildren: int32]                              -- 1 if directory has sub-items
//     [sizeBytes: int64]
//     [modifiedDateLen: int32] [modifiedDateChars: wchar_t[]]  -- "YYYY/MM/DD HH:MM:SS"
//     [isRecycleBinItem: int32]                        -- 1 if from recycle bin
//     [originalPathLen: int32] [originalPathChars: wchar_t[]]  -- recycle bin only
//     [recycleDateLen: int32] [recycleDateChars: wchar_t[]]    -- recycle bin only
//     [parsingNameLen: int32] [parsingNameChars: wchar_t[]]    -- Recycle Bin parsing name
//
// The caller must call FreeDirectoryEntries() to release the buffer.
__declspec(dllexport)
unsigned char* ListDirectoryEntries(const wchar_t* path, int* outSize);

// Free a buffer allocated by ListDirectoryEntries.
__declspec(dllexport)
void FreeDirectoryEntries(unsigned char* ptr);

// Get the friendly display name for any path (including Shell CLSID paths).
// Returns a wchar_t* buffer allocated with CoTaskMemAlloc; caller must free
// with CoTaskMemFree (or use the FreeDirectoryEntries helper).
// Returns nullptr on failure.
__declspec(dllexport)
wchar_t* GetShellDisplayName(const wchar_t* path);

// -- Session-based paged enumeration for Shell virtual folders -----------
// Use for large folders (Recycle Bin) where full enumeration is too slow.
//
// Usage:
//   int sid = BeginShellEnum(path);
//   while (true) {
//       int size; unsigned char* page = GetNextEnumPage(sid, 100, &size);
//       if (!page) break;
//       // parse page...
//       FreeDirectoryEntries(page);
//   }
//   EndShellEnum(sid);

__declspec(dllexport)
int BeginShellEnum(const wchar_t* path, int directoriesOnly);

__declspec(dllexport)
unsigned char* GetNextEnumPage(int sessionId, int count, int* outSize);

__declspec(dllexport)
void EndShellEnum(int sessionId);

__declspec(dllexport)
long long GetRecycleBinCount(const wchar_t* driveRoot);

// Toggle hidden/system file filtering (default off). Applies to
// subsequent enumerations; open sessions re-read the flag each page.
__declspec(dllexport)
void SetShowHiddenFiles(int show);

#ifdef __cplusplus
}
#endif
