#pragma once
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Unified directory listing for regular paths and Shell virtual folders.
//
// Handles three cases automatically:
//   1. Regular filesystem path (e.g. "C:\Users\...")  → FindFirstFile/FindNextFile
//   2. Shell virtual folder (e.g. "shell:RecycleBinFolder", "::{CLSID}")
//      → SHParseDisplayName + BindToHandler(BHID_EnumItems)
//   3. My Computer / This PC → enumerates drive roots
//
// Returns a flat buffer layout:
//   [count: int32]
//   for each item:
//     [nameLen: int32] [nameChars: wchar_t[]]          -- display name
//     [pathLen: int32] [pathChars: wchar_t[]]          -- full path / parsing name
//     [isDirectory: int32]
//     [sizeBytes: int64]
//     [modifiedDateLen: int32] [modifiedDateChars: wchar_t[]]  -- "YYYY/MM/DD HH:MM:SS"
//     [isRecycleBinItem: int32]                        -- 1 if from recycle bin
//     [originalPathLen: int32] [originalPathChars: wchar_t[]]  -- recycle bin only
//     [recycleDateLen: int32] [recycleDateChars: wchar_t[]]    -- recycle bin only
//     [parsingNameLen: int32] [parsingNameChars: wchar_t[]]    -- recycle bin shell parsing name
//
// The caller must call FreeDirectoryEntries() to release the buffer.
__declspec(dllexport)
unsigned char* ListDirectoryEntries(const wchar_t* path, int* outSize);

// Free a buffer allocated by ListDirectoryEntries.
__declspec(dllexport)
void FreeDirectoryEntries(unsigned char* ptr);

#ifdef __cplusplus
}
#endif
