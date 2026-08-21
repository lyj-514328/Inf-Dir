# onlyoffice-view

`onlyoffice-view` is an independent read-only viewer for Office-compatible formats.
It converts the source document to PDF with ONLYOFFICE `x2t`, then renders the
result with the bundled PDF.js WebView2 viewer.

Excel formats are intentionally not declared by this plugin yet. The Excel
viewer will be added separately after its rendering path is selected.

## Runtime

`plugins/build.bat` downloads the official ONLYOFFICE Document Builder Windows
x64 package and includes its complete runtime under `onlyoffice/` in the
plugin distribution. This includes `x2t.exe` and its DLLs, fonts, themes, and
other assets required by the converter.

At runtime, `ONLYOFFICE_X2T_PATH` can point directly to `x2t.exe`; otherwise the
plugin searches the bundled `onlyoffice/` directory beside its executable.

## Usage

```text
onlyoffice-view.exe <file> [--window-placement <JSON>]
```
