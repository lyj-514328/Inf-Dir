# excel-view

`excel-view` is an independent WebView2 spreadsheet viewer. It loads local
`.xlsx`-family files into FortuneSheet and uses FortuneExcel for local XLSX
import/export. No server or network request is needed after the static assets
have been built.

The existing `office-view` and `onlyoffice-view` plugins may also declare some
of these extensions. Viewer priority decides which plugin handles an overlap.
Legacy binary `.xls` and `.xlsb` files remain assigned to the ONLYOFFICE x2t
viewer until a local XLSX conversion path is added here.

## Build

`plugins/build.bat` runs `plugins/excel-view/build.bat`, which installs the
pinned npm dependencies and bundles FortuneSheet/FortuneExcel into the plugin
distribution.

## Usage

```text
excel-view.exe <file.xlsx> [--window-placement <JSON>]
```

The viewer starts read-only. The export control is available for testing the
FortuneExcel round trip.
