# Project Viewer

`project-view` is the Microsoft Project Quick View plugin for Inf-Dir.

- `host/`: Rust + WebView2 window host and local static-resource protocol.
- `backend/`: Java 17 command-line parser using MPXJ. It prints one versioned JSON document to stdout.
- `web/`: offline TypeScript-free browser UI using dhtmlxGantt for the Gantt view.

## Build

Run `build.bat` from this directory. The script builds the Java shaded jar, packages it with `jpackage`, builds the Rust host, installs the pinned dhtmlxGantt Community bundle, and writes a self-contained package to `bin/Release/project-view/`.

The build requires JDK 17+, Rust/Cargo, Node.js/npm, curl, PowerShell, and either Maven or a network connection for the script's Maven bootstrap.

## Parser contract

The parser accepts `--input <FILE>` and returns a JSON document with `schemaVersion`, project metadata, a flat task list, parent IDs and outline metadata, dates, progress, milestones, and predecessor relations. Diagnostics are written to stderr so stdout remains machine-readable.
