#include "sidebar_helper.h"
#include <shlobj.h>
#include <shlwapi.h>
#include <knownfolders.h>
#include <objbase.h>
#include <propkey.h>
#include <sddl.h>
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

// Reads a REG_SZ / REG_EXPAND_SZ string value.
static std::wstring ReadRegStringValue(HKEY key, const wchar_t* valueName) {
    wchar_t buf[1024] = {};
    DWORD size = sizeof(buf);
    if (RegGetValueW(key, nullptr, valueName, RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ,
                     nullptr, buf, &size) != ERROR_SUCCESS)
        return L"";
    return std::wstring(buf);
}

static std::wstring ExpandIfNecessary(const std::wstring& s) {
    if (s.find(L'%') == std::wstring::npos) return s;
    DWORD needed = ExpandEnvironmentStringsW(s.c_str(), nullptr, 0);
    if (needed == 0) return s;
    std::wstring out(needed, L'\0');
    ExpandEnvironmentStringsW(s.c_str(), out.data(), needed);
    out.resize(wcslen(out.c_str()));
    return out;
}

static std::wstring GetCurrentUserSidString() {
    std::wstring result;
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
        return result;

    DWORD size = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &size);
    if (size > 0) {
        std::vector<unsigned char> buf(size);
        if (GetTokenInformation(token, TokenUser, buf.data(), size, &size)) {
            TOKEN_USER* tokenUser = reinterpret_cast<TOKEN_USER*>(buf.data());
            LPWSTR sidStr = nullptr;
            if (ConvertSidToStringSidW(tokenUser->User.Sid, &sidStr)) {
                result = sidStr;
                LocalFree(sidStr);
            }
        }
    }
    CloseHandle(token);
    return result;
}

// DisplayNameResource may be an indirect string ("@module,-resId"); resolve it.
static std::wstring ResolveDisplayName(const std::wstring& raw, const std::wstring& fallback) {
    std::wstring name = ExpandIfNecessary(raw);
    if (!name.empty() && name[0] == L'@') {
        wchar_t resolved[512];
        if (SUCCEEDED(SHLoadIndirectString(name.c_str(), resolved, 512, nullptr)))
            name = resolved;
        else
            name.clear();
    }
    return name.empty() ? fallback : name;
}

extern "C" __declspec(dllexport)
unsigned char* GetCloudDriveRoots(int* outSize) {
    if (!outSize) return nullptr;
    *outSize = 0;

    std::vector<std::wstring> names;
    std::vector<std::wstring> paths;

    // Official discovery: enumerate the CfAPI sync roots that Windows itself
    // registers under SyncRootManager. Any compliant cloud client (OneDrive,
    // Dropbox, Baidu Netdisk, ...) shows up here without vendor-specific code.
    const std::wstring userSid = GetCurrentUserSidString();

    HKEY managerKey = nullptr;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE,
                      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\SyncRootManager",
                      0, KEY_READ, &managerKey) == ERROR_SUCCESS) {
        for (DWORD i = 0;; i++) {
            wchar_t syncRootId[1024];
            DWORD idLen = 1024;
            if (RegEnumKeyExW(managerKey, i, syncRootId, &idLen,
                              nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS)
                break;

            HKEY syncRootKey = nullptr;
            if (RegOpenKeyExW(managerKey, syncRootId, 0, KEY_READ, &syncRootKey) != ERROR_SUCCESS)
                continue;

            // Sync folder: UserSyncRoots value named after the current user's SID.
            std::wstring syncFolder;
            HKEY userSyncRoots = nullptr;
            if (RegOpenKeyExW(syncRootKey, L"UserSyncRoots", 0, KEY_READ, &userSyncRoots) == ERROR_SUCCESS) {
                if (!userSid.empty())
                    syncFolder = ReadRegStringValue(userSyncRoots, userSid.c_str());
                if (syncFolder.empty()) {
                    // Provider not keyed by SID: fall back to the first value.
                    wchar_t valueName[512];
                    DWORD valueNameLen = 512;
                    if (RegEnumValueW(userSyncRoots, 0, valueName, &valueNameLen,
                                      nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS)
                        syncFolder = ReadRegStringValue(userSyncRoots, valueName);
                }
                RegCloseKey(userSyncRoots);
            }

            // Display name: DisplayNameResource, falling back to the provider
            // segment of the sync root id (text before the first '!').
            std::wstring idStr(syncRootId);
            std::wstring fallbackName = idStr.substr(0, idStr.find(L'!'));
            std::wstring displayName = ResolveDisplayName(
                ReadRegStringValue(syncRootKey, L"DisplayNameResource"), fallbackName);
            RegCloseKey(syncRootKey);

            syncFolder = ExpandIfNecessary(syncFolder);
            if (syncFolder.empty() || !PathIsDirectoryW(syncFolder.c_str()))
                continue;

            bool duplicate = false;
            for (const auto& existing : paths) {
                if (_wcsicmp(existing.c_str(), syncFolder.c_str()) == 0) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) continue;

            names.push_back(displayName);
            paths.push_back(syncFolder);
        }
        RegCloseKey(managerKey);
    }

    // Buffer layout (same shape as GetQuickAccessItems, without pinned flag):
    //   [count: int32]
    //   for each: [nameLen] [name] [pathLen] [path]
    std::vector<unsigned char> buf;
    int count = (int)names.size();
    buf.insert(buf.end(), (unsigned char*)&count, (unsigned char*)&count + sizeof(count));
    for (int i = 0; i < count; i++) {
        AppendString(buf, names[i]);
        AppendString(buf, paths[i]);
    }

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
    return PathIsDirectoryEmptyW(path) ? 0 : 1;
}
