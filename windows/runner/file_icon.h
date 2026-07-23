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

__declspec(dllexport)
void FreeIconPngW(unsigned char* ptr);

#ifdef __cplusplus
}
#endif
