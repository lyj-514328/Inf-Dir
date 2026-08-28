# Viewer Sample Test Report

- Run: 20260828-141039
- Samples root: D:\BaiduNetdiskDownload\abc\samples
- Initial persisted records: 603
- Rechecked records: 22
- Manual override records: 1
- Final logical viewer/sample jobs: 604
- Responsive windows (including content errors): 597
- Responsive windows without an explicit viewer error: 484
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
| content_error | 113 |
| exit_nonzero | 7 |
| running_window | 484 |

## By Viewer

| Viewer | Declared samples | Responsive windows | Failures / content errors | Indeterminate |
| --- | ---: | ---: | ---: | ---: |
| inf-dir.archive-view | 35 | 32 | 3 | 0 |
| inf-dir.chm-view | 1 | 0 | 1 | 0 |
| inf-dir.code-view | 103 | 102 | 1 | 0 |
| inf-dir.email-view | 6 | 6 | 0 | 0 |
| inf-dir.font-view | 4 | 4 | 0 | 0 |
| inf-dir.image-view | 113 | 70 | 43 | 0 |
| inf-dir.markdown-view | 6 | 6 | 0 | 0 |
| inf-dir.mupdf-view | 14 | 14 | 0 | 0 |
| inf-dir.office-view | 13 | 13 | 0 | 0 |
| inf-dir.onlyoffice-view | 77 | 8 | 69 | 0 |
| inf-dir.pdfjs-view | 1 | 1 | 0 | 0 |
| inf-dir.pdf-view | 1 | 1 | 0 | 0 |
| inf-dir.project-view | 3 | 0 | 3 | 0 |
| inf-dir.text-view | 41 | 41 | 0 | 0 |
| inf-dir.video-view | 176 | 176 | 0 | 0 |
| inf-dir.web-view | 10 | 10 | 0 | 0 |

## Failures and anomalies

| Viewer | Declared format | Sample | Status | Exit code | Verification | Error output |
| --- | --- | --- | --- | ---: | --- | --- |
| inf-dir.archive-view | .arj | archive\arj\sample_web.arj | exit_nonzero |  | recheck_12s | error: failed to open archive: Unrecognized archive format |
| inf-dir.archive-view | .dmg | archive\dmg\sample_web.dmg | content_error | -1 | initial | error: failed to open archive: Unrecognized archive format |
| inf-dir.archive-view | .wim | archive\wim\sample_wimlib.wim | content_error | -1 | recheck_12s | error: failed to open archive: Unrecognized archive format |
| inf-dir.chm-view | .chm | document\chm\sample_web.chm | content_error | -1 | manual_20260828 | Manual verification: Unexpected ITSF GUIDs: {00000000-0000-0000-0000-000000000000} / {00000060-0000-0000-0000-000000000000} |
| inf-dir.code-view | .ads | code\ads\sample_targeted.ads | content_error | -1 | initial | [code-view] failed to initialize WebView2: WebView2 error: WindowsError(Error { code: HRESULT(0x800700AA), message: "请求的资源在使用中。" }) |
| inf-dir.image-view | .cr2 | image\cr2\sample1.cr2 | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .dng | image\dng\sample1.dng | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .dpx | image\dpx\sample_rawcooked.dpx | content_error | -1 | initial | Error: failed to load image 鈥?native image decoder failed: The file extension `."dpx"` was not recognized as an image format; ImageMagick fallback failed: magick.exe: unable to read image data `D:\BaiduNetdiskDownload\abc\samples\image\dpx\ ... |
| inf-dir.image-view | .erf | image\erf\sample1.erf | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: Unsupported fi ... |
| inf-dir.image-view | .heif | image\heif\sample1.heif | content_error | -1 | initial | Error: failed to load image 鈥?native image decoder failed: The file extension `."heif"` was not recognized as an image format; ImageMagick fallback failed: ImageMagick exited with exit code: 0xffffffff |
| inf-dir.image-view | .jng | image\jng\sample_libpng_jdaa.jng | content_error | -1 | initial | Error: failed to load image 鈥?native image decoder failed: The file extension `."jng"` was not recognized as an image format; ImageMagick fallback failed: magick.exe: Invalid bit depth in IHDR `C:/Users/lyjia/AppData/Local/Temp/magick-yRVJJ ... |
| inf-dir.image-view | .jp2 | image\jp2\sample1.jp2 | content_error | -1 | initial | Error: failed to load image 鈥?native image decoder failed: The file extension `."jp2"` was not recognized as an image format; ImageMagick fallback failed: ImageMagick exited with exit code: 0xffffffff |
| inf-dir.image-view | .jxr | image\jxr\sample_nomacs.jxr | content_error | -1 | initial | Error: failed to load image 鈥?native image decoder failed: The file extension `."jxr"` was not recognized as an image format; ImageMagick fallback failed: '"JXRDecApp.exe"' is not recognized as an internal or external command, operable prog ... |
| inf-dir.image-view | .mvg | image\mvg\sample_sembiance.mvg | content_error | -1 | initial | Error: failed to load image 鈥?native image decoder failed: The file extension `."mvg"` was not recognized as an image format; ImageMagick fallback failed: magick.exe: no decode delegate for this image format `D:\BaiduNetdiskDownload\abc\sam ... |
| inf-dir.image-view | .nef | image\nef\sample1.nef | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .nrw | image\nrw\sample1.nrw | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .ora | image\ora\sample_orajs.ora | content_error | -1 | initial | Error: failed to load image 鈥?native image decoder failed: The file extension `."ora"` was not recognized as an image format; ImageMagick fallback failed: magick.exe: unable to open file 'D:\BaiduNetdiskDownload\abc\samples\image\ora\sample ... |
| inf-dir.image-view | .orf | image\orf\sample1.orf | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .pal | image\pal\sample_graphicex.pal | content_error | -1 | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."pal"` was not recognized as an image format; ImageMagick fallback failed: magick.exe: must specify image size `D:\BaiduNetdiskDownload\abc\samples\image\pal\sa ... |
| inf-dir.image-view | .pef | image\pef\sample1.pef | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .pix | image\pix\sample_web.pix | content_error | -1 | initial | Error: failed to load image 鈥?native image decoder failed: The file extension `."pix"` was not recognized as an image format; ImageMagick fallback failed: magick.exe: improper image header `D:\BaiduNetdiskDownload\abc\samples\image\pix\samp ... |
| inf-dir.image-view | .ptx | image\ptx\sample_web.ptx | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: no decode dele ... |
| inf-dir.image-view | .rw2 | image\rw2\sample1.rw2 | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .sfw | image\sfw\sample_sfw2jpg.sfw | content_error | -1 | initial | Error: failed to load image 鈥?native image decoder failed: The file extension `."sfw"` was not recognized as an image format; ImageMagick fallback failed: magick.exe: unable to create temporary file 'C:/Users/lyjia/AppData/Local/Temp/magick ... |
| inf-dir.image-view | .ari | raw\ari\sample_archive.ari | content_error | -1 | recheck_12s | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: no decode dele ... |
| inf-dir.image-view | .arw | raw\arw\sample_archive.arw | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .bay | raw\bay\sample_synthetic_d100.bay | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: no decode dele ... |
| inf-dir.image-view | .cine | raw\cine\sample_ffmpeg.cine | content_error | -1 | initial | Error: failed to load image 鈥?native image decoder failed: The file extension `."cine"` was not recognized as an image format; ImageMagick fallback failed: magick.exe: improper image header `D:\BaiduNetdiskDownload\abc\samples\raw\cine\samp ... |
| inf-dir.image-view | .cr3 | raw\cr3\sample_archive.cr3 | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .crw | raw\crw\sample_archive.crw | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .cs1 | raw\cs1\sample_synthetic_d100.cs1 | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .dcr | raw\dcr\sample_archive.dcr | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .ia | raw\ia\sample_synthetic_d100.ia | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: no decode dele ... |
| inf-dir.image-view | .iiq | raw\iiq\sample_archive.iiq | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .kc2 | raw\kc2\sample_dcs200_f14.kc2 | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: no decode dele ... |
| inf-dir.image-view | .kc2 | raw\kc2\sample_synthetic_d100.kc2 | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: no decode dele ... |
| inf-dir.image-view | .mef | raw\mef\sample_archive.mef | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .mos | raw\mos\sample_archive.mos | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .pxn | raw\pxn\sample_synthetic_d100.pxn | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: no decode dele ... |
| inf-dir.image-view | .qtk | raw\qtk\sample_quicktake150.qtk | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: no decode dele ... |
| inf-dir.image-view | .raw | raw\raw\sample_archive.raw | content_error | -1 | recheck_12s | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: Unsupported fi ... |
| inf-dir.image-view | .rdc | raw\rdc\sample_synthetic_d100.rdc | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: no decode dele ... |
| inf-dir.image-view | .rwl | raw\rwl\sample_archive.rwl | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .sr2 | raw\sr2\sample_archive.sr2 | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .srf | raw\srf\sample_archive.srf | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .srw | raw\srw\sample_archive.srw | content_error | -1 | initial | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: ImageMagick exited with ex ... |
| inf-dir.image-view | .x3f | raw\x3f\sample_archive.x3f | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?LibRaw RAW decode failed: runtime is missing: C:\Users\lyjia\Desktop\Workspace\Inf-Dir2\plugins\dist\inf-dir.image-view\libraw-decoder\libraw-decoder.exe; ImageMagick fallback failed: magick.exe: Unsupported fi ... |
| inf-dir.image-view | .cin | video\cin\sample_ffmpeg.cin | exit_nonzero |  | recheck_12s | Error: failed to load image 鈥?native image decoder failed: The file extension `."cin"` was not recognized as an image format; ImageMagick fallback failed: magick.exe: improper image header `D:\BaiduNetdiskDownload\abc\samples\video\cin\samp ... |
| inf-dir.onlyoffice-view | .doc | document\doc\sample1.doc | content_error | -1 | initial | [onlyoffice-view] conversion failed: failed to start x2t: 拒绝访问。 (os error 5) |
| inf-dir.onlyoffice-view | .docm | document\docm\sample_web.docm | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .docx | document\docx\sample1.docx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .dot | document\dot\sample_web.dot | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .dotm | document\dotm\sample_web.dotm | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .dotx | document\dotx\sample_web.dotx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .odp | document\odp\sample1.odp | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .odt | document\odt\sample1.odt | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .ott | document\ott\sample1.ott | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .potm | document\potm\sample_web.potm | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .potx | document\potx\sample_web.potx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .ppt | document\ppt\sample1.ppt | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .pptm | document\pptm\sample_web.pptm | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .pptx | document\pptx\sample_web.pptx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .rtf | document\rtf\sample1.rtf | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vdw | document\vdw\sample_targeted.vdw | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vdx | document\vdx\dan_VisioTest.vdx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vdx | document\vdx\pronom_Visio2002-Sample1.vdx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vdx | document\vdx\pronom_Visio2003-Sample1.vdx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vdx | document\vdx\sample_targeted.vdx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\dan_Visio2002Test.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\dan_VisioTest.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio2000-Sample.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio2002-Sample1.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio2002-Sample1-v5.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio2003-Sample1.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio2003-Sample1-2002.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio4-Sample.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio4-Sample-v2.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio4-Sample-v3.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 0xc0000374 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_VisioDrawingv5-Sample.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_VisioDrawingv5-Sample2.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\sample_targeted.vsd | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vsdm | document\vsdm\sample_targeted.vsdm | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vsdx | document\vsdx\sample_targeted.vsdx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vss | document\vss\dan_Visio2002Test.vss | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vss | document\vss\dan_VisioTest.vss | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio2002-Sample1.vss | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio2002-Sample1-v5.vss | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio2003-Sample1.vss | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio2003-Sample1-2002.vss | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio4-Sample.vss | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio4-Sample-v2.vss | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vss | document\vss\sample_targeted.vss | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vssx | document\vssx\sample_targeted.vssx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vst | document\vst\dan_Visio2002Test.vst | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vst | document\vst\dan_VisioTest.vst | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio2002-Sample1.vst | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio2002-Sample1-v5.vst | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio2003-Sample1.vst | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio2003-Sample1-2002.vst | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio4-Sample.vst | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio4-Sample-v2.vst | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vst | document\vst\sample_targeted.vst | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .vstm | document\vstm\sample_targeted.vstm | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vstx | document\vstx\sample_targeted.vstx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vsx | document\vsx\dan_VisioTest.vsx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vsx | document\vsx\pronom_Visio2002-Sample1.vsx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vsx | document\vsx\pronom_Visio2003-Sample1.vsx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vsx | document\vsx\sample_targeted.vsx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vtx | document\vtx\dan_VisioTest.vtx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vtx | document\vtx\pronom_Visio2002-Sample1.vtx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .vtx | document\vtx\pronom_Visio2003-Sample1.vtx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .wbk | document\wbk\sample_web.wbk | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .wps | document\wps\sample_sembiance.wps | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 88 |
| inf-dir.onlyoffice-view | .pot | presentation\pot\sample_web.pot | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .pps | presentation\pps\sample_web.pps | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .ppsx | presentation\ppsx\sample_web.ppsx | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.onlyoffice-view | .mht | web\mht\sample_web.mht | content_error | -1 | initial | [onlyoffice-view] conversion failed: x2t exited with status exit code: 80 |
| inf-dir.project-view | .mpp | document\mpp\sample_targeted.mpp | exit_nonzero |  | recheck_12s | Unhandled exception. System.InvalidOperationException: SplitterDistance ������ Panel1MinSize �� Width - Panel2MinSize ֮�䡣    at System.Windows.Forms.SplitContainer.set_SplitterDistance(Int32 value)    at System.Windows.Forms.SplitContainer. ... |
| inf-dir.project-view | .mpt | document\mpt\sample_targeted.mpt | exit_nonzero |  | recheck_12s | Unhandled exception. System.InvalidOperationException: SplitterDistance ������ Panel1MinSize �� Width - Panel2MinSize ֮�䡣    at System.Windows.Forms.SplitContainer.set_SplitterDistance(Int32 value)    at System.Windows.Forms.SplitContainer. ... |
| inf-dir.project-view | .mpx | document\mpx\sample_targeted.mpx | exit_nonzero |  | recheck_12s | Unhandled exception. System.InvalidOperationException: SplitterDistance ������ Panel1MinSize �� Width - Panel2MinSize ֮�䡣    at System.Windows.Forms.SplitContainer.set_SplitterDistance(Int32 value)    at System.Windows.Forms.SplitContainer. ... |

Raw per-job results: viewer-sample-test\results\20260828-141039\results.jsonl
Recheck results: viewer-sample-test\results\20260828-141039\recheck.jsonl
Recheck results: viewer-sample-test\results\20260828-141039\recheck-failures.jsonl
Manual verification overrides: viewer-sample-test\results\20260828-141039\manual-overrides.jsonl
