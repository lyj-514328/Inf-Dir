#pragma once
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Enumerate the Windows "Recent" shell folder (shell:Recent) in
// most-recently-used order, resolving each shortcut to its target file.
// Folder targets, dead links and duplicates are excluded, matching the
// "Recent files" list on Explorer's Home page.
//
// Returned buffer layout:
//   [count: int32]
//   for each item:
//     [pathLen: int32] [pathChars: wchar_t[]]        -- resolved target path
//     [modifiedLen: int32] [modifiedChars: wchar_t[]] -- "YYYY/MM/DD HH:MM:SS"
//
// limit <= 0 means no limit. Free the buffer with FreeRecentFiles().
__declspec(dllexport)
unsigned char* GetRecentFiles(int limit, int* outSize);

__declspec(dllexport)
void FreeRecentFiles(unsigned char* ptr);

#ifdef __cplusplus
}
#endif
