#pragma once

#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Enumerates the Windows Shell "Open with" submenu for one filesystem file.
// The returned buffer uses this layout:
//   [count: int32]
//   for each entry:
//     [kind: int32] [commandId: int32] [enabled: int32]
//     [labelLen: int32] [labelChars: wchar_t[]]
//     [iconPngLen: int32] [iconPngBytes: uint8[]]
// kind is 0 for a command and 1 for a separator. commandId is the Shell menu
// identifier expected by InvokeOpenWithMenuEntry(). Free it with
// FreeOpenWithMenuEntries().
__declspec(dllexport)
unsigned char* GetOpenWithMenuEntriesW(const wchar_t* filePath, int* outSize);

__declspec(dllexport)
void FreeOpenWithMenuEntries(unsigned char* ptr);

// Invokes one command returned by GetOpenWithMenuEntriesW(). Calling this
// releases the cached Shell menu, so commandId values are valid only until the
// next enumeration call.
__declspec(dllexport)
HRESULT InvokeOpenWithMenuEntry(int commandId, HWND hwnd);

#ifdef __cplusplus
}
#endif
