#include "directory_listing.h"
#include <shlobj.h>
#include <shlwapi.h>
#include <knownfolders.h>
#include <propkey.h>
#include <propvarutil.h>
#include <vector>
#include <string>

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "propsys.lib")

// -- Helper: append primitives to byte buffer --------------------------

static void AppendString(std::vector<unsigned char>& buf, const std::wstring& s) {
    int32_t len = (int32_t)s.size();
    buf.insert(buf.end(), (unsigned char*)&len, (unsigned char*)&len + sizeof(len));
    if (len > 0) {
        buf.insert(buf.end(),
            (unsigned char*)s.data(),
            (unsigned char*)s.data() + len * sizeof(wchar_t));
    }
}

static void AppendInt64(std::vector<unsigned char>& buf, int64_t val) {
    buf.insert(buf.end(), (unsigned char*)&val, (unsigned char*)&val + sizeof(val));
}

static void AppendInt32(std::vector<unsigned char>& buf, int32_t val) {
    buf.insert(buf.end(), (unsigned char*)&val, (unsigned char*)&val + sizeof(val));
}

// -- Helper: format a FILETIME as "YYYY/MM/DD HH:MM:SS" ----------------

static std::wstring FormatFileTime(const FILETIME& ft) {
    SYSTEMTIME st = {};
    FileTimeToSystemTime(&ft, &st);
    wchar_t buf[64];
    swprintf_s(buf, L"%04d/%02d/%02d %02d:%02d:%02d",
        st.wYear, st.wMonth, st.wDay,
        st.wHour, st.wMinute, st.wSecond);
    return buf;
}

// -- Helper: resolve a property key by canonical name ------------------

static bool GetPropertyKeyByName(const wchar_t* name, PROPERTYKEY& pkey) {
    return SUCCEEDED(PSGetPropertyKeyFromName(name, &pkey));
}

// -- Helper: read a string property from IShellItem2 -------------------

static std::wstring GetShellItemString(IShellItem2* item2, const PROPERTYKEY& pkey) {
    PWSTR value = nullptr;
    if (SUCCEEDED(item2->GetString(pkey, &value)) && value) {
        std::wstring result = value;
        CoTaskMemFree(value);
        return result;
    }
    return L"";
}

// -- Path detection helpers --------------------------------------------

static bool IsVirtualShellPath(const wchar_t* path) {
    return (wcsstr(path, L"shell:") != nullptr ||
            wcsstr(path, L"::{") != nullptr);
}

static bool IsRecycleBinPath(const wchar_t* path) {
    return (wcsstr(path, L"RecycleBinFolder") != nullptr ||
            wcsstr(path, L"645FF040") != nullptr);
}

static bool IsMyComputerPath(const wchar_t* path) {
    return (wcsstr(path, L"MyComputerFolder") != nullptr ||
            wcsstr(path, L"20D04FE0") != nullptr);
}

// -- Enumerate Shell virtual folder via BHID_EnumItems -----------------

// Returns false if the path is not a virtual folder we handle.
static bool EnumerateShellFolder(const wchar_t* path,
    std::vector<unsigned char>& buf, int32_t& count,
    bool comInitialized)
{
    if (!IsVirtualShellPath(path))
        return false;

    // Resolve IShellItem for the folder
    IShellItem* folderItem = nullptr;
    HRESULT hr = SHCreateItemFromParsingName(path, nullptr,
        IID_PPV_ARGS(&folderItem));
    if (FAILED(hr) || !folderItem)
        return false;

    IEnumShellItems* enumItems = nullptr;
    hr = folderItem->BindToHandler(nullptr, BHID_EnumItems,
        IID_PPV_ARGS(&enumItems));
    folderItem->Release();

    if (FAILED(hr) || !enumItems)
        return true; // virtual folder but empty - still "handled"

    // Resolve property keys for Recycle Bin fields
    PROPERTYKEY pkeyDeletedFrom = {};
    PROPERTYKEY pkeyDateDeleted = {};
    PROPERTYKEY pkeySize = {};
    PROPERTYKEY pkeyFileAttributes = {};
    GetPropertyKeyByName(L"System.Recycle.DeletedFrom", pkeyDeletedFrom);
    GetPropertyKeyByName(L"System.Recycle.DateDeleted", pkeyDateDeleted);
    GetPropertyKeyByName(L"System.Size", pkeySize);
    GetPropertyKeyByName(L"System.FileAttributes", pkeyFileAttributes);
    PROPERTYKEY emptyPkey = {};

    bool isRecycleBinItem = IsRecycleBinPath(path);

    IShellItem* childItems[32];
    while (true) {
        ULONG fetched = 0;
        hr = enumItems->Next(32, childItems, &fetched);
        if (FAILED(hr) || fetched == 0) break;

        for (ULONG i = 0; i < fetched; i++) {
            IShellItem* child = childItems[i];

            // Display name
            LPWSTR psz = nullptr;
            std::wstring name;
            if (SUCCEEDED(child->GetDisplayName(SIGDN_NORMALDISPLAY, &psz)) && psz) {
                name = psz;
                CoTaskMemFree(psz);
                psz = nullptr;
            }

            // Path / parsing name
            std::wstring filePath;
            if (SUCCEEDED(child->GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, &psz)) && psz) {
                filePath = psz;
                CoTaskMemFree(psz);
                psz = nullptr;
            }
            if (filePath.empty()) filePath = name;

            int32_t isDirectory = 0;
            int64_t sizeBytes = 0;
            std::wstring modifiedDate;
            std::wstring originalPath;
            std::wstring recycleDate;
            std::wstring parsingName;

            IShellItem2* item2 = nullptr;
            if (SUCCEEDED(child->QueryInterface(IID_PPV_ARGS(&item2)))) {
                // Size
                if (memcmp(&pkeySize, &emptyPkey, sizeof(PROPERTYKEY)) != 0) {
                    PROPVARIANT pv;
                    PropVariantInit(&pv);
                    if (SUCCEEDED(item2->GetProperty(pkeySize, &pv))) {
                        if (pv.vt == VT_UI8 || pv.vt == VT_UI4)
                            sizeBytes = (int64_t)pv.uhVal.QuadPart;
                        else if (pv.vt == VT_I8 || pv.vt == VT_I4)
                            sizeBytes = (int64_t)pv.hVal.QuadPart;
                        PropVariantClear(&pv);
                    }
                }

                // Attributes - isDirectory
                if (memcmp(&pkeyFileAttributes, &emptyPkey, sizeof(PROPERTYKEY)) != 0) {
                    PROPVARIANT pv;
                    PropVariantInit(&pv);
                    if (SUCCEEDED(item2->GetProperty(pkeyFileAttributes, &pv))) {
                        if (pv.vt == VT_UI4)
                            isDirectory = (pv.ulVal & FILE_ATTRIBUTE_DIRECTORY) ? 1 : 0;
                        PropVariantClear(&pv);
                    }
                }

                // Recycle-bin-specific fields
                if (isRecycleBinItem) {
                    if (memcmp(&pkeyDeletedFrom, &emptyPkey, sizeof(PROPERTYKEY)) != 0)
                        originalPath = GetShellItemString(item2, pkeyDeletedFrom);

                    if (memcmp(&pkeyDateDeleted, &emptyPkey, sizeof(PROPERTYKEY)) != 0) {
                        FILETIME ft = {};
                        if (SUCCEEDED(item2->GetFileTime(pkeyDateDeleted, &ft)))
                            recycleDate = FormatFileTime(ft);
                    }

                    parsingName = filePath;
                }

                // Modified date
                FILETIME ft = {};
                if (SUCCEEDED(item2->GetFileTime(PKEY_DateModified, &ft)))
                    modifiedDate = FormatFileTime(ft);

                item2->Release();
            }

            // Write item to buffer
            AppendString(buf, name);
            AppendString(buf, filePath);
            AppendInt32(buf, isDirectory);
            // For shell folders, if it's a directory we optimistically
            // mark hasChildren; the actual check is expensive.
            AppendInt32(buf, isDirectory);
            AppendInt64(buf, sizeBytes);
            AppendString(buf, modifiedDate);
            AppendInt32(buf, isRecycleBinItem ? 1 : 0);
            AppendString(buf, originalPath);
            AppendString(buf, recycleDate);
            AppendString(buf, parsingName);
            count++;

            child->Release();
        }
    }
    enumItems->Release();
    return true;
}

// -- Enumerate regular filesystem directory via FindFirstFile ----------

static void EnumerateFilesystem(const wchar_t* path,
    std::vector<unsigned char>& buf, int32_t& count)
{
    // Build search pattern: path\*
    std::wstring searchPattern = path;
    if (!searchPattern.empty() && searchPattern.back() != L'\\')
        searchPattern += L'\\';
    searchPattern += L'*';

    WIN32_FIND_DATAW ffd;
    HANDLE hFind = FindFirstFileW(searchPattern.c_str(), &ffd);
    if (hFind == INVALID_HANDLE_VALUE)
        return;

    do {
        // Skip . and ..
        if (wcscmp(ffd.cFileName, L".") == 0 || wcscmp(ffd.cFileName, L"..") == 0)
            continue;

        std::wstring name = ffd.cFileName;
        std::wstring fullPath = path;
        if (!fullPath.empty() && fullPath.back() != L'\\')
            fullPath += L'\\';
        fullPath += name;

        int32_t isDirectory = (ffd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? 1 : 0;
        int64_t sizeBytes = ((int64_t)ffd.nFileSizeHigh << 32) | ffd.nFileSizeLow;
        std::wstring modifiedDate = FormatFileTime(ffd.ftLastWriteTime);

        int32_t hasChildren = 0;
        if (isDirectory) {
            hasChildren = PathIsDirectoryEmptyW(fullPath.c_str()) ? 0 : 1;
        }

        AppendString(buf, name);
        AppendString(buf, fullPath);
        AppendInt32(buf, isDirectory);
        AppendInt32(buf, hasChildren);
        AppendInt64(buf, sizeBytes);
        AppendString(buf, modifiedDate);
        AppendInt32(buf, 0); // not recycle bin
        AppendString(buf, L""); // originalPath
        AppendString(buf, L""); // recycleDate
        AppendString(buf, L""); // parsingName
        count++;

    } while (FindNextFileW(hFind, &ffd) != 0);

    FindClose(hFind);
}

// -- Enumerate drives (for "My Computer") ------------------------------

static void EnumerateDrives(std::vector<unsigned char>& buf, int32_t& count) {
    for (int i = 0; i < 26; i++) {
        wchar_t root[] = { (wchar_t)(L'A' + i), L':', L'\\', L'\0' };
        UINT type = GetDriveTypeW(root);
        if (type == DRIVE_NO_ROOT_DIR || type == DRIVE_UNKNOWN)
            continue; // skip empty drives

        // Get volume name for a friendly label
        wchar_t volName[256] = {};
        BOOL ok = GetVolumeInformationW(root, volName, 256, nullptr, nullptr, nullptr, nullptr, 0);
        std::wstring label = ok ? volName : L"";
        (void)ok; // suppress unused-variable warning
        wchar_t letter[4] = { root[0], L':', L'\0' };
        if (!label.empty())
            label += L" (" + std::wstring(letter) + L")";
        else
            label = std::wstring(letter);

        std::wstring modifiedDate;
        // No meaningful date for drives, use current time
        SYSTEMTIME st;
        GetLocalTime(&st);
        wchar_t dateBuf[64];
        swprintf_s(dateBuf, L"%04d/%02d/%02d %02d:%02d:%02d",
            st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
        modifiedDate = dateBuf;

        // Check whether the drive has any top-level items.
        int32_t hasChildren = 0;
        {
            std::wstring probe = std::wstring(root) + L"*";
            WIN32_FIND_DATAW pfd;
            HANDLE hProbe = FindFirstFileW(probe.c_str(), &pfd);
            if (hProbe != INVALID_HANDLE_VALUE) {
                do {
                    if (wcscmp(pfd.cFileName, L".") != 0 &&
                        wcscmp(pfd.cFileName, L"..") != 0) {
                        hasChildren = 1;
                        break;
                    }
                } while (FindNextFileW(hProbe, &pfd) != 0);
                FindClose(hProbe);
            }
        }

        AppendString(buf, label);       // name
        AppendString(buf, root);        // path
        AppendInt32(buf, 1);            // isDirectory
        AppendInt32(buf, hasChildren);  // hasChildren
        AppendInt64(buf, 0);            // size
        AppendString(buf, modifiedDate); // modifiedDate
        AppendInt32(buf, 0);            // isRecycleBinItem
        AppendString(buf, L"");         // originalPath
        AppendString(buf, L"");         // recycleDate
        AppendString(buf, L"");         // parsingName
        count++;
    }
}

// -- Main exported function --------------------------------------------

extern "C" __declspec(dllexport)
unsigned char* ListDirectoryEntries(const wchar_t* path, int* outSize) {
    if (!path || !outSize) return nullptr;
    *outSize = 0;

    bool comInit = false;
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(hr)) return nullptr;
    comInit = (hr == S_OK);

    std::vector<unsigned char> buf;
    int32_t count = 0;
    size_t countPos = buf.size();
    AppendInt32(buf, 0); // placeholder

    // Determine path type and dispatch
    if (IsMyComputerPath(path)) {
        EnumerateDrives(buf, count);
    } else if (IsRecycleBinPath(path)) {
        EnumerateShellFolder(path, buf, count, comInit);
    } else if (IsVirtualShellPath(path)) {
        EnumerateShellFolder(path, buf, count, comInit);
    } else {
        EnumerateFilesystem(path, buf, count);
    }

    // Sort: directories first, then by name
    // We'll sort on the Dart side for simplicity

    memcpy(buf.data() + countPos, &count, sizeof(count));

    if (comInit) CoUninitialize();

    SIZE_T totalSz = buf.size();
    unsigned char* result = (unsigned char*)CoTaskMemAlloc(totalSz);
    if (!result) return nullptr;
    memcpy(result, buf.data(), totalSz);
    *outSize = (int)totalSz;
    return result;
}

extern "C" __declspec(dllexport)
void FreeDirectoryEntries(unsigned char* ptr) {
    if (ptr) CoTaskMemFree(ptr);
}

extern "C" __declspec(dllexport)
wchar_t* GetShellDisplayName(const wchar_t* path) {
    if (!path) return nullptr;

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    bool comInit = (hr == S_OK);

    IShellItem* item = nullptr;
    hr = SHCreateItemFromParsingName(path, nullptr, IID_PPV_ARGS(&item));
    if (FAILED(hr) || !item) {
        if (comInit) CoUninitialize();
        return nullptr;
    }

    LPWSTR displayName = nullptr;
    hr = item->GetDisplayName(SIGDN_NORMALDISPLAY, &displayName);
    item->Release();

    if (comInit) CoUninitialize();

    if (FAILED(hr) || !displayName) return nullptr;

    // displayName is already CoTaskMemAlloc'd - return directly
    return displayName;
}

