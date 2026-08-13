#include "file_operations.h"

#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

HRESULT RunFileOperationW(
    int operation,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t* destinationFolder,
    int permanentDelete)
{
    if (!sourcePaths || sourceCount <= 0) return E_INVALIDARG;

    IFileOperation* pfo = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_ALL,
        IID_PPV_ARGS(&pfo));
    if (FAILED(hr)) return hr;

    // Silent shell operation: we show our own confirm dialogs and rely on the
    // shell undo stack instead of the shell's progress/collision UI.
    DWORD flags;
    if (operation == 2) {
        // Delete: recycle to the Recycle Bin (undoable) unless permanent.
        flags = FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;
        if (!permanentDelete) flags |= FOF_ALLOWUNDO;
    } else {
        flags = FOF_ALLOWUNDO | FOF_NOCONFIRMMKDIR | FOF_SILENT | FOF_NOERRORUI;
    }
    pfo->SetOperationFlags(flags);

    IShellItem* dest = nullptr;
    if (destinationFolder && *destinationFolder) {
        hr = SHCreateItemFromParsingName(destinationFolder, nullptr,
            IID_PPV_ARGS(&dest));
        if (FAILED(hr)) {
            pfo->Release();
            return hr;
        }
    }

    for (int i = 0; i < sourceCount; i++) {
        if (!sourcePaths[i]) continue;
        IShellItem* src = nullptr;
        hr = SHCreateItemFromParsingName(sourcePaths[i], nullptr,
            IID_PPV_ARGS(&src));
        if (FAILED(hr)) continue;
        switch (operation) {
        case 0: pfo->CopyItem(src, dest, nullptr, nullptr); break;
        case 1: pfo->MoveItem(src, dest, nullptr, nullptr); break;
        case 2: pfo->DeleteItem(src, nullptr); break;
        }
        src->Release();
    }

    hr = pfo->PerformOperations();
    pfo->Release();
    if (dest) dest->Release();
    return hr;
}
