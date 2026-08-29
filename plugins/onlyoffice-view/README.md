# onlyoffice-view

`onlyoffice-view` is an independent read-only viewer for Office-compatible formats.
It converts the source document to PDF with ONLYOFFICE `docbuilder.exe`, then
renders the result with the bundled PDF.js WebView2 viewer.

Excel formats are also declared by this plugin. They are converted to PDF by
`docbuilder.exe` and rendered by the bundled PDF.js viewer. The existing `office-view`
plugin may also declare OOXML Excel formats; the user's viewer priority decides
which renderer opens an overlapping extension.

## Runtime

`plugins/build.bat` downloads the official ONLYOFFICE Document Builder Windows
x64 package, extracts it without pruning, and copies the complete installation
under `onlyoffice/` in the plugin distribution. This includes
`docbuilder.exe`, its internal `x2t.exe`, all DLLs, fonts, themes, SDK files,
and other assets required by the converter.

At runtime, `ONLYOFFICE_DOCBUILDER_PATH` can point directly to `docbuilder.exe`;
otherwise the plugin searches the bundled `onlyoffice/` directory beside its
executable. Document Builder initializes its font cache before converting and
uses `x2t` internally with the generated conversion metadata.

The public runtime does not include a license. Without one, Builder can still
produce preview PDFs but marks them with an `Unregistered Version` watermark.
For a licensed deployment, place the vendor-provided `license.xml` beside
`onlyoffice/docbuilder.exe`, or register it with
`docbuilder.exe -register <license.xml>`;
alternatively set `ONLYOFFICE_BUILDER_LICENSE` to the license path before
launching Inf-Dir. Do not commit the license file to the repository.

## Usage

```text
onlyoffice-view.exe <file> [--window-placement <JSON>]
```
