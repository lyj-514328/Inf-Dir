# Viewer Sample Test Report

- Run: 20260829-135513
- Samples root: C:\Users\LYJ514328\Desktop\BaiduSyncdisk\abc\samples
- Initial persisted records: 111
- Rechecked records: 15
- Manual override records: 0
- Final logical viewer/sample jobs: 111
- Responsive windows (including content errors): 101
- Responsive windows without an explicit viewer error: 101
- The initial run had one JSONL write lost to a file lock; the missing AAI job was rechecked and included in the final set.

## Classification

- running_window: the process created a responsive window within the test timeout.
- content_error: a responsive window appeared, but the viewer reported a decode/open/initialization error for the sample.
- exit_nonzero: the process exited before a responsive window was observed and reported a non-zero/failed launch result.
- exit_zero: the process exited before a responsive window with code zero.
- running_no_window / hung / start_error: viewing could not be confirmed.
- WebView2 and Office viewers can show an in-window decoder error without exiting; running_window confirms startup, not visual content acceptance.
- Jobs are created only when a sample basename matches a manifest fileName or declared extension; declared formats with no matching sample are outside this run.

## Overall

| Status | Count |
| --- | ---: |
| exit_nonzero | 10 |
| running_window | 101 |

## By Viewer

| Viewer | Declared samples | Responsive windows | Failures / content errors | Indeterminate |
| --- | ---: | ---: | ---: | ---: |
| inf-dir.image-view | 111 | 101 | 10 | 0 |

## Failures and anomalies

| Viewer | Declared format | Sample | Status | Exit code | Verification | Error output |
| --- | --- | --- | --- | ---: | --- | --- |
| inf-dir.image-view | .dpx | image\dpx\sample_rawcooked.dpx | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."dpx"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |
| inf-dir.image-view | .erf | image\erf\sample1.erf | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?content decode failed: content sniff failed: The image format could not be determined; ImageMagick RAW decode failed: magick.exe: Unsupported file format or not RAW file `C:\Users\LYJ514328\Desktop\BaiduSyncdis ... |
| inf-dir.image-view | .jng | image\jng\sample_libpng_jdaa.jng | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."jng"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |
| inf-dir.image-view | .jxr | image\jxr\sample_nomacs.jxr | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."jxr"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |
| inf-dir.image-view | .mvg | image\mvg\sample_sembiance.mvg | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."mvg"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |
| inf-dir.image-view | .ora | image\ora\sample_orajs.ora | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."ora"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |
| inf-dir.image-view | .pix | image\pix\sample_web.pix | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."pix"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |
| inf-dir.image-view | .sfw | image\sfw\sample_sfw2jpg.sfw | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."sfw"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |
| inf-dir.image-view | .cine | raw\cine\sample_ffmpeg.cine | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."cine"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback faile ... |
| inf-dir.image-view | .cin | video\cin\sample_ffmpeg.cin | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."cin"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |

Raw per-job results: viewer-sample-test\results\20260829-135513\results.jsonl
Recheck results: viewer-sample-test\results\20260829-135513\recheck.jsonl
Recheck results: viewer-sample-test\results\20260829-135513\recheck-failures.jsonl

## Run notes

- The executable was rebuilt from the current `HEAD` on 2026-08-29.
- The package included the ImageMagick and LibRaw runtimes from `plugins/img-view`.
- The initial 5-second pass found four slow RAW decodes; all four became responsive in the 12-second recheck.
- The sample tree contains pre-existing derived `.tiff` files from earlier manual checks; they are included in the 111 matched jobs.

## Post-fix targeted recheck (2026-08-29)

The image viewer was rebuilt from the current source and copied to
`plugins/dist/inf-dir.image-view/img-view.exe` (SHA-256:
`44B5258ACB1BFCA1A78A9933F8931C4982410F107A3F64853350DD2376C90815`). The
release unit suite passed all 5 tests. The ten samples listed in the original
failure set were launched again with a 12-second responsive-window timeout.

Six cases now start a responsive viewer: JNG, JXR, MVG, ORA, SFW, and Phantom
CINE RAW. With the four Cineon samples added below, the current targeted status
is 111 of 115 matched image-view jobs responsive; four content failures remain.

| Sample | Result |
| --- | --- |
| `image\\jng\\sample_libpng_jdaa.jng` | recovered via patched ImageMagick JNG decode; malformed alpha falls back to color-only preview |
| `image\\jxr\\sample_nomacs.jxr` | recovered via Windows WIC decoder |
| `image\\mvg\\sample_sembiance.mvg` | recovered via explicit MVG dispatch |
| `image\\ora\\sample_orajs.ora` | recovered via ORA ZIP thumbnail extraction |
| `image\\sfw\\sample_sfw2jpg.sfw` | recovered after in-memory JPEG reconstruction in ImageMagick |
| `raw\\cine\\sample_ffmpeg.cine` | recovered via bundled LibRaw sidecar |
| `image\\dpx\\sample_rawcooked.dpx` | unresolved: header declares 1664x384 DPX data, but the 342,629-byte file is truncated |
| `image\\erf\\sample1.erf` | unresolved: file content is not a supported RAW container; both ImageMagick and LibRaw reject it |
| `image\\pix\\sample_web.pix` | unresolved: header is not valid for ImageMagick's Alias/Wavefront PIX coder |
| `video\\cin\\sample_ffmpeg.cin` | unresolved by image-view intentionally: this is a Delphine video stream, not a Cineon bitmap |

The four remaining entries are retained as sample/content limitations rather
than launch failures. The `.cin` extension is shared by Cineon images and
Delphine videos, so reliable routing requires content detection or an explicit
viewer association.

## Sample-set update (2026-08-29)

Four valid Cineon image samples were added from
`Kimi_Agent_Cineon 样本获取.zip` to
`C:\Users\LYJ514328\Desktop\BaiduSyncdisk\abc\samples\image\cin`:

`checker.cin`, `gradient_10bit.cin`, `plasma.cin`, and `testbars.cin`.

All four files have the standard Cineon magic (`80 2A 5F D7`) and opened in the
current `image-view` package with `running_window`. The image-view sample set
contains 115 matched jobs. The original `video\\cin\\sample_ffmpeg.cin` remains
in place as a separate Delphine video sample.

## Current runtime verification (2026-08-29)

The staged ImageMagick runtime was rebuilt from the patched source (version
7.1.2-31) and isolated through `MAGICK_HOME`/module-path environment variables.
The SFW sample decodes successfully without a temporary file. The JXR, ORA, and
SFW plugin paths were also launched from the staged Windows MSVC build and each
created a responsive window.

Raw targeted results: `viewer-sample-test/results/20260829-135513/recheck-postfix-final.jsonl`.

## Full packaged scan follow-up (2026-08-29)

The packaged viewer scan covered 562 viewer/sample jobs across 649 samples.
For image-view, the 3-second pass reported 101 responsive windows, 16 slow
RAW/HEIF/JP2 jobs, and the four content failures above. A 12-second recheck
confirmed 15 of those slow jobs. The remaining RAF sample now also starts in
about 11 seconds after making LibRaw the first RAW decoder, so the current
image-view result is 117 responsive jobs out of 121, with only DPX, non-RAW ERF,
malformed PIX, and Delphine video `.cin` unresolved.

## Sample-set replacement and fix-pix recovery (2026-08-30)

The three problematic samples were replaced with real, valid files:

- `image\dpx\Digital_LAD_2048x1556.dpx` (replaced the truncated `sample_rawcooked.dpx`)
- `image\erf\RAW_EPSON_RD1.ERF` (replaced the non-RAW synthetic `sample1.erf`)
- `image\pix\abydos.pix` and `image\pix\example.pix` (replaced the malformed `sample_web.pix`)

The image-view runtime was rebuilt from the `fix-pix` ImageMagick release
(`plugins/img-view/build.bat`, SHA-256 `26C7E32C5D717596E2AA126A4C332968902B49E30B120A8134EDA393781B6CE0`).
All four replacement files now open in a responsive viewer window with a
12-second timeout. Together with the previously added Cineon samples, no
image-view sample remains unresolved except the intentional `.cin` Delphine
video, which is correctly left to a video viewer rather than image-view.

The same full scan found 491 responsive windows overall. The remaining
onlyoffice-view failures are concentrated in legacy Visio/WPS formats that
Document Builder returns as open-file errors; these are converter capability
limits rather than license or WebView2 startup failures. The complete scan and
the 12-second follow-up are recorded under
`viewer-sample-test/results/20260829-225810/`.

The latest MSVC image-view executable used for the RAW-order and JNG alpha-order
fixes has SHA-256
`CAE042D6D429DCCEB213041FF1095E085F1E26FE8B320739FBCB8DAEA03CA33D`.
