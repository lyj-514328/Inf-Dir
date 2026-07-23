#pragma once
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns the system image list icon index for a file path.
// Uses SHGFI_USEFILEATTRIBUTES so the file need not exist on disk.
// Returns -1 on failure.
__declspec(dllexport)
int GetFileIconIndexW(const wchar_t* path, DWORD fileAttributes);

// Extracts the icon at the given system image list index as PNG bytes.
// Returns a CoTaskMem-allocated buffer; caller must free with FreeIconPngW.
// Returns NULL on failure. *outSize receives the byte count.
__declspec(dllexport)
unsigned char* GetIconPngByIndexW(int iconIndex, int* outSize);

__declspec(dllexport)
void FreeIconPngW(unsigned char* ptr);

#ifdef __cplusplus
}
#endif
