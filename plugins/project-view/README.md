# Project Viewer

`project-view` is the Microsoft Project Quick View plugin for Inf-Dir.

- `host/`: Rust + WebView2 window host with an in-process `mpxj-rs` parser.
- `web/`: offline TypeScript-free browser UI using dhtmlxGantt for the Gantt view.

## Build

Run `build.bat` from this directory. The script builds and tests the native Rust host, installs the pinned dhtmlxGantt Community bundle, and writes a self-contained package to `bin/Release/project-view/`.

The build requires Rust 1.85+ with Cargo and Node.js/npm. The packaged viewer also requires the WebView2 Runtime.

## Parser contract

The parser runs inside `project-view.exe` and returns a JSON document through the viewer's local protocol with `schemaVersion`, project metadata, a flat task list, parent IDs and outline metadata, dates, progress, milestones, and predecessor relations. Recoverable `mpxj-rs` errors are included in `warnings`.

The production plugin reads MPP/MPT (MPP8, MPP9, MPP12, and MPP14) and MPX 3.0/4.0. The parser also supports MSPDI XML when invoked directly, but `.xml` is not registered globally because it is not specific to Microsoft Project.
