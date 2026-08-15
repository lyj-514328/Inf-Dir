# pdf-view

Standalone PDF viewer for Inf-Dir, built with `egui`/`eframe` and
`pdfium-render`. PDFium is the PDF engine used by Chromium.

## Build

Run `build.bat` from a normal Windows command prompt or from the UCRT64 shell.
The crate is pinned to Rust's `x86_64-pc-windows-gnu` target and uses
`C:\msys64\ucrt64\bin\gcc.exe` as its linker.

`pdfium-render` loads PDFium dynamically. Supply a compatible 64-bit PDFium
7881 `pdfium.dll` in this directory before running `build.bat`, or put it beside
the built executable yourself. At runtime, `PDFIUM_PATH` can override the DLL
with either a file path or a containing folder.

## Run

```text
pdf-view.exe document.pdf --window-placement "{\"version\":2,\"x\":100,\"y\":100,\"clientWidth\":944,\"clientHeight\":681,\"maximized\":false}"
```

Keys: `Left`/`Right` or `PageUp`/`PageDown` changes pages, `Home`/`End` jumps
to the first/last page, `+`/`-` or `Ctrl+wheel` changes zoom, `F` fits the
page, `W` fits its width, `R` rotates, and `Esc` closes the window.
