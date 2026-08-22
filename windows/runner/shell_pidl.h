#pragma once

#include <shlobj.h>
#include <shobjidl.h>
#include <string>

bool InfDirIsPidlPath(const wchar_t* path);

// Returns an opaque, stable-in-process path containing the item's PIDL.
std::wstring InfDirPidlPathFromShellItem(IShellItem* item);

// Resolves either a normal parsing path or a \\SHELL\ PIDL path.
HRESULT InfDirCreateShellItemFromPath(const wchar_t* path, IShellItem** item);

// Resolves either a normal parsing path or a \\SHELL\ PIDL path. The caller
// owns the returned PIDL and must release it with CoTaskMemFree.
HRESULT InfDirGetPidlFromPath(const wchar_t* path, PIDLIST_ABSOLUTE* pidl);

extern "C" __declspec(dllexport)
int OpenShellItemW(const wchar_t* path);
