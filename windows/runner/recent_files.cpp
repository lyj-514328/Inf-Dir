#include "recent_files.h"
#include <shlobj.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <vector>
#include <string>
#include <unordered_set>
#include <cwctype>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shlwapi.lib")

static void AppendString(std::vector<unsigned char>& buf, const std::wstring& s) {
    int32_t len = (int32_t)s.size();
    buf.insert(buf.end(), (unsigned char*)&len, (unsigned char*)&len + sizeof(len));
    if (len > 0) {
        buf.insert(buf.end(),
            (unsigned char*)s.data(),
            (unsigned char*)s.data() + len * sizeof(wchar_t));
    }
}

static void AppendInt32(std::vector<unsigned char>& buf, int32_t val) {
    buf.insert(buf.end(), (unsigned char*)&val, (unsigned char*)&val + sizeof(val));
}

static std::wstring FormatFileTime(const FILETIME& ft) {
    SYSTEMTIME st = {};
    FileTimeToSystemTime(&ft, &st);
    wchar_t buf[64];
    swprintf_s(buf, L"%04d/%02d/%02d %02d:%02d:%02d",
        st.wYear, st.wMonth, st.wDay,
        st.wHour, st.wMinute, st.wSecond);
    return buf;
}

static std::wstring StrRetToString(IShellFolder* folder, PCUITEMID_CHILD pidl,
    const STRRET& strret) {
    switch (strret.uType) {
    case STRRET_WSTR:
        if (strret.pOleStr) {
            std::wstring result = strret.pOleStr;
            CoTaskMemFree(strret.pOleStr);
            return result;
        }
        return L"";
    case STRRET_OFFSET:
        return (const wchar_t*)(((const unsigned char*)pidl) + strret.uOffset);
    case STRRET_CSTR: {
        int len = MultiByteToWideChar(CP_ACP, 0, strret.cStr, -1, nullptr, 0);
        if (len <= 0) return L"";
        std::wstring result((size_t)len - 1, L'\0');
        MultiByteToWideChar(CP_ACP, 0, strret.cStr, -1, &result[0], len);
        return result;
    }
    default:
        return L"";
    }
}

static std::wstring GetChildParsingName(IShellFolder* folder, PCUITEMID_CHILD pidl) {
    STRRET strret = {};
    if (FAILED(folder->GetDisplayNameOf(pidl, SHGDN_FORPARSING, &strret)))
        return L"";
    return StrRetToString(folder, pidl, strret);
}

static bool ResolveShortcutTarget(const std::wstring& lnkPath, std::wstring& target) {
    IShellLinkW* link = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link));
    if (FAILED(hr) || !link)
        return false;

    bool ok = false;
    IPersistFile* persistFile = nullptr;
    if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&persistFile)))) {
        if (SUCCEEDED(persistFile->Load(lnkPath.c_str(), STGM_READ))) {
            wchar_t pathBuf[MAX_PATH];
            WIN32_FIND_DATAW ffd = {};
            if (SUCCEEDED(link->GetPath(pathBuf, MAX_PATH, &ffd, SLGP_RAWPATH)) &&
                pathBuf[0] != L'\0') {
                target = pathBuf;
                ok = true;
            }
        }
        persistFile->Release();
    }
    link->Release();

    if (ok && target.find(L'%') != std::wstring::npos) {
        wchar_t expanded[MAX_PATH];
        DWORD len = ExpandEnvironmentStringsW(target.c_str(), expanded, MAX_PATH);
        if (len > 0 && len < MAX_PATH)
            target = expanded;
    }
    return ok;
}

extern "C" __declspec(dllexport)
unsigned char* GetRecentFiles(int limit, int* outSize) {
    if (!outSize) return nullptr;
    *outSize = 0;

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(hr)) return nullptr;
    bool comInit = (hr == S_OK);

    std::vector<unsigned char> buf;
    int32_t count = 0;
    AppendInt32(buf, 0); // count placeholder

    do {
        IShellFolder* desktop = nullptr;
        if (FAILED(SHGetDesktopFolder(&desktop)) || !desktop)
            break;

        LPITEMIDLIST pidlRecent = nullptr;
        ULONG eaten = 0;
        DWORD attrs = 0;
        hr = desktop->ParseDisplayName(nullptr, nullptr,
            const_cast<LPWSTR>(L"shell:Recent"), &eaten, &pidlRecent, &attrs);
        if (FAILED(hr) || !pidlRecent) {
            desktop->Release();
            break;
        }

        IShellFolder* recentFolder = nullptr;
        hr = desktop->BindToObject(pidlRecent, nullptr, IID_PPV_ARGS(&recentFolder));
        CoTaskMemFree(pidlRecent);
        desktop->Release();
        if (FAILED(hr) || !recentFolder)
            break;

        IEnumIDList* enumId = nullptr;
        hr = recentFolder->EnumObjects(nullptr,
            SHCONTF_FOLDERS | SHCONTF_NONFOLDERS, &enumId);
        if (FAILED(hr) || !enumId) {
            recentFolder->Release();
            break;
        }

        std::unordered_set<std::wstring> seen;
        PITEMID_CHILD child = nullptr;
        ULONG fetched = 0;
        while (enumId->Next(1, &child, &fetched) == S_OK && fetched == 1) {
            std::wstring lnkPath = GetChildParsingName(recentFolder, child);
            CoTaskMemFree(child);
            child = nullptr;

            if (lnkPath.empty())
                continue;
            if (_wcsicmp(PathFindExtensionW(lnkPath.c_str()), L".lnk") != 0)
                continue;

            std::wstring target;
            if (!ResolveShortcutTarget(lnkPath, target))
                continue;

            WIN32_FILE_ATTRIBUTE_DATA attr = {};
            if (!GetFileAttributesExW(target.c_str(), GetFileExInfoStandard, &attr))
                continue; // dead link
            if (attr.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                continue; // files only; archives are regular files

            std::wstring key = target;
            for (wchar_t& ch : key)
                ch = (wchar_t)towlower(ch);
            if (!seen.insert(key).second)
                continue;

            AppendString(buf, target);
            AppendString(buf, FormatFileTime(attr.ftLastWriteTime));
            count++;
            if (limit > 0 && count >= limit)
                break;
        }

        enumId->Release();
        recentFolder->Release();
    } while (false);

    if (comInit) CoUninitialize();

    memcpy(buf.data(), &count, sizeof(count));

    SIZE_T totalSz = buf.size();
    unsigned char* result = (unsigned char*)CoTaskMemAlloc(totalSz);
    if (!result) return nullptr;
    memcpy(result, buf.data(), totalSz);
    *outSize = (int)totalSz;
    return result;
}

extern "C" __declspec(dllexport)
void FreeRecentFiles(unsigned char* ptr) {
    if (ptr) CoTaskMemFree(ptr);
}
