#pragma once
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Enumerate the "New" menu items registered for HKCR extension keys
// (ShellNew subkeys), mirroring Explorer's "New >" submenu. The display
// name comes from the ItemName value, the ProgID's friendly name, or the
// registered file type name. Each entry carries everything needed to
// create the item: template path, raw data bytes, a launch command, and
// a 16x16 PNG icon for the file type.
//
// Returned buffer layout:
//   [count: int32]
//   for each item:
//     [extLen: int32] [extChars: wchar_t[]]             -- ".ext"
//     [nameLen: int32] [nameChars: wchar_t[]]           -- display name
//     [tplLen: int32] [tplChars: wchar_t[]]             -- resolved template path (may be empty)
//     [cmdLen: int32] [cmdChars: wchar_t[]]             -- creation command (may be empty)
//     [dataLen: int32] [dataBytes: uint8[]]             -- file content (may be empty)
//     [pngLen: int32] [pngBytes: uint8[]]               -- icon PNG (may be empty)
//
// Free the buffer with FreeShellNewEntries().
__declspec(dllexport)
unsigned char* GetShellNewEntries(int* outSize);

__declspec(dllexport)
void FreeShellNewEntries(unsigned char* ptr);

#ifdef __cplusplus
}
#endif
