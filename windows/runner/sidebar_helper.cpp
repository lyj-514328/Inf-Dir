#include "sidebar_helper.h"
#include <shlobj.h>
#include <shlwapi.h>
#include <knownfolders.h>
#include <objbase.h>
#include <vector>
#include <string>

#pragma comment(lib, "shlwapi.lib")

// KnownFolder GUIDs not defined in some SDK versions
// {679F85C8-3225-4EA2-B389-DD0AFE7B1977}
static const GUID FOLDERID_QuickAccess_Inline =
    {0x679F85C8, 0x3225, 0x4EA2, {0xB3, 0x89, 0xDD, 0x0A, 0xFE, 0x7B, 0x19, 0x77}};

static void AppendString(std::vector<unsigned char>& buf, const std::wstring& s) {
    int len = (int)s.size();
    buf.insert(buf.end(), (unsigned char*)&len, (unsigned char*)&len + sizeof(len));
    if (len > 0)
        buf.insert(buf.end(), (unsigned char*)s.data(), (unsigned char*)s.data() + len * sizeof(wchar_t));
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
    hr = SHGetKnownFolderItem(FOLDERID_QuickAccess_Inline, KF_FLAG_DEFAULT, nullptr, IID_IShellItem, (void**)&shellItem);
    if (FAILED(hr) || !shellItem) {
        if (comInit) CoUninitialize();
        return nullptr;
    }

    IShellFolder* shellFolder = nullptr;
    hr = shellItem->BindToHandler(nullptr, BHID_SFObject, IID_IShellFolder, (void**)&shellFolder);
    shellItem->Release();
    if (FAILED(hr) || !shellFolder) {
        if (comInit) CoUninitialize();
        return nullptr;
    }

    IEnumIDList* enumIdl = nullptr;
    hr = shellFolder->EnumObjects(nullptr, SHCONTF_FOLDERS | SHCONTF_NONFOLDERS | SHCONTF_INCLUDEHIDDEN, &enumIdl);
    if (FAILED(hr) || !enumIdl) {
        shellFolder->Release();
        if (comInit) CoUninitialize();
        return nullptr;
    }

    std::vector<std::wstring> names;
    std::vector<std::wstring> paths;

    PITEMID_CHILD pidl;
    while (enumIdl->Next(1, &pidl, nullptr) == S_OK) {
        STRRET strRet = {};
        if (SUCCEEDED(shellFolder->GetDisplayNameOf(pidl, SHGDN_NORMAL | SHGDN_INFOLDER, &strRet))) {
            wchar_t nameBuf[256];
            StrRetToBufW(&strRet, pidl, nameBuf, 256);
            names.push_back(nameBuf);
        } else {
            names.push_back(L"?");
        }

        if (SUCCEEDED(shellFolder->GetDisplayNameOf(pidl, SHGDN_FORPARSING, &strRet))) {
            wchar_t pathBuf[1024];
            StrRetToBufW(&strRet, pidl, pathBuf, 1024);
            paths.push_back(pathBuf);
        } else {
            paths.push_back(L"");
        }

        CoTaskMemFree(pidl);
    }

    enumIdl->Release();
    shellFolder->Release();
    if (comInit) CoUninitialize();

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
