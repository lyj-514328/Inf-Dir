#pragma once
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Shows the native Windows Shell context menu.
//
// hwnd             - owner window handle
// folderPath       - full path of the current folder
// selectedPaths    - array of full paths of selected items (NULL for background)
// selectedCount    - number of selected items (0 for background menu)
// x, y             - screen coordinates (physical pixels) for the menu
// interceptVerbs   - verbs that should NOT be invoked (returned to caller instead)
// interceptCount   - number of intercept verbs
// verbOut          - output buffer receiving the command verb (UTF-16)
// verbOutCch       - size of verbOut in wchar_t units
//
// Returns S_OK on success. verbOut contains the selected verb, or is empty
// if the user cancelled. If the verb was in interceptVerbs, InvokeCommand
// is NOT called - the caller is expected to handle it.
__declspec(dllexport)
HRESULT ShowShellContextMenuW(
    HWND hwnd,
    const wchar_t* folderPath,
    const wchar_t** selectedPaths,
    int selectedCount,
    int x, int y,
    const wchar_t** interceptVerbs,
    int interceptCount,
    wchar_t* verbOut,
    int verbOutCch);

#ifdef __cplusplus
}
#endif
