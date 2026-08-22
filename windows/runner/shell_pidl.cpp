#include "shell_pidl.h"

#include "shell_debug.h"

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

namespace {
constexpr wchar_t kPidlPrefix[] = L"\\\\SHELL\\";
constexpr char kBase64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string EncodeBase64(const unsigned char* data, size_t size) {
  std::string result;
  result.reserve(((size + 2) / 3) * 4);
  for (size_t i = 0; i < size; i += 3) {
    const unsigned int a = data[i];
    const unsigned int b = i + 1 < size ? data[i + 1] : 0;
    const unsigned int c = i + 2 < size ? data[i + 2] : 0;
    result.push_back(kBase64[(a >> 2) & 0x3f]);
    result.push_back(kBase64[((a << 4) | (b >> 4)) & 0x3f]);
    result.push_back(i + 1 < size ? kBase64[((b << 2) | (c >> 6)) & 0x3f]
                                  : '=');
    result.push_back(i + 2 < size ? kBase64[c & 0x3f] : '=');
  }
  std::replace(result.begin(), result.end(), '/', '_');
  return result;
}

int Base64Value(char value) {
  if (value >= 'A' && value <= 'Z') return value - 'A';
  if (value >= 'a' && value <= 'z') return value - 'a' + 26;
  if (value >= '0' && value <= '9') return value - '0' + 52;
  if (value == '+' || value == '-') return 62;
  if (value == '_' || value == '/') return 63;
  return -1;
}

bool DecodeBase64(const std::wstring& input, std::vector<unsigned char>& output) {
  if (input.empty() || input.size() % 4 != 0) return false;
  output.clear();
  output.reserve((input.size() / 4) * 3);
  for (size_t i = 0; i < input.size(); i += 4) {
    const int a = Base64Value(static_cast<char>(input[i]));
    const int b = Base64Value(static_cast<char>(input[i + 1]));
    if (a < 0 || b < 0) return false;
    const wchar_t cChar = input[i + 2];
    const wchar_t dChar = input[i + 3];
    const int c = cChar == L'=' ? 0 : Base64Value(static_cast<char>(cChar));
    const int d = dChar == L'=' ? 0 : Base64Value(static_cast<char>(dChar));
    if (c < 0 || d < 0) return false;
    output.push_back(static_cast<unsigned char>((a << 2) | (b >> 4)));
    if (cChar != L'=')
      output.push_back(static_cast<unsigned char>((b << 4) | (c >> 2)));
    if (dChar != L'=')
      output.push_back(static_cast<unsigned char>((c << 6) | d));
  }
  return true;
}

HRESULT PidlFromOpaquePath(const wchar_t* path, PIDLIST_ABSOLUTE* pidl) {
  if (!path || !pidl) return E_INVALIDARG;
  *pidl = nullptr;
  std::wstring encoded(path + wcslen(kPidlPrefix));
  std::vector<unsigned char> bytes;
  if (!DecodeBase64(encoded, bytes) || bytes.size() < sizeof(USHORT))
    return E_INVALIDARG;

  const auto* source = reinterpret_cast<const ITEMIDLIST*>(bytes.data());
  const UINT size = ILGetSize(source);
  if (size == 0 || size > bytes.size()) return E_INVALIDARG;
  auto* copy = static_cast<PIDLIST_ABSOLUTE>(CoTaskMemAlloc(size));
  if (!copy) return E_OUTOFMEMORY;
  memcpy(copy, bytes.data(), size);
  *pidl = copy;
  return S_OK;
}
}  // namespace

bool InfDirIsPidlPath(const wchar_t* path) {
  return path && wcsncmp(path, kPidlPrefix, wcslen(kPidlPrefix)) == 0;
}

std::wstring InfDirPidlPathFromShellItem(IShellItem* item) {
  if (!item) return {};
  PIDLIST_ABSOLUTE pidl = nullptr;
  if (FAILED(SHGetIDListFromObject(item, &pidl)) || !pidl) return {};
  const UINT size = ILGetSize(pidl);
  std::wstring result;
  if (size > 0) {
    const auto encoded = EncodeBase64(reinterpret_cast<const unsigned char*>(pidl), size);
    result = kPidlPrefix;
    result.append(encoded.begin(), encoded.end());
  }
  CoTaskMemFree(pidl);
  return result;
}

HRESULT InfDirGetPidlFromPath(const wchar_t* path, PIDLIST_ABSOLUTE* pidl) {
  if (!path || !pidl) return E_INVALIDARG;
  if (InfDirIsPidlPath(path)) return PidlFromOpaquePath(path, pidl);
  return SHParseDisplayName(path, nullptr, pidl, 0, nullptr);
}

HRESULT InfDirCreateShellItemFromPath(const wchar_t* path, IShellItem** item) {
  if (!path || !item) return E_INVALIDARG;
  *item = nullptr;
  if (InfDirIsPidlPath(path)) {
    PIDLIST_ABSOLUTE pidl = nullptr;
    const HRESULT hr = PidlFromOpaquePath(path, &pidl);
    if (FAILED(hr)) return hr;
    const HRESULT result = SHCreateItemFromIDList(
        pidl, IID_PPV_ARGS(item));
    CoTaskMemFree(pidl);
    return result;
  }
  return SHCreateItemFromParsingName(path, nullptr, IID_PPV_ARGS(item));
}

extern "C" __declspec(dllexport)
int OpenShellItemW(const wchar_t* path) {
  if (!path) return static_cast<int>(E_INVALIDARG);
  InfDirShellLog(L"open entered");
  const std::wstring requestedPath(path);
  InfDirShellLog(L"open request path=" + requestedPath);
  const HRESULT comResult = CoInitializeEx(
      nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  const bool comInitialized = comResult == S_OK;
  if (FAILED(comResult) && comResult != RPC_E_CHANGED_MODE)
    return static_cast<int>(comResult);

  PIDLIST_ABSOLUTE pidl = nullptr;
  const HRESULT hr = InfDirGetPidlFromPath(requestedPath.c_str(), &pidl);
  if (FAILED(hr) || !pidl) {
    InfDirShellLog(L"open pidl resolve failed hr=0x" +
                   std::to_wstring(static_cast<unsigned long>(hr)));
    if (comInitialized) CoUninitialize();
    return static_cast<int>(hr);
  }

  SHELLEXECUTEINFOW execute = {};
  execute.cbSize = sizeof(execute);
  execute.fMask = SEE_MASK_IDLIST;
  execute.lpIDList = pidl;
  execute.nShow = SW_SHOWNORMAL;
  const BOOL opened = ShellExecuteExW(&execute);
  const DWORD error = opened ? ERROR_SUCCESS : GetLastError();
  InfDirShellLog(L"open shell execute result=" +
                 std::to_wstring(opened ? 1 : 0) + L" error=" +
                 std::to_wstring(error));
  CoTaskMemFree(pidl);
  if (comInitialized) CoUninitialize();
  return opened ? 0 : static_cast<int>(HRESULT_FROM_WIN32(error));
}
