#pragma once

#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Enumerates the recommended application handlers registered for a file's
// extension using SHAssocEnumHandlers. Icons are loaded from each handler's
// original Shell icon resource at iconSize physical pixels.
// The returned buffer uses this layout:
//   [count: int32]
//   [defaultAppIconPngLen: int32] [defaultAppIconPngBytes: uint8[]]
//   for each entry:
//     [kind: int32] [commandId: int32] [enabled: int32]
//     [labelLen: int32] [labelChars: wchar_t[]]
//     [iconPngLen: int32] [iconPngBytes: uint8[]]
// kind is 0 for a command (1 remains reserved for separators). commandId is an
// opaque identifier expected by InvokeOpenWithMenuEntry(). Free the buffer
// with FreeOpenWithMenuEntries().
__declspec(dllexport)
unsigned char* GetOpenWithMenuEntriesW(
    const wchar_t* filePath,
    int iconSize,
    int* outSize);

__declspec(dllexport)
void FreeOpenWithMenuEntries(unsigned char* ptr);

// Invokes the cached IAssocHandler for one command. Identifiers remain valid
// until an item is invoked or another file is enumerated.
__declspec(dllexport)
HRESULT InvokeOpenWithMenuEntry(int commandId);

#ifdef __cplusplus
}
#endif
