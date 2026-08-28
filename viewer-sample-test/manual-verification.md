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

## img-view RAW and Container Fallbacks

Date: 2026-08-28

The post-fix targeted verification used
`C:\Users\LYJ514328\Desktop\BaiduSyncdisk\abc\samples` with a freshly built
`img-view` package:

- `image\ptx\sample_web.ptx`: opened through the built-in V.Flash BGR555 decoder.
- `raw\arw\sample_archive.arw` and `raw\cr3\sample_archive.cr3`: opened through
  ImageMagick's LibRaw-backed RAW coder.
- `raw\raw\sample_archive.raw`: opened through content sniffing, which decoded
  its actual JPEG bytes before the extension-driven RAW coder was attempted.
- `raw\x3f\sample_archive.x3f`: opened through the embedded JPEG preview fallback
  when ImageMagick's LibRaw-backed RAW coder could not decode the RAW payload.

The no-`libraw-decoder.exe` regression run then forced ImageMagick's `dng:`
coder for RAW extensions that it does not register directly. This recovered the
`.bay`, `.ia`, `.kc2`, `.pxn`, `.qtk`, and `.rdc` viewer samples; `.cs1` decoded
through the same path but did not produce a window within the harness's 5-second
ready timeout. The complete run produced 99 responsive windows out of 111 jobs.

The historical generated report above predates the packaged LibRaw decoder and
is intentionally left unchanged; the targeted post-fix results are recorded
here instead.
