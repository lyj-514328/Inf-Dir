#include "file_operations.h"

#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <knownfolders.h>
#include <propkey.h>

#include <atomic>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

enum AsyncOperationStatus {
    kQueued = 0,
    kRunning = 1,
    kSucceeded = 2,
    kFailed = 3,
    kCancelled = 4,
};

struct OperationItemResult {
    std::wstring path;
    HRESULT hr = S_OK;
    // Newly created item's filesystem path (copy/move/rename callbacks).
    std::wstring createdPath;
    // Recycle Bin parsing name when the item was recycled (delete callback).
    std::wstring recycledPath;
};

struct AsyncOperationState {
    std::mutex mutex;
    int status = kQueued;
    int progress = 0;
    HRESULT result = S_OK;
    std::atomic<bool> cancelRequested{false};
    std::vector<OperationItemResult> itemResults;
    // UTF-8 JSON of itemResults, built once the operation reaches a terminal
    // state and consumed by InfDirGetFileOperationResultsW.
    std::string resultsJson;
};

std::mutex g_asyncOperationsMutex;
std::map<int64_t, std::shared_ptr<AsyncOperationState>> g_asyncOperations;
std::atomic<int64_t> g_nextOperationId{1};

void SetAsyncState(
    const std::shared_ptr<AsyncOperationState>& state,
    int status,
    int progress,
    HRESULT result) {
    std::lock_guard<std::mutex> lock(state->mutex);
    state->status = status;
    state->progress = progress;
    state->result = result;
}

bool IsCancelled(const std::shared_ptr<AsyncOperationState>& state) {
    return state && state->cancelRequested.load();
}

// Same Windows natural-sort key the directory enumerator uses
// (directory_listing.cpp BuildNameSortKey), so locally inserted entries sort
// identically to enumerated ones.
std::vector<unsigned char> BuildSortKeyForName(const std::wstring& name) {
    if (name.empty()) return {};

    constexpr DWORD flags =
        LCMAP_SORTKEY | SORT_DIGITSASNUMBERS | NORM_IGNORECASE;
    const int keyLength = LCMapStringEx(
        LOCALE_NAME_USER_DEFAULT,
        flags,
        name.data(),
        static_cast<int>(name.size()),
        nullptr,
        0,
        nullptr,
        nullptr,
        0);
    if (keyLength <= 0) return {};

    std::vector<unsigned char> key(keyLength);
    const int written = LCMapStringEx(
        LOCALE_NAME_USER_DEFAULT,
        flags,
        name.data(),
        static_cast<int>(name.size()),
        reinterpret_cast<LPWSTR>(key.data()),
        keyLength,
        nullptr,
        nullptr,
        0);
    if (written <= 0) return {};

    key.resize(written);
    return key;
}

std::string EscapeJsonString(const std::wstring& value) {
    std::string out;
    out.reserve(value.size() + 8);
    for (const wchar_t ch : value) {
        switch (ch) {
        case L'\\': out += "\\\\"; break;
        case L'"': out += "\\\""; break;
        case L'\r': out += "\\r"; break;
        case L'\n': out += "\\n"; break;
        case L'\t': out += "\\t"; break;
        default:
            if (ch < 0x20) {
                char buffer[8];
                snprintf(buffer, sizeof(buffer), "\\u%04x", (unsigned)ch);
                out += buffer;
            } else {
                out += static_cast<char>(ch);
            }
            break;
        }
    }
    return out;
}

std::string BuildResultsJson(
    const std::vector<OperationItemResult>& results) {
    std::string out = "[";
    for (size_t i = 0; i < results.size(); ++i) {
        if (i > 0) out += ",";
        out += "{\"path\":\"";
        out += EscapeJsonString(results[i].path);
        out += "\",\"hr\":";
        out += std::to_string(static_cast<long>(results[i].hr));
        if (!results[i].createdPath.empty()) {
            out += ",\"createdPath\":\"";
            out += EscapeJsonString(results[i].createdPath);
            out += "\"";
        }
        if (!results[i].recycledPath.empty()) {
            out += ",\"recycledPath\":\"";
            out += EscapeJsonString(results[i].recycledPath);
            out += "\"";
        }
        out += "}";
    }
    out += "]";
    return out;
}

// Collects per-item outcomes and real progress from IFileOperation without
// showing Shell UI. FOF_SILENT only suppresses the built-in dialogs; the
// advised sink still receives every callback.
class FileOperationSink final : public IFileOperationProgressSink {
public:
    explicit FileOperationSink(
        const std::shared_ptr<AsyncOperationState>& state)
        : ref_(1), state_(state) {}
    virtual ~FileOperationSink() = default;

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (riid == IID_IUnknown ||
            riid == IID_IFileOperationProgressSink) {
            *ppv = static_cast<IFileOperationProgressSink*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override {
        return ++ref_;
    }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --ref_;
        if (remaining == 0) delete this;
        return remaining;
    }

    STDMETHODIMP StartOperations() override { return S_OK; }
    STDMETHODIMP FinishOperations(HRESULT) override { return S_OK; }
    STDMETHODIMP PreRenameItem(DWORD, IShellItem*, LPCWSTR) override {
        return S_OK;
    }
    STDMETHODIMP PostRenameItem(DWORD, IShellItem*, LPCWSTR, HRESULT,
        IShellItem*) override {
        return S_OK;
    }
    STDMETHODIMP PreMoveItem(DWORD, IShellItem*, IShellItem*, LPCWSTR)
        override {
        return S_OK;
    }
    STDMETHODIMP PostMoveItem(DWORD, IShellItem* item, IShellItem*, LPCWSTR,
        HRESULT hrMove, IShellItem* newlyCreated) override {
        RecordItem(item, hrMove, newlyCreated, false);
        return S_OK;
    }
    STDMETHODIMP PreCopyItem(DWORD, IShellItem*, IShellItem*, LPCWSTR)
        override {
        return S_OK;
    }
    STDMETHODIMP PostCopyItem(DWORD, IShellItem* item, IShellItem*, LPCWSTR,
        HRESULT hrCopy, IShellItem* newlyCreated) override {
        RecordItem(item, hrCopy, newlyCreated, false);
        return S_OK;
    }
    STDMETHODIMP PreDeleteItem(DWORD, IShellItem*) override { return S_OK; }
    STDMETHODIMP PostDeleteItem(DWORD, IShellItem* item, HRESULT hrDelete,
        IShellItem* newlyCreated) override {
        RecordItem(item, hrDelete, newlyCreated, true);
        return S_OK;
    }
    STDMETHODIMP PreNewItem(DWORD, IShellItem*, LPCWSTR) override {
        return S_OK;
    }
    STDMETHODIMP PostNewItem(DWORD, IShellItem*, LPCWSTR, LPCWSTR, DWORD,
        HRESULT, IShellItem*) override {
        return S_OK;
    }
    STDMETHODIMP UpdateProgress(UINT iWorkTotal, UINT iWorkSoFar) override {
        std::lock_guard<std::mutex> lock(state_->mutex);
        if (iWorkTotal > 0) {
            state_->progress = static_cast<int>(
                (static_cast<unsigned long long>(iWorkSoFar) * 100) /
                iWorkTotal);
            // 100 is reserved for the terminal state, set by the worker.
            if (state_->progress > 99) state_->progress = 99;
        }
        return S_OK;
    }
    STDMETHODIMP ResetTimer() override { return S_OK; }
    STDMETHODIMP PauseTimer() override { return S_OK; }
    STDMETHODIMP ResumeTimer() override { return S_OK; }

private:
    // [newlyCreated] carries the item in its new location (copy/move) or in
    // the Recycle Bin (delete), enabling undo history without enumeration.
    void RecordItem(
        IShellItem* item,
        HRESULT hr,
        IShellItem* newlyCreated,
        bool recycled) {
        if (!item) return;
        PWSTR path = nullptr;
        if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) &&
            path) {
            OperationItemResult result;
            result.path = path;
            result.hr = hr;
            CoTaskMemFree(path);

            if (newlyCreated) {
                PWSTR newPath = nullptr;
                const HRESULT nameHr = recycled
                    ? newlyCreated->GetDisplayName(
                        SIGDN_DESKTOPABSOLUTEPARSING, &newPath)
                    : newlyCreated->GetDisplayName(SIGDN_FILESYSPATH, &newPath);
                if (SUCCEEDED(nameHr) && newPath) {
                    if (recycled) {
                        result.recycledPath = newPath;
                    } else {
                        result.createdPath = newPath;
                    }
                    CoTaskMemFree(newPath);
                }
            }

            std::lock_guard<std::mutex> lock(state_->mutex);
            state_->itemResults.push_back(std::move(result));
        }
    }

    std::atomic<ULONG> ref_;
    std::shared_ptr<AsyncOperationState> state_;
};

}  // namespace

static HRESULT RunFileOperationCore(
    int operation,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t* destinationFolder,
    int permanentDelete,
    int collisionMode,
    const std::shared_ptr<AsyncOperationState>& asyncState)
{
    if (!sourcePaths || sourceCount <= 0) return E_INVALIDARG;
    if (IsCancelled(asyncState)) {
        return HRESULT_FROM_WIN32(ERROR_CANCELLED);
    }

    IFileOperation* pfo = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_ALL,
        IID_PPV_ARGS(&pfo));
    if (FAILED(hr)) return hr;

    // Silent shell operation: we show our own confirm dialogs and rely on the
    // shell undo stack instead of the shell's progress/collision UI.
    DWORD flags;
    if (operation == 2) {
        // Delete: recycle to the Recycle Bin (undoable via the app's own
        // history stack) unless permanent. FOF_ALLOWUNDO is deliberately
        // omitted: combined with FOFX_RECYCLEONDELETE it makes PostDeleteItem
        // report COPYENGINE_E_USER_CANCELLED with a null psiNewlyCreated,
        // which loses the recycled parsing name needed for undo.
        flags = FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;
        if (!permanentDelete) {
            flags |= FOFX_RECYCLEONDELETE;
        }
    } else {
        // FOF_NOCONFIRMATION answers "yes to all" to Shell conflict prompts,
        // which silently replaces colliding items; FOF_RENAMEONCOLLISION
        // keeps both by renaming the incoming item. The app pre-detects
        // collisions and picks the mode before calling in.
        flags = FOF_ALLOWUNDO | FOF_NOCONFIRMMKDIR | FOF_SILENT | FOF_NOERRORUI;
        if (collisionMode == 1) flags |= FOF_RENAMEONCOLLISION;
    }
    hr = pfo->SetOperationFlags(flags);
    if (FAILED(hr)) {
        pfo->Release();
        return hr;
    }

    IShellItem* dest = nullptr;
    if (destinationFolder && *destinationFolder) {
        hr = SHCreateItemFromParsingName(destinationFolder, nullptr,
            IID_PPV_ARGS(&dest));
        if (FAILED(hr)) {
            pfo->Release();
            return hr;
        }
    }

    for (int i = 0; i < sourceCount; i++) {
        if (IsCancelled(asyncState)) {
            if (dest) dest->Release();
            pfo->Release();
            return HRESULT_FROM_WIN32(ERROR_CANCELLED);
        }
        if (!sourcePaths[i]) continue;
        IShellItem* src = nullptr;
        hr = SHCreateItemFromParsingName(sourcePaths[i], nullptr,
            IID_PPV_ARGS(&src));
        if (FAILED(hr)) {
            if (dest) dest->Release();
            pfo->Release();
            return hr;
        }
        switch (operation) {
        case 0: hr = pfo->CopyItem(src, dest, nullptr, nullptr); break;
        case 1: hr = pfo->MoveItem(src, dest, nullptr, nullptr); break;
        case 2: hr = pfo->DeleteItem(src, nullptr); break;
        default: hr = E_INVALIDARG; break;
        }
        src->Release();
        if (FAILED(hr)) {
            if (dest) dest->Release();
            pfo->Release();
            return hr;
        }
    }

    FileOperationSink* sink = nullptr;
    DWORD adviseCookie = 0;
    if (asyncState) {
        sink = new FileOperationSink(asyncState);
        hr = pfo->Advise(sink, &adviseCookie);
        if (FAILED(hr)) {
            sink->Release();
            sink = nullptr;
            pfo->Release();
            if (dest) dest->Release();
            return hr;
        }
    }

    hr = pfo->PerformOperations();
    BOOL aborted = FALSE;
    if (SUCCEEDED(hr)) {
        pfo->GetAnyOperationsAborted(&aborted);
        if (aborted) hr = HRESULT_FROM_WIN32(ERROR_CANCELLED);
    }
    if (sink) {
        pfo->Unadvise(adviseCookie);
        sink->Release();
    }
    pfo->Release();
    if (dest) dest->Release();
    return hr;
}

extern "C" __declspec(dllexport)
HRESULT RunFileOperationW(
    int operation,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t* destinationFolder,
    int permanentDelete)
{
    return RunFileOperationCore(
        operation,
        sourcePaths,
        sourceCount,
        destinationFolder,
        permanentDelete,
        0,
        nullptr);
}

extern "C" __declspec(dllexport)
HRESULT InfDirStartFileOperationW(
    int operation,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t* destinationFolder,
    int permanentDelete,
    int collisionMode,
    int64_t* operationId)
{
    if (!sourcePaths || sourceCount <= 0 || !operationId) return E_INVALIDARG;
    if (operation < 0 || operation > 2) return E_INVALIDARG;
    if (collisionMode < 0 || collisionMode > 1) return E_INVALIDARG;

    std::vector<std::wstring> sources;
    sources.reserve(sourceCount);
    for (int i = 0; i < sourceCount; i++) {
        if (!sourcePaths[i]) return E_INVALIDARG;
        sources.emplace_back(sourcePaths[i]);
    }
    const std::wstring destination = destinationFolder
        ? std::wstring(destinationFolder) : std::wstring();

    const int64_t id = g_nextOperationId.fetch_add(1);
    const auto state = std::make_shared<AsyncOperationState>();
    {
        std::lock_guard<std::mutex> lock(g_asyncOperationsMutex);
        g_asyncOperations.emplace(id, state);
    }
    *operationId = id;

    std::thread([
        state,
        operation,
        sources = std::move(sources),
        destination,
        permanentDelete,
        collisionMode]() mutable {
        SetAsyncState(state, kRunning, 1, S_OK);
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        bool initialized = SUCCEEDED(hr);
        if (hr == RPC_E_CHANGED_MODE) {
            hr = S_OK;
            initialized = false;
        }
        if (SUCCEEDED(hr)) {
            std::vector<const wchar_t*> sourcePointers;
            sourcePointers.reserve(sources.size());
            for (const auto& source : sources) {
                sourcePointers.push_back(source.c_str());
            }
            hr = RunFileOperationCore(
                operation,
                sourcePointers.data(),
                static_cast<int>(sourcePointers.size()),
                destination.empty() ? nullptr : destination.c_str(),
                permanentDelete,
                collisionMode,
                state);
        }
        if (initialized) CoUninitialize();

        const bool cancelled = state->cancelRequested.load() ||
            hr == HRESULT_FROM_WIN32(ERROR_CANCELLED);
        const int status = cancelled
            ? kCancelled : SUCCEEDED(hr) ? kSucceeded : kFailed;
        const int progress = cancelled || FAILED(hr) ? 0 : 100;
        {
            std::lock_guard<std::mutex> lock(state->mutex);
            state->status = status;
            state->progress = progress;
            state->result = hr;
            state->resultsJson = BuildResultsJson(state->itemResults);
        }
    }).detach();
    return S_OK;
}

extern "C" __declspec(dllexport)
HRESULT InfDirPollFileOperationW(
    int64_t operationId,
    int* status,
    int* progress,
    int* result)
{
    if (!status || !progress || !result) return E_INVALIDARG;
    std::shared_ptr<AsyncOperationState> state;
    {
        std::lock_guard<std::mutex> lock(g_asyncOperationsMutex);
        const auto found = g_asyncOperations.find(operationId);
        if (found == g_asyncOperations.end()) {
            return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
        }
        state = found->second;
    }
    std::lock_guard<std::mutex> lock(state->mutex);
    *status = state->status;
    *progress = state->progress;
    *result = static_cast<int>(state->result);
    return S_OK;
}

extern "C" __declspec(dllexport)
HRESULT InfDirCancelFileOperationW(int64_t operationId)
{
    std::lock_guard<std::mutex> lock(g_asyncOperationsMutex);
    const auto found = g_asyncOperations.find(operationId);
    if (found == g_asyncOperations.end()) {
        return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
    }
    found->second->cancelRequested.store(true);
    return S_OK;
}

extern "C" __declspec(dllexport)
HRESULT InfDirGetFileOperationResultsW(int64_t operationId, char** outJson)
{
    if (!outJson) return E_INVALIDARG;
    *outJson = nullptr;
    std::shared_ptr<AsyncOperationState> state;
    {
        std::lock_guard<std::mutex> lock(g_asyncOperationsMutex);
        const auto found = g_asyncOperations.find(operationId);
        if (found == g_asyncOperations.end()) {
            return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
        }
        state = found->second;
    }
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->resultsJson.empty()) return S_OK;
    const size_t length = state->resultsJson.size() + 1;
    char* buffer = static_cast<char*>(CoTaskMemAlloc(length));
    if (!buffer) return E_OUTOFMEMORY;
    memcpy(buffer, state->resultsJson.c_str(), length);
    *outJson = buffer;
    state->resultsJson.clear();
    return S_OK;
}

extern "C" __declspec(dllexport)
HRESULT InfDirCloseFileOperationW(int64_t operationId)
{
    std::lock_guard<std::mutex> lock(g_asyncOperationsMutex);
    g_asyncOperations.erase(operationId);
    return S_OK;
}

extern "C" __declspec(dllexport)
HRESULT InfDirBuildNameSortKeyW(
    const wchar_t* name,
    unsigned char** outKey,
    int* outKeyLen)
{
    if (!name || !*name || !outKey || !outKeyLen) return E_INVALIDARG;
    *outKey = nullptr;
    *outKeyLen = 0;

    const std::vector<unsigned char> key = BuildSortKeyForName(name);
    if (key.empty()) return S_FALSE;

    unsigned char* buffer = static_cast<unsigned char*>(
        CoTaskMemAlloc(key.size()));
    if (!buffer) return E_OUTOFMEMORY;
    memcpy(buffer, key.data(), key.size());
    *outKey = buffer;
    *outKeyLen = static_cast<int>(key.size());
    return S_OK;
}

extern "C" __declspec(dllexport)
HRESULT EmptyRecycleBinW(HWND owner)
{
    return SHEmptyRecycleBinW(owner, nullptr,
        SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
}

static HRESULT RestoreRecycleBinCore(
    HWND owner,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t** destinationOverrides,
    int collisionMode,
    const std::shared_ptr<AsyncOperationState>& asyncState)
{
    if (!sourcePaths || sourceCount <= 0) return E_INVALIDARG;
    if (IsCancelled(asyncState)) {
        return HRESULT_FROM_WIN32(ERROR_CANCELLED);
    }

    IShellItem* recycleBin = nullptr;
    HRESULT hr = SHGetKnownFolderItem(FOLDERID_RecycleBinFolder,
        KF_FLAG_DEFAULT, nullptr, IID_PPV_ARGS(&recycleBin));
    if (FAILED(hr) || !recycleBin) return FAILED(hr) ? hr : E_FAIL;

    IEnumShellItems* items = nullptr;
    hr = recycleBin->BindToHandler(nullptr, BHID_EnumItems,
        IID_PPV_ARGS(&items));
    recycleBin->Release();
    if (FAILED(hr) || !items) return FAILED(hr) ? hr : E_FAIL;

    IFileOperation* pfo = nullptr;
    hr = CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_ALL,
        IID_PPV_ARGS(&pfo));
    if (FAILED(hr)) {
        items->Release();
        return hr;
    }

    // FOF_NOCONFIRMATION answers "yes to all" to Shell conflict prompts,
    // which silently replaces colliding items; FOF_RENAMEONCOLLISION keeps
    // both by renaming the restored item. The app pre-detects collisions and
    // picks the mode before calling in.
    DWORD flags = FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;
    if (collisionMode == 1) flags |= FOF_RENAMEONCOLLISION;
    hr = pfo->SetOperationFlags(flags);
    if (SUCCEEDED(hr) && owner) hr = pfo->SetOwnerWindow(owner);
    if (FAILED(hr)) {
        items->Release();
        pfo->Release();
        return hr;
    }

    PROPERTYKEY originalDirectoryKey = {};
    hr = PSGetPropertyKeyFromName(
        L"System.Recycle.DeletedFrom", &originalDirectoryKey);
    if (FAILED(hr)) {
        items->Release();
        pfo->Release();
        return hr;
    }

    auto isMatched = new bool[sourceCount]();
    int matchedCount = 0;
    IShellItem* source = nullptr;
    while (matchedCount < sourceCount &&
           items->Next(1, &source, nullptr) == S_OK) {
        if (IsCancelled(asyncState)) {
            source->Release();
            source = nullptr;
            hr = HRESULT_FROM_WIN32(ERROR_CANCELLED);
            break;
        }
        PWSTR parsingName = nullptr;
        hr = source->GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING,
            &parsingName);
        int selectedIndex = -1;
        if (SUCCEEDED(hr) && parsingName) {
            for (int i = 0; i < sourceCount; i++) {
                if (!isMatched[i] && sourcePaths[i] &&
                    _wcsicmp(sourcePaths[i], parsingName) == 0) {
                    selectedIndex = i;
                    break;
                }
            }
        }
        if (parsingName) CoTaskMemFree(parsingName);
        if (selectedIndex < 0) {
            source->Release();
            source = nullptr;
            continue;
        }

        // Prefer the caller-provided override; otherwise fall back to the
        // original directory recorded by the Shell.
        const wchar_t* override = (destinationOverrides &&
                                   destinationOverrides[selectedIndex] &&
                                   *destinationOverrides[selectedIndex])
            ? destinationOverrides[selectedIndex] : nullptr;
        PWSTR originalDirectory = nullptr;
        if (override) {
            hr = S_OK;
        } else {
            IShellItem2* source2 = nullptr;
            hr = source->QueryInterface(IID_PPV_ARGS(&source2));
            if (SUCCEEDED(hr)) {
                hr = source2->GetString(originalDirectoryKey,
                    &originalDirectory);
            }
            if (source2) source2->Release();
        }
        if (SUCCEEDED(hr)) {
            const wchar_t* target = override ? override : originalDirectory;
            if (target && *target) {
                IShellItem* destination = nullptr;
                hr = SHCreateItemFromParsingName(target, nullptr,
                    IID_PPV_ARGS(&destination));
                if (SUCCEEDED(hr)) {
                    // A null new name asks Shell to restore the item's
                    // original display name, including the extension.
                    hr = pfo->MoveItem(source, destination, nullptr, nullptr);
                    destination->Release();
                }
            } else {
                hr = E_INVALIDARG;
            }
        }
        if (originalDirectory) CoTaskMemFree(originalDirectory);
        source->Release();
        source = nullptr;
        if (FAILED(hr)) break;

        isMatched[selectedIndex] = true;
        matchedCount++;
    }
    if (source) source->Release();
    items->Release();
    if (SUCCEEDED(hr) && matchedCount != sourceCount) {
        hr = HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
    }
    delete[] isMatched;

    FileOperationSink* sink = nullptr;
    DWORD adviseCookie = 0;
    if (SUCCEEDED(hr) && asyncState) {
        sink = new FileOperationSink(asyncState);
        hr = pfo->Advise(sink, &adviseCookie);
        if (FAILED(hr)) {
            sink->Release();
            sink = nullptr;
        }
    }
    if (SUCCEEDED(hr)) {
        hr = pfo->PerformOperations();
        BOOL aborted = FALSE;
        if (SUCCEEDED(hr)) {
            pfo->GetAnyOperationsAborted(&aborted);
            if (aborted) hr = HRESULT_FROM_WIN32(ERROR_CANCELLED);
        }
    }
    if (sink) {
        pfo->Unadvise(adviseCookie);
        sink->Release();
    }
    pfo->Release();
    return hr;
}

extern "C" __declspec(dllexport)
HRESULT RestoreRecycleBinItemsW(
    HWND owner,
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t** destinationOverrides,
    int collisionMode)
{
    return RestoreRecycleBinCore(
        owner, sourcePaths, sourceCount, destinationOverrides,
        collisionMode, nullptr);
}

extern "C" __declspec(dllexport)
HRESULT InfDirStartRestoreOperationW(
    const wchar_t** sourcePaths,
    int sourceCount,
    const wchar_t** destinationOverrides,
    int collisionMode,
    int64_t* operationId)
{
    if (!sourcePaths || sourceCount <= 0 || !operationId) return E_INVALIDARG;
    if (collisionMode < 0 || collisionMode > 1) return E_INVALIDARG;

    std::vector<std::wstring> sources;
    sources.reserve(sourceCount);
    for (int i = 0; i < sourceCount; i++) {
        if (!sourcePaths[i]) return E_INVALIDARG;
        sources.emplace_back(sourcePaths[i]);
    }
    std::vector<std::wstring> overrides;
    if (destinationOverrides) {
        overrides.reserve(sourceCount);
        for (int i = 0; i < sourceCount; i++) {
            overrides.emplace_back(destinationOverrides[i]
                ? std::wstring(destinationOverrides[i]) : std::wstring());
        }
    }

    const int64_t id = g_nextOperationId.fetch_add(1);
    const auto state = std::make_shared<AsyncOperationState>();
    {
        std::lock_guard<std::mutex> lock(g_asyncOperationsMutex);
        g_asyncOperations.emplace(id, state);
    }
    *operationId = id;

    std::thread([
        state,
        sources = std::move(sources),
        overrides = std::move(overrides),
        collisionMode]() mutable {
        SetAsyncState(state, kRunning, 1, S_OK);
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        bool initialized = SUCCEEDED(hr);
        if (hr == RPC_E_CHANGED_MODE) {
            hr = S_OK;
            initialized = false;
        }
        if (SUCCEEDED(hr)) {
            std::vector<const wchar_t*> sourcePointers;
            sourcePointers.reserve(sources.size());
            for (const auto& source : sources) {
                sourcePointers.push_back(source.c_str());
            }
            std::vector<const wchar_t*> overridePointers;
            if (!overrides.empty()) {
                overridePointers.reserve(overrides.size());
                for (const auto& override : overrides) {
                    overridePointers.push_back(
                        override.empty() ? nullptr : override.c_str());
                }
            }
            hr = RestoreRecycleBinCore(
                nullptr,
                sourcePointers.data(),
                static_cast<int>(sourcePointers.size()),
                overridePointers.empty() ? nullptr : overridePointers.data(),
                collisionMode,
                state);
        }
        if (initialized) CoUninitialize();

        const bool cancelled = state->cancelRequested.load() ||
            hr == HRESULT_FROM_WIN32(ERROR_CANCELLED);
        const int status = cancelled
            ? kCancelled : SUCCEEDED(hr) ? kSucceeded : kFailed;
        const int progress = cancelled || FAILED(hr) ? 0 : 100;
        {
            std::lock_guard<std::mutex> lock(state->mutex);
            state->status = status;
            state->progress = progress;
            state->result = hr;
            state->resultsJson = BuildResultsJson(state->itemResults);
        }
    }).detach();
    return S_OK;
}

extern "C" __declspec(dllexport)
HRESULT PickFolderW(HWND owner, const wchar_t* initialPath, wchar_t** outPath)
{
    if (!outPath) return E_INVALIDARG;
    *outPath = nullptr;

    IFileOpenDialog* dialog = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
    if (FAILED(hr)) return hr;

    DWORD options = 0;
    hr = dialog->GetOptions(&options);
    if (SUCCEEDED(hr)) {
        hr = dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
    }
    if (SUCCEEDED(hr) && initialPath && *initialPath) {
        IShellItem* initialItem = nullptr;
        hr = SHCreateItemFromParsingName(initialPath, nullptr,
            IID_PPV_ARGS(&initialItem));
        if (SUCCEEDED(hr)) {
            hr = dialog->SetFolder(initialItem);
            initialItem->Release();
        } else {
            // Unusable initial path: let the dialog start at its default.
            hr = S_OK;
        }
    }
    if (SUCCEEDED(hr)) {
        hr = dialog->Show(owner);
        if (SUCCEEDED(hr)) {
            IShellItem* result = nullptr;
            hr = dialog->GetResult(&result);
            if (SUCCEEDED(hr) && result) {
                PWSTR path = nullptr;
                hr = result->GetDisplayName(SIGDN_FILESYSPATH, &path);
                if (SUCCEEDED(hr) && path) {
                    const size_t length = wcslen(path) + 1;
                    *outPath = static_cast<wchar_t*>(
                        CoTaskMemAlloc(length * sizeof(wchar_t)));
                    if (*outPath) {
                        wcscpy_s(*outPath, length, path);
                    } else {
                        hr = E_OUTOFMEMORY;
                    }
                    CoTaskMemFree(path);
                }
                result->Release();
            }
        }
    }
    dialog->Release();
    return hr;
}

extern "C" __declspec(dllexport)
void FreeCoTaskMemW(void* ptr)
{
    CoTaskMemFree(ptr);
}
