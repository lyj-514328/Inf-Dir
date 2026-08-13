#include "file_operations.h"

#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <knownfolders.h>
#include <propkey.h>

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
        if (!permanentDelete) {
            flags |= FOF_ALLOWUNDO | FOFX_RECYCLEONDELETE;
        }
    } else {
        flags = FOF_ALLOWUNDO | FOF_NOCONFIRMMKDIR | FOF_SILENT | FOF_NOERRORUI;
    }
    hr = pfo->SetOperationFlags(flags);
    if (FAILED(hr)) {
        pfo->Release();
        return hr;
    }

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
        if (FAILED(hr)) {
            if (dest) dest->Release();
            pfo->Release();
            return hr;
        }
        switch (operation) {
        case 0: hr = pfo->CopyItem(src, dest, nullptr, nullptr); break;
        case 1: hr = pfo->MoveItem(src, dest, nullptr, nullptr); break;
        case 2: hr = pfo->DeleteItem(src, nullptr); break;
        default: hr = E_INVALIDARG; break;
        }
        src->Release();
        if (FAILED(hr)) {
            if (dest) dest->Release();
            pfo->Release();
            return hr;
        }
    }

    hr = pfo->PerformOperations();
    BOOL aborted = FALSE;
    if (SUCCEEDED(hr)) {
        pfo->GetAnyOperationsAborted(&aborted);
        if (aborted) hr = HRESULT_FROM_WIN32(ERROR_CANCELLED);
    }
    pfo->Release();
    if (dest) dest->Release();
    return hr;
}

extern "C" __declspec(dllexport)
HRESULT EmptyRecycleBinW(HWND owner)
{
    return SHEmptyRecycleBinW(owner, nullptr,
        SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
}

extern "C" __declspec(dllexport)
HRESULT RestoreRecycleBinItemsW(
    HWND owner,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t** destinationOverrides)
{
    if (!sourcePaths || sourceCount <= 0) return E_INVALIDARG;

    IShellItem* recycleBin = nullptr;
    HRESULT hr = SHGetKnownFolderItem(FOLDERID_RecycleBinFolder,
        KF_FLAG_DEFAULT, nullptr, IID_PPV_ARGS(&recycleBin));
    if (FAILED(hr) || !recycleBin) return FAILED(hr) ? hr : E_FAIL;

    IEnumShellItems* items = nullptr;
    hr = recycleBin->BindToHandler(nullptr, BHID_EnumItems,
        IID_PPV_ARGS(&items));
    recycleBin->Release();
    if (FAILED(hr) || !items) return FAILED(hr) ? hr : E_FAIL;

    IFileOperation* pfo = nullptr;
    hr = CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_ALL,
        IID_PPV_ARGS(&pfo));
    if (FAILED(hr)) {
        items->Release();
        return hr;
    }

    DWORD flags = FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;
    if (destinationOverrides) flags |= FOF_RENAMEONCOLLISION;
    hr = pfo->SetOperationFlags(flags);
    if (SUCCEEDED(hr) && owner) hr = pfo->SetOwnerWindow(owner);
    if (FAILED(hr)) {
        items->Release();
        pfo->Release();
        return hr;
    }

    PROPERTYKEY originalDirectoryKey = {};
    hr = PSGetPropertyKeyFromName(
        L"System.Recycle.DeletedFrom", &originalDirectoryKey);
    if (FAILED(hr)) {
        items->Release();
        pfo->Release();
        return hr;
    }

    auto isMatched = new bool[sourceCount]();
    int matchedCount = 0;
    IShellItem* source = nullptr;
    while (matchedCount < sourceCount &&
           items->Next(1, &source, nullptr) == S_OK) {
        PWSTR parsingName = nullptr;
        hr = source->GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING,
            &parsingName);
        int selectedIndex = -1;
        if (SUCCEEDED(hr) && parsingName) {
            for (int i = 0; i < sourceCount; i++) {
                if (!isMatched[i] && sourcePaths[i] &&
                    _wcsicmp(sourcePaths[i], parsingName) == 0) {
                    selectedIndex = i;
                    break;
                }
            }
        }
        if (parsingName) CoTaskMemFree(parsingName);
        if (selectedIndex < 0) {
            source->Release();
            source = nullptr;
            continue;
        }

        // Prefer the caller-provided override; otherwise fall back to the
        // original directory recorded by the Shell.
        const wchar_t* override = (destinationOverrides &&
                                   destinationOverrides[selectedIndex] &&
                                   *destinationOverrides[selectedIndex])
            ? destinationOverrides[selectedIndex] : nullptr;
        PWSTR originalDirectory = nullptr;
        if (override) {
            hr = S_OK;
        } else {
            IShellItem2* source2 = nullptr;
            hr = source->QueryInterface(IID_PPV_ARGS(&source2));
            if (SUCCEEDED(hr)) {
                hr = source2->GetString(originalDirectoryKey,
                    &originalDirectory);
            }
            if (source2) source2->Release();
        }
        if (SUCCEEDED(hr)) {
            const wchar_t* target = override ? override : originalDirectory;
            if (target && *target) {
                IShellItem* destination = nullptr;
                hr = SHCreateItemFromParsingName(target, nullptr,
                    IID_PPV_ARGS(&destination));
                if (SUCCEEDED(hr)) {
                    // A null new name asks Shell to restore the item's
                    // original display name, including the extension.
                    hr = pfo->MoveItem(source, destination, nullptr, nullptr);
                    destination->Release();
                }
            } else {
                hr = E_INVALIDARG;
            }
        }
        if (originalDirectory) CoTaskMemFree(originalDirectory);
        source->Release();
        source = nullptr;
        if (FAILED(hr)) break;

        isMatched[selectedIndex] = true;
        matchedCount++;
    }
    if (source) source->Release();
    items->Release();
    if (SUCCEEDED(hr) && matchedCount != sourceCount) {
        hr = HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
    }
    delete[] isMatched;

    if (SUCCEEDED(hr)) {
        hr = pfo->PerformOperations();
        BOOL aborted = FALSE;
        if (SUCCEEDED(hr)) {
            pfo->GetAnyOperationsAborted(&aborted);
            if (aborted) hr = HRESULT_FROM_WIN32(ERROR_CANCELLED);
        }
    }
    pfo->Release();
    return hr;
}

extern "C" __declspec(dllexport)
HRESULT PickFolderW(HWND owner, const wchar_t* initialPath, wchar_t** outPath)
{
    if (!outPath) return E_INVALIDARG;
    *outPath = nullptr;

    IFileOpenDialog* dialog = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
    if (FAILED(hr)) return hr;

    DWORD options = 0;
    hr = dialog->GetOptions(&options);
    if (SUCCEEDED(hr)) {
        hr = dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
    }
    if (SUCCEEDED(hr) && initialPath && *initialPath) {
        IShellItem* initialItem = nullptr;
        hr = SHCreateItemFromParsingName(initialPath, nullptr,
            IID_PPV_ARGS(&initialItem));
        if (SUCCEEDED(hr)) {
            hr = dialog->SetFolder(initialItem);
            initialItem->Release();
        } else {
            // Unusable initial path: let the dialog start at its default.
            hr = S_OK;
        }
    }
    if (SUCCEEDED(hr)) {
        hr = dialog->Show(owner);
        if (SUCCEEDED(hr)) {
            IShellItem* result = nullptr;
            hr = dialog->GetResult(&result);
            if (SUCCEEDED(hr) && result) {
                PWSTR path = nullptr;
                hr = result->GetDisplayName(SIGDN_FILESYSPATH, &path);
                if (SUCCEEDED(hr) && path) {
                    const size_t length = wcslen(path) + 1;
                    *outPath = static_cast<wchar_t*>(
                        CoTaskMemAlloc(length * sizeof(wchar_t)));
                    if (*outPath) {
                        wcscpy_s(*outPath, length, path);
                    } else {
                        hr = E_OUTOFMEMORY;
                    }
                    CoTaskMemFree(path);
                }
                result->Release();
            }
        }
    }
    dialog->Release();
    return hr;
}

extern "C" __declspec(dllexport)
void FreeCoTaskMemW(void* ptr)
{
    CoTaskMemFree(ptr);
}
