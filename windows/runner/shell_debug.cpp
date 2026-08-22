#include "shell_debug.h"

#include <windows.h>

#include <fstream>
#include <mutex>

namespace {
std::mutex g_shellLogMutex;

std::string ToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}
}  // namespace

void InfDirShellLog(const std::wstring& message) {
  std::lock_guard<std::mutex> lock(g_shellLogMutex);
  wchar_t tempPath[MAX_PATH] = {};
  const DWORD length = GetTempPathW(MAX_PATH, tempPath);
  if (length == 0 || length >= MAX_PATH) return;

  std::wstring path(tempPath);
  path += L"inf-dir-shell.log";
  std::ofstream file(path, std::ios::app | std::ios::binary);
  if (!file) return;

  SYSTEMTIME now = {};
  GetLocalTime(&now);
  char timestamp[64] = {};
  sprintf_s(timestamp, "%04u-%02u-%02u %02u:%02u:%02u.%03u ", now.wYear,
            now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
            now.wMilliseconds);
  file << timestamp << ToUtf8(message) << "\n";
}
