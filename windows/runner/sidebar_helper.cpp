#include "sidebar_helper.h"
#include <shlobj.h>
#include <shlwapi.h>
#include <knownfolders.h>
#include <objbase.h>
#include <propkey.h>
#include <vector>
#include <string>

#pragma comment(lib, "shlwapi.lib")

static const GUID CLSID_FrequentPlaces =
    {0x3936E9E4, 0xD92C, 0x4EEE, {0xA8, 0x5A, 0xBC, 0x16, 0xD5, 0xEA, 0x08, 0x19}};

static void AppendString(std::vector<unsigned char>& buf, const std::wstring& s) {
    int len = (int)s.size();
    buf.insert(buf.end(), (unsigned char*)&len, (unsigned char*)&len + sizeof(len));
    if (len > 0)
        buf.insert(buf.end(), (unsigned char*)s.data(), (unsigned char*)s.data() + len * sizeof(wchar_t));
}

static std::wstring GetShellItemDisplayName(IShellItem* item, SIGDN sigdn) {
    LPWSTR pszName = nullptr;
    HRESULT hr = item->GetDisplayName(sigdn, &pszName);
    if (FAILED(hr) || !pszName) return L"";
    std::wstring result = pszName;
    CoTaskMemFree(pszName);
    return result;
}

extern "C" __declspec(dllexport)
unsigned char* GetQuickAccessItems(int* outSize) {
    if (!outSize) return nullptr;
    *outSize = 0;

    bool comInit = false;
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(hr)) return nullptr;
    comInit = (hr == S_OK);

    IShellItem* shellItem = nullptr;
    hr = SHGetKnownFolderItem(CLSID_FrequentPlaces, KF_FLAG_DEFAULT, nullptr, IID_IShellItem, (void**)&shellItem);
    if (FAILED(hr) || !shellItem) {
        wchar_t parseBuf[] = L"shell:::{3936E9E4-D92C-4EEE-A85A-BC16D5EA0819}";
        PIDLIST_ABSOLUTE pidl = nullptr;
        hr = SHParseDisplayName(parseBuf, nullptr, &pidl, 0, nullptr);
        if (SUCCEEDED(hr) && pidl) {
            hr = SHCreateShellItem(nullptr, nullptr, pidl, &shellItem);
            CoTaskMemFree(pidl);
        }
    }
    if (FAILED(hr) || !shellItem) {
        if (comInit) CoUninitialize();
        return nullptr;
    }

    IShellFolder* shellFolder = nullptr;
    hr = shellItem->BindToHandler(nullptr, BHID_SFObject, IID_IShellFolder, (void**)&shellFolder);
    shellItem->Release();

    std::vector<std::wstring> names;
    std::vector<std::wstring> paths;
    std::vector<int> pinnedFlags;

    if (SUCCEEDED(hr) && shellFolder) {
        IEnumIDList* enumIdl = nullptr;
        hr = shellFolder->EnumObjects(nullptr, SHCONTF_FOLDERS | SHCONTF_NONFOLDERS, &enumIdl);

        if (SUCCEEDED(hr) && enumIdl) {
            PITEMID_CHILD pidl;
            while (enumIdl->Next(1, &pidl, nullptr) == S_OK) {
                STRRET strRet = {};
                std::wstring nameStr;
                std::wstring pathStr;

                if (SUCCEEDED(shellFolder->GetDisplayNameOf(pidl, SHGDN_NORMAL | SHGDN_INFOLDER, &strRet))) {
                    wchar_t buf[256];
                    StrRetToBufW(&strRet, pidl, buf, 256);
                    nameStr = buf;
                }
                if (SUCCEEDED(shellFolder->GetDisplayNameOf(pidl, SHGDN_FORPARSING, &strRet))) {
                    wchar_t buf[1024];
                    StrRetToBufW(&strRet, pidl, buf, 1024);
                    pathStr = buf;
                }

                if (!pathStr.empty()) {
                    IShellItem* resolvedItem = nullptr;
                    if (SUCCEEDED(SHCreateItemWithParent(nullptr, shellFolder, pidl, IID_IShellItem, (void**)&resolvedItem))) {
                        std::wstring resolved = GetShellItemDisplayName(resolvedItem, SIGDN_DESKTOPABSOLUTEPARSING);
                        if (!resolved.empty()) pathStr = resolved;

                        int isPinned = 0;
                        IShellItem2* item2 = nullptr;
                        if (SUCCEEDED(resolvedItem->QueryInterface(IID_IShellItem2, (void**)&item2))) {
                            PROPVARIANT propVar;
                            PropVariantInit(&propVar);
                            if (SUCCEEDED(item2->GetProperty(PKEY_Home_IsPinned, &propVar))) {
                                if (propVar.vt == VT_BOOL) {
                                    isPinned = (propVar.boolVal == VARIANT_TRUE) ? 1 : 0;
                                }
                                PropVariantClear(&propVar);
                            }
                            item2->Release();
                        }
                        pinnedFlags.push_back(isPinned);
                        resolvedItem->Release();
                    } else {
                        pinnedFlags.push_back(0);
                    }
                }

                if (!nameStr.empty() && !pathStr.empty()) {
                    names.push_back(nameStr);
                    paths.push_back(pathStr);
                }
                CoTaskMemFree(pidl);
            }
            enumIdl->Release();
        }
        shellFolder->Release();
    }

    if (comInit) CoUninitialize();

    // Buffer layout:
    //   [count: int32]
    //   for each: [nameLen] [name] [pathLen] [path] [isPinned: int32]
    std::vector<unsigned char> buf;
    int count = (int)names.size();
    buf.insert(buf.end(), (unsigned char*)&count, (unsigned char*)&count + sizeof(count));

    for (int i = 0; i < count; i++) {
        AppendString(buf, names[i]);
        AppendString(buf, paths[i]);
        buf.insert(buf.end(), (unsigned char*)&pinnedFlags[i], (unsigned char*)&pinnedFlags[i] + sizeof(int));
    }

    SIZE_T totalSz = buf.size();
    unsigned char* result = (unsigned char*)CoTaskMemAlloc(totalSz);
    if (!result) return nullptr;
    memcpy(result, buf.data(), totalSz);
    *outSize = (int)totalSz;
    return result;
}

extern "C" __declspec(dllexport)
unsigned char* GetDriveInfo(const wchar_t* driveRoot, int* outSize) {
    if (!driveRoot || !outSize) return nullptr;
    *outSize = 0;

    wchar_t volName[256] = {};
    wchar_t fsName[256] = {};
    BOOL ok = GetVolumeInformationW(
        driveRoot,
        volName, 256,
        nullptr, nullptr, nullptr,
        fsName, 256
    );

    std::wstring friendlyName;
    std::wstring fsType;

    if (ok) {
        friendlyName = volName;
        fsType = fsName;
    }

    std::vector<unsigned char> buf;
    AppendString(buf, friendlyName);
    AppendString(buf, fsType);

    SIZE_T totalSz = buf.size();
    unsigned char* result = (unsigned char*)CoTaskMemAlloc(totalSz);
    if (!result) return nullptr;
    memcpy(result, buf.data(), totalSz);
    *outSize = (int)totalSz;
    return result;
}

extern "C" __declspec(dllexport)
void FreeSidebarItems(unsigned char* ptr) {
    if (ptr) CoTaskMemFree(ptr);
}

extern "C" __declspec(dllexport)
int ProbeDirectoryHasChildren(const wchar_t* path) {
    if (!path || !*path) return 0;

    std::wstring pattern = path;
    if (!pattern.empty() && pattern.back() != L'\\')
        pattern += L'\\';
    pattern += L'*';

    WIN32_FIND_DATAW ffd;
    HANDLE hFind = FindFirstFileW(pattern.c_str(), &ffd);
    if (hFind == INVALID_HANDLE_VALUE)
        return 0;

    int hasDir = 0;
    do {
        if (wcscmp(ffd.cFileName, L".") == 0 || wcscmp(ffd.cFileName, L"..") == 0)
            continue;
        if (ffd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            hasDir = 1;
            break;
        }
    } while (FindNextFileW(hFind, &ffd) != 0);

    FindClose(hFind);
    return hasDir;
}
