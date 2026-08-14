#pragma once
#include <windows.h>
#include <stdint.h>

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

// Starts a copy/move/delete on a native worker thread so the Flutter UI
// isolate never blocks on the Shell operation. Returns immediately with
// *operationId identifying the operation for InfDirPollFileOperationW /
// InfDirCancelFileOperationW. collisionMode selects the copy/move collision
// policy: 0 = silently replace, 1 = keep both (FOF_RENAMEONCOLLISION).
__declspec(dllexport)
HRESULT InfDirStartFileOperationW(
    int operation,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t* destinationFolder,
    int permanentDelete,
    int collisionMode,
    int64_t* operationId);

// Polls the worker-thread operation. *status: 0 queued, 1 running,
// 2 succeeded, 3 failed, 4 cancelled. *progress is 0-100. Returns
// HRESULT_FROM_WIN32(ERROR_NOT_FOUND) for an unknown operation id.
__declspec(dllexport)
HRESULT InfDirPollFileOperationW(
    int64_t operationId,
    int* status,
    int* progress,
    int* result);

// Requests cancellation of a running worker-thread operation. The flag stops
// further items from being queued; an in-flight FOF_SILENT PerformOperations
// cannot be interrupted and reports its outcome when it returns.
__declspec(dllexport)
HRESULT InfDirCancelFileOperationW(int64_t operationId);

// Takes the per-item results of a finished operation as a UTF-8 JSON array
// of {"path": ..., "hr": ...} objects, allocated with CoTaskMemAlloc (free
// with FreeCoTaskMemW). Returns S_OK with *outJson = nullptr when the
// operation recorded no items. The stored results are consumed on first call.
__declspec(dllexport)
HRESULT InfDirGetFileOperationResultsW(int64_t operationId, char** outJson);

// Removes the operation state from the registry after its results have been
// consumed, preventing unbounded growth across many operations.
__declspec(dllexport)
HRESULT InfDirCloseFileOperationW(int64_t operationId);

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
// longer exists. collisionMode selects the name-collision policy:
// 0 = replace the existing item (silent), 1 = keep both (rename the restore).
__declspec(dllexport)
HRESULT RestoreRecycleBinItemsW(
    HWND owner,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t** destinationOverrides,
    int collisionMode);

// Starts a Recycle Bin restore on a native worker thread: enumerates the bin,
// queues the matched items and performs the move without blocking the Flutter
// UI isolate. Progress and per-item results are reported through the same
// poll / results protocol as InfDirStartFileOperationW.
__declspec(dllexport)
HRESULT InfDirStartRestoreOperationW(
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t** destinationOverrides,
    int collisionMode,
    int64_t* operationId);

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
