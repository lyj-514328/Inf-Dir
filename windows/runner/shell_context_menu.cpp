#include "shell_context_menu.h"
#include <shlobj.h>
#include <shobjidl.h>
#include <commctrl.h>
#include <strsafe.h>

// -- Helpers ----------------------------------------------------------

static bool IsVirtualShellPath(LPCWSTR path) {
    return (wcsstr(path, L"shell:") != nullptr ||
            wcsstr(path, L"::{") != nullptr);
}

static HRESULT GetFolderShellFolder(IShellFolder** ppFolder, LPCWSTR path) {
    // Virtual shell paths (e.g. "shell:RecycleBinFolder", "::{CLSID}")
    // cannot be parsed via SHGetDesktopFolder->ParseDisplayName on all
    // Windows versions. Use SHParseDisplayName instead.
    if (IsVirtualShellPath(path)) {
        PIDLIST_ABSOLUTE pidl = nullptr;
        HRESULT hr = SHParseDisplayName(path, nullptr, &pidl, 0, nullptr);
        if (FAILED(hr) || !pidl) return hr;

        IShellFolder* desktop = nullptr;
        hr = SHGetDesktopFolder(&desktop);
        if (SUCCEEDED(hr)) {
            hr = desktop->BindToObject(pidl, nullptr, IID_IShellFolder,
                reinterpret_cast<void**>(ppFolder));
            desktop->Release();
        }
        CoTaskMemFree(pidl);
        return hr;
    }

    // Regular filesystem path - use desktop->ParseDisplayName
    IShellFolder* desktop = nullptr;
    HRESULT hr = SHGetDesktopFolder(&desktop);
    if (FAILED(hr)) return hr;

    PIDLIST_ABSOLUTE pidl = nullptr;
    ULONG eaten = 0;
    hr = desktop->ParseDisplayName(nullptr, nullptr,
        const_cast<LPWSTR>(path), &eaten, &pidl, nullptr);
    if (FAILED(hr)) {
        desktop->Release();
        return hr;
    }

    hr = desktop->BindToObject(pidl, nullptr, IID_IShellFolder,
        reinterpret_cast<void**>(ppFolder));
    CoTaskMemFree(pidl);
    desktop->Release();
    return hr;
}

static const wchar_t* FileNameFromPath(const wchar_t* fullPath) {
    const wchar_t* p = wcsrchr(fullPath, L'\\');
    if (!p) p = wcsrchr(fullPath, L'/');
    return p ? p + 1 : fullPath;
}

static bool IsVerbIntercepted(const wchar_t* verb,
    const wchar_t** interceptVerbs, int interceptCount) {
    for (int i = 0; i < interceptCount; i++) {
        if (_wcsicmp(verb, interceptVerbs[i]) == 0) return true;
    }
    return false;
}

// -- Main entry point -------------------------------------------------

extern "C" __declspec(dllexport)
HRESULT ShowShellContextMenuW(
    HWND hwnd,
    const wchar_t* folderPath,
    const wchar_t** selectedPaths,
    int selectedCount,
    int x, int y,
    const wchar_t** interceptVerbs,
    int interceptCount,
    wchar_t* verbOut,
    int verbOutCch)
{
    if (verbOut && verbOutCch > 0) verbOut[0] = L'\0';

    IShellFolder* folder = nullptr;
    HRESULT hr = GetFolderShellFolder(&folder, folderPath);
    if (FAILED(hr)) return hr;

    IContextMenu* pcm = nullptr;

    if (selectedCount > 0 && selectedPaths) {
        bool isVirtual = IsVirtualShellPath(folderPath);
        PIDLIST_RELATIVE* pidls = new PIDLIST_RELATIVE[selectedCount]();
        bool ok = true;

        if (isVirtual) {
            // For virtual shell folders (Recycle Bin, etc.), we need
            // relative PIDLs for GetUIObjectOf. Get the item's absolute
            // PIDL via IShellItem2::GetIDList, then strip the folder
            // prefix to obtain the relative portion.
            PIDLIST_ABSOLUTE folderPidl = nullptr;
            SHParseDisplayName(folderPath, nullptr, &folderPidl, 0, nullptr);

            for (int i = 0; i < selectedCount && ok; i++) {
                IShellItem* item = nullptr;
                hr = SHCreateItemFromParsingName(selectedPaths[i], nullptr,
                    IID_PPV_ARGS(&item));
                if (SUCCEEDED(hr) && item) {
                    PIDLIST_ABSOLUTE absPidl = nullptr;
                    hr = SHGetIDListFromObject(item, &absPidl);
                    if (SUCCEEDED(hr) && absPidl) {
                        // Walk through folderPidl's ITEMIDLISTs and skip
                        // the same prefix from absPidl to get the relative PIDL.
                        PCUIDLIST_RELATIVE folderWalk =
                            (PCUIDLIST_RELATIVE)folderPidl;
                        PCUIDLIST_RELATIVE itemWalk =
                            (PCUIDLIST_RELATIVE)absPidl;
                        while (folderWalk->mkid.cb > 0 &&
                               itemWalk->mkid.cb > 0) {
                            folderWalk = ILGetNext(folderWalk);
                            itemWalk = ILGetNext(itemWalk);
                        }
                        // itemWalk now points to the relative PIDL
                        pidls[i] = ILClone(itemWalk);
                        CoTaskMemFree(absPidl);
                    } else {
                        ok = false;
                    }
                    item->Release();
                } else {
                    ok = false;
                }
            }

            if (folderPidl) CoTaskMemFree(folderPidl);
        } else {
            // Regular filesystem paths - extract filename and parse
            // within the parent folder.
            for (int i = 0; i < selectedCount && ok; i++) {
                const wchar_t* name = FileNameFromPath(selectedPaths[i]);
                ULONG eaten = 0;
                hr = folder->ParseDisplayName(nullptr, nullptr,
                    const_cast<LPWSTR>(name), &eaten, &pidls[i], nullptr);
                if (FAILED(hr)) ok = false;
            }
        }

        if (ok) {
            hr = folder->GetUIObjectOf(hwnd, selectedCount,
                const_cast<LPCITEMIDLIST*>(pidls),
                IID_IContextMenu, nullptr,
                reinterpret_cast<void**>(&pcm));
        } else {
            hr = E_FAIL;
        }

        for (int i = 0; i < selectedCount; i++) {
            if (pidls[i]) CoTaskMemFree(pidls[i]);
        }
        delete[] pidls;
    } else {
        hr = folder->CreateViewObject(hwnd, IID_IContextMenu,
            reinterpret_cast<void**>(&pcm));
    }

    folder->Release();
    if (FAILED(hr) || !pcm) return FAILED(hr) ? hr : E_FAIL;

    IContextMenu2* pcm2 = nullptr;
    pcm->QueryInterface(IID_IContextMenu2, reinterpret_cast<void**>(&pcm2));

    HMENU hMenu = CreatePopupMenu();
    if (!hMenu) {
        if (pcm2) pcm2->Release();
        pcm->Release();
        return E_FAIL;
    }

    UINT flags = CMF_NORMAL | CMF_EXPLORE;
    if (selectedCount == 1) flags |= CMF_CANRENAME;

    __try {
        hr = pcm->QueryContextMenu(hMenu, 0, 1, 0x7FFF, flags);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        hr = E_FAIL;
    }

    if (FAILED(hr)) {
        DestroyMenu(hMenu);
        if (pcm2) pcm2->Release();
        pcm->Release();
        return hr;
    }

    UINT cmd = 0;
    __try {
        cmd = TrackPopupMenuEx(hMenu,
            TPM_RETURNCMD | TPM_LEFTALIGN | TPM_RIGHTBUTTON,
            x, y, hwnd, nullptr);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        cmd = 0;
    }

    if (cmd > 0) {
        // Retrieve verb (Unicode)
        wchar_t verbW[256] = {};
        __try {
            pcm->GetCommandString(cmd - 1, GCS_VERBW,
                nullptr, reinterpret_cast<LPSTR>(verbW), 256);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            verbW[0] = L'\0';
        }

        // Fallback to ANSI verb
        if (!verbW[0]) {
            char verbA[256] = {};
            __try {
                pcm->GetCommandString(cmd - 1, GCS_VERBA,
                    nullptr, verbA, sizeof(verbA));
            } __except (EXCEPTION_EXECUTE_HANDLER) {
                verbA[0] = '\0';
            }
            if (verbA[0]) {
                MultiByteToWideChar(CP_ACP, 0, verbA, -1, verbW, 256);
            }
        }

        // Copy verb to output
        if (verbOut && verbOutCch > 0 && verbW[0]) {
            StringCchCopyW(verbOut, verbOutCch, verbW);
        }

        // Invoke unless intercepted
        if (verbW[0] && !IsVerbIntercepted(verbW, interceptVerbs, interceptCount)) {
            CMINVOKECOMMANDINFOEX ici = {};
            ici.cbSize = sizeof(ici);
            ici.hwnd = hwnd;
            ici.fMask = CMIC_MASK_UNICODE;
            ici.lpVerbW = verbW;
            ici.lpVerb = MAKEINTRESOURCEA(cmd - 1);

            __try {
                pcm->InvokeCommand(reinterpret_cast<LPCMINVOKECOMMANDINFO>(&ici));
            } __except (EXCEPTION_EXECUTE_HANDLER) {
                // Shell extension crashed
            }
        }
    }

    DestroyMenu(hMenu);
    if (pcm2) pcm2->Release();
    pcm->Release();
    return S_OK;
}

