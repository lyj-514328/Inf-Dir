#pragma once
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Performs a copy/move/delete via the Windows Shell IFileOperation so the
// operation participates in the shell undo stack (FOF_ALLOWUNDO) and, for
// delete, the shared Recycle Bin.
//
// operation          - 0 = copy, 1 = move, 2 = delete
// sourcePaths        - array of full source paths (UTF-16)
// sourceCount        - number of source paths
// destinationFolder  - destination directory (NULL for delete)
// permanentDelete    - non-zero deletes permanently (Shift+Delete); zero
//                      recycles to the Recycle Bin with undo support
//
// Returns S_OK on success, otherwise an HRESULT error.
__declspec(dllexport)
HRESULT RunFileOperationW(
    int operation,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t* destinationFolder,
    int permanentDelete);

#ifdef __cplusplus
}
#endif
