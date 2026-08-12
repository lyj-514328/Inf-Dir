#include "shell_new.h"
#include <shlobj.h>
#include <shlwapi.h>
#include <commoncontrols.h>
#include <gdiplus.h>
#include <vector>
#include <string>
#include <algorithm>
#include <cstring>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "gdiplus.lib")

namespace {

void AppendInt32(std::vector<unsigned char>& buf, int32_t val) {
    buf.insert(buf.end(), (unsigned char*)&val, (unsigned char*)&val + sizeof(val));
}

void AppendWStr(std::vector<unsigned char>& buf, const std::wstring& s) {
    int32_t len = (int32_t)s.size();
    AppendInt32(buf, len);
    if (len > 0) {
        buf.insert(buf.end(),
            (unsigned char*)s.data(),
            (unsigned char*)s.data() + len * sizeof(wchar_t));
    }
}

void AppendBytes(std::vector<unsigned char>& buf, const unsigned char* data, int32_t len) {
    AppendInt32(buf, len);
    if (len > 0 && data)
        buf.insert(buf.end(), data, data + len);
}

std::wstring RegGetString(HKEY root, const std::wstring& subKey, const wchar_t* valueName) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(root, subKey.c_str(), 0, KEY_READ, &key) != ERROR_SUCCESS)
        return L"";
    std::wstring result;
    DWORD size = 0;
    LONG rc = RegQueryValueExW(key, valueName, nullptr, nullptr, nullptr, &size);
    if (rc == ERROR_SUCCESS && size > 0) {
        result.resize(size / sizeof(wchar_t));
        rc = RegQueryValueExW(key, valueName, nullptr, nullptr,
            (LPBYTE)&result[0], &size);
        if (rc != ERROR_SUCCESS) {
            result.clear();
        } else {
            result.resize(wcsnlen(result.c_str(), result.size()));
        }
    }
    RegCloseKey(key);
    return result;
}

// Files uses StorageFile.DisplayType for a sample file. SHGetFileInfo returns
// the same localized Windows file-type label without creating a temp file.
std::wstring ResolveDisplayName(const std::wstring& extension) {
    SHFILEINFOW sfi = {};
    // Leaf must carry the extension ("x.txt"); ".txt\x" parses as file "x"
    // with no extension and fails to resolve the type.
    if (SHGetFileInfoW((L"x" + extension).c_str(), FILE_ATTRIBUTE_NORMAL,
            &sfi, sizeof(sfi), SHGFI_TYPENAME | SHGFI_USEFILEATTRIBUTES) &&
        sfi.szTypeName[0] != L'\0') {
        return sfi.szTypeName;
    }
    return L"file " + extension;
}

// FileName may be a bare filename kept in the system shellnew folder.
std::wstring ResolveTemplatePath(const std::wstring& fileName) {
    if (fileName.empty())
        return L"";
    if (!PathIsRelativeW(fileName.c_str()))
        return fileName;

    wchar_t dir[MAX_PATH] = {};
    GetWindowsDirectoryW(dir, MAX_PATH);
    std::wstring candidate = std::wstring(dir) + L"\\shellnew\\" + fileName;
    if (GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES)
        return candidate;

    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, dir))) {
        candidate = std::wstring(dir) + L"\\Microsoft\\Windows\\Templates\\" + fileName;
        if (GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES)
            return candidate;
    }
    return L"";
}

std::vector<unsigned char> ReadFileBytes(const std::wstring& path) {
    std::vector<unsigned char> result;
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return result;
    DWORD high = 0;
    DWORD low = GetFileSize(file, &high);
    if (low > 0 && high == 0) {
        result.resize(low);
        DWORD read = 0;
        if (!ReadFile(file, result.data(), low, &read, nullptr) || read != low)
            result.clear();
    }
    CloseHandle(file);
    return result;
}

// -- GDI+ lazy init + PNG encoder (mirrors file_icon.cpp) ---------------

bool EnsureGdiplus(CLSID& pngClsid) {
    static bool ready = false;
    static ULONG_PTR token = 0;
    static CLSID clsid = {};
    pngClsid = clsid;
    if (ready) return true;

    Gdiplus::GdiplusStartupInput input;
    if (Gdiplus::GdiplusStartup(&token, &input, nullptr) != Gdiplus::Ok)
        return false;

    UINT num = 0, size = 0;
    if (Gdiplus::GetImageEncodersSize(&num, &size) != Gdiplus::Ok || size == 0)
        return false;
    auto* codecs = (Gdiplus::ImageCodecInfo*)malloc(size);
    if (!codecs) return false;
    if (Gdiplus::GetImageEncoders(num, size, codecs) == Gdiplus::Ok) {
        for (UINT i = 0; i < num; i++) {
            if (wcscmp(codecs[i].MimeType, L"image/png") == 0) {
                clsid = codecs[i].Clsid;
                ready = true;
                break;
            }
        }
    }
    free(codecs);
    pngClsid = clsid;
    return ready;
}

// HICON -> PNG. DrawIconEx composites the icon onto a transparent 32bpp
// DIB, preserving per-pixel alpha. (Gdiplus::Bitmap::FromHICON drops the
// alpha mask and yields a white-box / dark-border artifact.)
std::vector<unsigned char> IconToPng(HICON hIcon) {
    std::vector<unsigned char> result;
    CLSID pngClsid = {};
    if (!hIcon || !EnsureGdiplus(pngClsid))
        return result;

    ICONINFO ii = {};
    if (!GetIconInfo(hIcon, &ii))
        return result;
    BITMAP bm = {};
    int w = 0, h = 0;
    if (ii.hbmColor) {
        if (GetObject(ii.hbmColor, sizeof(bm), &bm)) { w = bm.bmWidth; h = bm.bmHeight; }
    } else if (ii.hbmMask) {
        if (GetObject(ii.hbmMask, sizeof(bm), &bm)) { w = bm.bmWidth; h = bm.bmHeight / 2; }
    }
    if (ii.hbmColor) DeleteObject(ii.hbmColor);
    if (ii.hbmMask) DeleteObject(ii.hbmMask);
    if (w <= 0 || h <= 0)
        return result;

    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = w;
    bmi.bmiHeader.biHeight = -h; // top-down
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    void* bits = nullptr;
    HDC screenDC = GetDC(nullptr);
    HBITMAP hBmp = CreateDIBSection(screenDC, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
    ReleaseDC(nullptr, screenDC);
    if (!hBmp || !bits) {
        if (hBmp) DeleteObject(hBmp);
        return result;
    }
    memset(bits, 0, (size_t)w * h * 4);

    HDC memDC = CreateCompatibleDC(nullptr);
    HGDIOBJ old = SelectObject(memDC, hBmp);
    DrawIconEx(memDC, 0, 0, hIcon, w, h, 0, nullptr, DI_NORMAL);
    SelectObject(memDC, old);
    DeleteDC(memDC);

    Gdiplus::Bitmap bmp(w, h, w * 4, PixelFormat32bppARGB, (BYTE*)bits);
    IStream* stm = nullptr;
    if (CreateStreamOnHGlobal(nullptr, TRUE, &stm) == S_OK) {
        if (bmp.Save(stm, &pngClsid, nullptr) == Gdiplus::Ok) {
            STATSTG stat = {};
            if (stm->Stat(&stat, STATFLAG_NONAME) == S_OK &&
                stat.cbSize.QuadPart > 0 && stat.cbSize.QuadPart < 1024 * 1024) {
                result.resize((size_t)stat.cbSize.QuadPart);
                LARGE_INTEGER zero = {};
                stm->Seek(zero, STREAM_SEEK_SET, nullptr);
                ULONG read = 0;
                stm->Read(result.data(), (ULONG)result.size(), &read);
                result.resize(read);
            }
        }
        stm->Release();
    }
    DeleteObject(hBmp);
    return result;
}

// File-type icon as PNG bytes, or empty on failure. Pick the smallest system
// image list that covers the physical-pixel request from Flutter.
std::vector<unsigned char> TypeIconPng(const std::wstring& extension, int iconSize) {
    // Leaf must carry the extension ("x.txt"); ".txt\x" parses as a file
    // named "x" with no extension and falls back to the generic blank icon.
    std::wstring pseudo = L"x" + extension;

    SHFILEINFOW sfi = {};
    if (SHGetFileInfoW(pseudo.c_str(), FILE_ATTRIBUTE_NORMAL, &sfi, sizeof(sfi),
            SHGFI_SYSICONINDEX | SHGFI_USEFILEATTRIBUTES)) {
        const int imageListSize = iconSize <= 16 ? SHIL_SMALL
            : iconSize <= 32 ? SHIL_LARGE
            : iconSize <= 48 ? SHIL_EXTRALARGE
                             : SHIL_JUMBO;
        IImageList* imageList = nullptr;
        if (SUCCEEDED(SHGetImageList(imageListSize, IID_PPV_ARGS(&imageList))) && imageList) {
            HICON icon = nullptr;
            if (SUCCEEDED(imageList->GetIcon(sfi.iIcon, ILD_TRANSPARENT, &icon)) && icon) {
                std::vector<unsigned char> png = IconToPng(icon);
                DestroyIcon(icon);
                imageList->Release();
                if (!png.empty()) return png;
            } else {
                imageList->Release();
            }
        }
    }

    sfi = {};
    if (SHGetFileInfoW(pseudo.c_str(), FILE_ATTRIBUTE_NORMAL, &sfi, sizeof(sfi),
            SHGFI_ICON | SHGFI_USEFILEATTRIBUTES | SHGFI_LARGEICON) &&
        sfi.hIcon) {
        std::vector<unsigned char> png = IconToPng(sfi.hIcon);
        DestroyIcon(sfi.hIcon);
        if (!png.empty()) return png;
    }

    sfi = {};
    if (SHGetFileInfoW(pseudo.c_str(), FILE_ATTRIBUTE_NORMAL, &sfi, sizeof(sfi),
            SHGFI_ICON | SHGFI_USEFILEATTRIBUTES | SHGFI_SMALLICON) &&
        sfi.hIcon) {
        std::vector<unsigned char> png = IconToPng(sfi.hIcon);
        DestroyIcon(sfi.hIcon);
        return png;
    }
    return {};
}

struct ShellNewEntry {
    std::wstring extension;
    std::wstring name;
    std::wstring templatePath;
    std::wstring command;
    std::vector<unsigned char> data;
    std::vector<unsigned char> iconPng;
};

bool CollectEntry(HKEY root, const std::wstring& extension,
    const std::wstring& currentPath, int iconSize, std::vector<ShellNewEntry>& out) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(root, currentPath.c_str(), 0, KEY_READ, &key) != ERROR_SUCCESS)
        return false;

    DWORD subKeyCount = 0, maxNameLen = 0, maxValueNameLen = 0;
    if (RegQueryInfoKeyW(key, nullptr, nullptr, nullptr, &subKeyCount, &maxNameLen,
            nullptr, nullptr, &maxValueNameLen, nullptr, nullptr, nullptr) != ERROR_SUCCESS) {
        RegCloseKey(key);
        return false;
    }

    std::vector<wchar_t> nameBuf(maxNameLen + 2);
    for (DWORD i = 0; i < subKeyCount; i++) {
        DWORD len = (DWORD)nameBuf.size();
        if (RegEnumKeyExW(key, i, nameBuf.data(), &len, nullptr, nullptr, nullptr, nullptr) !=
            ERROR_SUCCESS)
            continue;
        std::wstring subKey(nameBuf.data(), len);
        std::wstring fullPath = currentPath.empty() ? subKey : currentPath + L"\\" + subKey;

        if (_wcsicmp(subKey.c_str(), L"ShellNew") == 0) {
            HKEY shellNew = nullptr;
            if (RegOpenKeyExW(root, fullPath.c_str(), 0, KEY_READ, &shellNew) == ERROR_SUCCESS) {
                DWORD valueCount = 0, shellNewMaxValueNameLen = 0;
                bool hasContent = false;
                std::wstring fileName, command;
                if (RegQueryInfoKeyW(shellNew, nullptr, nullptr, nullptr, nullptr, nullptr,
                        nullptr, &valueCount, &shellNewMaxValueNameLen, nullptr, nullptr,
                        nullptr) == ERROR_SUCCESS) {
                    std::vector<wchar_t> valueBuf(shellNewMaxValueNameLen + 2);
                    for (DWORD v = 0; v < valueCount; v++) {
                        DWORD vlen = (DWORD)valueBuf.size();
                        if (RegEnumValueW(shellNew, v, valueBuf.data(), &vlen,
                                nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS)
                            continue;
                        std::wstring valueName(valueBuf.data(), vlen);
                        if (_wcsicmp(valueName.c_str(), L"NullFile") == 0 ||
                            _wcsicmp(valueName.c_str(), L"Name") == 0) {
                            hasContent = true;
                        } else if (_wcsicmp(valueName.c_str(), L"FileName") == 0) {
                            fileName = RegGetString(shellNew, L"", valueName.c_str());
                            hasContent = true;
                        } else if (_wcsicmp(valueName.c_str(), L"Command") == 0) {
                            command = RegGetString(shellNew, L"", valueName.c_str());
                            hasContent = true;
                        } else if (_wcsicmp(valueName.c_str(), L"Data") == 0 ||
                            _wcsicmp(valueName.c_str(), L"ItemName") == 0) {
                            hasContent = true;
                        }
                    }
                }
                if (hasContent) {
                    ShellNewEntry entry;
                    entry.extension = extension;
                    entry.command = command;
                    entry.templatePath = ResolveTemplatePath(fileName);

                    if (entry.templatePath.empty()) {
                        DWORD type = 0;
                        DWORD size = 0;
                        if (RegQueryValueExW(shellNew, L"Data", nullptr, &type, nullptr, &size) ==
                            ERROR_SUCCESS && size > 0) {
                            entry.data.resize(size);
                            RegQueryValueExW(shellNew, L"Data", nullptr, &type,
                                entry.data.data(), &size);
                            entry.data.resize(size);
                        }
                    }

                    entry.name = ResolveDisplayName(entry.extension);
                    if (entry.name.empty())
                        entry.name = L"x" + entry.extension;
                    entry.iconPng = TypeIconPng(entry.extension, iconSize);
                    out.push_back(std::move(entry));
                }
                RegCloseKey(shellNew);
                if (hasContent) {
                    RegCloseKey(key);
                    return true;
                }
            }
        } else {
            if (CollectEntry(root, extension, fullPath, iconSize, out)) {
                RegCloseKey(key);
                return true;
            }
        }
    }
    RegCloseKey(key);
    return false;
}

} // namespace

extern "C" __declspec(dllexport)
unsigned char* GetShellNewEntries(int iconSize, int* outSize) {
    if (!outSize || iconSize <= 0) return nullptr;
    *outSize = 0;

    std::vector<ShellNewEntry> entries;

    // Iterate top-level HKCR keys; only ".ext" keys can register a ShellNew
    // subkey (possibly nested under their ProgID).
    HKEY root = HKEY_CLASSES_ROOT;
    DWORD subKeyCount = 0, maxNameLen = 0;
    if (RegQueryInfoKeyW(root, nullptr, nullptr, nullptr, &subKeyCount, &maxNameLen,
            nullptr, nullptr, nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS) {
        std::vector<wchar_t> nameBuf(maxNameLen + 2);
        for (DWORD i = 0; i < subKeyCount; i++) {
            DWORD len = (DWORD)nameBuf.size();
            if (RegEnumKeyExW(root, i, nameBuf.data(), &len, nullptr, nullptr, nullptr, nullptr) !=
                ERROR_SUCCESS)
                continue;
            std::wstring extension(nameBuf.data(), len);
            if (extension.empty() || extension[0] != L'.')
                continue;
            if (_wcsicmp(extension.c_str(), L".library-ms") == 0 ||
                _wcsicmp(extension.c_str(), L".url") == 0 ||
                _wcsicmp(extension.c_str(), L".lnk") == 0)
                continue;
            CollectEntry(root, extension, extension, iconSize, entries);
        }
    }

    if (std::none_of(entries.begin(), entries.end(), [](const ShellNewEntry& entry) {
            return _wcsicmp(entry.extension.c_str(), L".txt") == 0;
        })) {
        ShellNewEntry textEntry;
        textEntry.extension = L".txt";
        textEntry.name = ResolveDisplayName(textEntry.extension);
        textEntry.iconPng = TypeIconPng(textEntry.extension, iconSize);
        entries.push_back(std::move(textEntry));
    }

    std::vector<unsigned char> buf;
    AppendInt32(buf, 0); // count placeholder
    int32_t count = 0;

    std::sort(entries.begin(), entries.end(),
        [](const ShellNewEntry& a, const ShellNewEntry& b) {
            return _wcsicmp(a.name.c_str(), b.name.c_str()) < 0;
        });

    for (auto& e : entries) {
        AppendWStr(buf, e.extension);
        AppendWStr(buf, e.name);
        AppendWStr(buf, e.templatePath);
        AppendWStr(buf, e.command);
        AppendBytes(buf, e.data.data(), (int32_t)e.data.size());
        AppendBytes(buf, e.iconPng.data(), (int32_t)e.iconPng.size());
        count++;
    }

    memcpy(buf.data(), &count, sizeof(count));

    SIZE_T totalSz = buf.size();
    unsigned char* result = (unsigned char*)CoTaskMemAlloc(totalSz);
    if (!result) return nullptr;
    memcpy(result, buf.data(), totalSz);
    *outSize = (int)totalSz;
    return result;
}

extern "C" __declspec(dllexport)
void FreeShellNewEntries(unsigned char* ptr) {
    if (ptr) CoTaskMemFree(ptr);
}
