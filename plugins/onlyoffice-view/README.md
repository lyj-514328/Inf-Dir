# onlyoffice-view

`onlyoffice-view` is an independent read-only viewer for Office-compatible formats.
It converts the source document to PDF with ONLYOFFICE `x2t`, then renders the
result with the bundled PDF.js WebView2 viewer.

Excel formats are intentionally not declared by this plugin yet. The Excel
viewer will be added separately after its rendering path is selected.

## Runtime

The plugin does not include an x2t binary in source control. At runtime, place
the ONLYOFFICE conversion runtime in an `onlyoffice/` directory beside the
executable, or set `ONLYOFFICE_X2T_PATH` to the converter executable or
`ONLYOFFICE_X2T_DIR` to its containing directory. The runtime must also include
the fonts and presentation themes expected by x2t.

## Usage

```text
onlyoffice-view.exe <file> [--window-placement <JSON>]
```
