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

// Empties the shared Windows Recycle Bin without showing Shell UI. The app
// owns confirmation and error reporting.
__declspec(dllexport)
HRESULT EmptyRecycleBinW(HWND owner);

// Restores Recycle Bin items to their original directories. Each source path
// is a Shell parsing name for a $R item; the original directory is read from
// System.Recycle.DeletedFrom so the Shell preserves the original item name.
// destinationOverrides may be NULL, or an array with one entry per source
// path (entries may be NULL): a non-empty override replaces the original
// directory, which is how the app restores items whose original folder no
// longer exists. When any override is present, name collisions are resolved
// by the Shell renaming the restored item.
__declspec(dllexport)
HRESULT RestoreRecycleBinItemsW(
    HWND owner,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t** destinationOverrides);

// Shows the native folder-picker dialog, modal to the foreground window.
// On success *outPath is a CoTaskMem-allocated filesystem path (UTF-16) that
// the caller must free with FreeCoTaskMemW. Returns
// HRESULT_FROM_WIN32(ERROR_CANCELLED) when the user cancels.
__declspec(dllexport)
HRESULT PickFolderW(
    HWND owner,
    const wchar_t* initialPath,
    wchar_t** outPath);

// Frees a string previously returned by PickFolderW.
__declspec(dllexport)
void FreeCoTaskMemW(void* ptr);

#ifdef __cplusplus
}
#endif
