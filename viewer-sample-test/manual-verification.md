# Manual Verification Notes

Date: 2026-08-28

## CHM Viewer

- `C:\Users\lyjia\Downloads\w3school.html.chm` opened successfully in
  `chm-view.exe` and displayed a responsive window.
- The automated sample
  `D:\BaiduNetdiskDownload\abc\samples\document\chm\sample_web.chm`
  displayed this content error inside the viewer:

  `Unexpected ITSF GUIDs: {00000000-0000-0000-0000-000000000000} / {00000060-0000-0000-0000-000000000000}`

The sample begins with the `ITSF` magic but has invalid zero GUID fields. This
is recorded as a sample/content error, not as a `chm-view` process-startup
failure. The automated `running_window` result therefore needs the manual
override in `manual-overrides.jsonl` for a content-level conclusion.
