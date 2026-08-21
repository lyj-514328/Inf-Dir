# CHM Viewer Maintenance Notes

## Blank window incident (2026-08-21)

### Symptoms

- The window title contained the CHM file name, but the content area was blank.
- In an intermediate state the CHMate toolbar rendered, while the CHM file was
  still not loaded.
- The Rust process did not report a parsing error.

### Root causes

1. Wry uses a WebView2 workaround for custom protocols on Windows. A page
   opened as `http://chm-view.local/...` is navigated internally as
   `http://http.chm-view.local/...`. The navigation allow-list matched only the
   original host, so the document response was served and then blocked.
2. The startup query contained the original `http://chm-view.local/file`
   address. The page ran under the rewritten WebView2 origin, so that absolute
   URL did not route back through Wry's custom protocol handler. The startup
   file URL must remain relative (`/file`).
3. The packaged page hides CHMate's optional sample link. Removing its
   `btnSample` element without changing the upstream initialization code caused
   an unconditional `addEventListener` call to throw before the automatic
   `?file=` load ran. Optional upstream UI hooks must be null-checked when the
   corresponding element is intentionally omitted.
4. A release executable built under `target/release` can be launched before
   the generated web directory is copied beside it. The host therefore checks
   the executable directory and its parent plugin directories when resolving
   `chm-view-web`.

### Prevention checklist

- When changing Wry protocol or navigation code, verify both the original URL
  and the WebView2 rewritten URL on Windows.
- Keep the startup resource URL relative to `location.origin`.
- Treat every removed upstream DOM element as an API change and guard its JS
  event hook.
- Smoke-test the standalone release executable, the plugin distribution copy,
  and the Flutter Debug plugin copy.
- Open `ai_refs/CHMate/samples/putty.chm` as a bundled parser/rendering smoke
  test before testing a user-supplied CHM.

### Verification commands

```powershell
cmd /c plugins\chm-view\build.bat
cargo test --manifest-path plugins/chm-view/Cargo.toml
flutter test test/viewer_format_coverage_test.dart
Get-ChildItem plugins/chm-view/web/src -Recurse -Filter *.js | ForEach-Object { node --check $_.FullName }
```
