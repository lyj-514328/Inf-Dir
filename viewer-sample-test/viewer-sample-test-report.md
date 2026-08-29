# Viewer Sample Test Report

- Run: 20260829-225810
- Samples root: C:\Users\LYJ514328\Desktop\BaiduSyncdisk\abc\samples
- Dist root: C:\Users\LYJ514328\Desktop\WorkSpace\Inf-Dir\plugins\dist
- Samples discovered: 649
- Viewer/sample jobs: 562
- Ready timeout per job: 3s

## Classification

- running_window: the process created a responsive window before the timeout; native decoders generally parse the file before this point.
- content_error: a responsive window appeared, but the viewer reported a decode/open/initialization error for the sample.
- exit_nonzero: the viewer exited before creating a window with a non-zero code.
- exit_zero: the viewer exited before creating a window with code zero.
- running_no_window / hung / start_error: viewing could not be confirmed.
- WebView2 and Office viewers may show an in-window error without exiting; running_window confirms startup, not visual content acceptance.

## Overall

| Status | Count |
| --- | ---: |
| exit_nonzero | 45 |
| running_no_window | 26 |
| running_window | 491 |

## By Viewer

| Viewer | Declared samples | Responsive windows | Non-zero exits | Indeterminate |
| --- | ---: | ---: | ---: | ---: |
| inf-dir.archive-view | 35 | 32 | 3 | 0 |
| inf-dir.chm-view | 1 | 1 | 0 | 0 |
| inf-dir.code-view | 103 | 103 | 0 | 0 |
| inf-dir.email-view | 6 | 4 | 0 | 2 |
| inf-dir.font-view | 4 | 4 | 0 | 0 |
| inf-dir.image-view | 121 | 101 | 4 | 16 |
| inf-dir.markdown-view | 6 | 6 | 0 | 0 |
| inf-dir.mupdf-view | 14 | 14 | 0 | 0 |
| inf-dir.office-view | 13 | 13 | 0 | 0 |
| inf-dir.onlyoffice-view | 77 | 32 | 38 | 7 |
| inf-dir.pdfjs-view | 1 | 1 | 0 | 0 |
| inf-dir.pdf-view | 1 | 1 | 0 | 0 |
| inf-dir.project-view | 3 | 2 | 0 | 1 |
| inf-dir.video-view | 167 | 167 | 0 | 0 |
| inf-dir.web-view | 10 | 10 | 0 | 0 |

## Failures and anomalies

| Viewer | Declared format | Sample | Status | Exit code | Window title | Error output |
| --- | --- | --- | --- | ---: | --- | --- |
| inf-dir.archive-view | .arj | archive\arj\sample_web.arj | exit_nonzero | 0 |  | error: failed to open archive: Unrecognized archive format |
| inf-dir.archive-view | .dmg | archive\dmg\sample_web.dmg | exit_nonzero | 0 |  | error: failed to open archive: Unrecognized archive format |
| inf-dir.archive-view | .wim | archive\wim\sample_wimlib.wim | exit_nonzero | 0 |  | error: failed to open archive: Unrecognized archive format |
| inf-dir.email-view | .dat | document\dat\sample_targeted.dat | running_no_window | -1 |  |  |
| inf-dir.email-view | .msg | document\msg\sample_targeted.msg | running_no_window | -1 |  |  |
| inf-dir.image-view | .cr2 | image\cr2\sample1.cr2 | running_no_window | -1 |  |  |
| inf-dir.image-view | .dpx | image\dpx\sample_rawcooked.dpx | exit_nonzero | 0 |  | Error: failed to load image 鈥?native image decoder failed: The file extension `."dpx"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |
| inf-dir.image-view | .erf | image\erf\sample1.erf | exit_nonzero | 0 |  | Error: failed to load image 鈥?content decode failed: content sniff failed: The image format could not be determined; ImageMagick RAW decode failed: magick.exe: Unsupported file format or not RAW file `C:\Users\LYJ514328\Desktop\BaiduSyncdis ... |
| inf-dir.image-view | .heif | image\heif\sample1.heif | running_no_window | -1 |  |  |
| inf-dir.image-view | .jp2 | image\jp2\sample1.jp2 | running_no_window | -1 |  |  |
| inf-dir.image-view | .nrw | image\nrw\sample1.nrw | running_no_window | -1 |  |  |
| inf-dir.image-view | .orf | image\orf\sample1.orf | running_no_window | -1 |  |  |
| inf-dir.image-view | .pef | image\pef\sample1.pef | running_no_window | -1 |  |  |
| inf-dir.image-view | .pix | image\pix\sample_web.pix | exit_nonzero | 0 |  | Error: failed to load image 鈥?native image decoder failed: The file extension `."pix"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |
| inf-dir.image-view | .raf | image\raf\sample1.raf | running_no_window | -1 |  |  |
| inf-dir.image-view | .rw2 | image\rw2\sample1.rw2 | running_no_window | -1 |  |  |
| inf-dir.image-view | .cr3 | raw\cr3\sample_archive.cr3 | running_no_window | -1 |  |  |
| inf-dir.image-view | .cs1 | raw\cs1\sample_synthetic_d100.cs1 | running_no_window | -1 |  |  |
| inf-dir.image-view | .mos | raw\mos\sample_archive.mos | running_no_window | -1 |  |  |
| inf-dir.image-view | .rwl | raw\rwl\sample_archive.rwl | running_no_window | -1 |  |  |
| inf-dir.image-view | .sr2 | raw\sr2\sample_archive.sr2 | running_no_window | -1 |  |  |
| inf-dir.image-view | .srf | raw\srf\sample_archive.srf | running_no_window | -1 |  |  |
| inf-dir.image-view | .srw | raw\srw\sample_archive.srw | running_no_window | -1 |  |  |
| inf-dir.image-view | .sti | raw\sti\sample_archive.sti | running_no_window | -1 |  |  |
| inf-dir.image-view | .cin | video\cin\sample_ffmpeg.cin | exit_nonzero | 0 |  | Error: failed to load image 鈥?native image decoder failed: The file extension `."cin"` was not recognized as an image format; content decode failed: content sniff failed: The image format could not be determined; ImageMagick fallback failed ... |
| inf-dir.onlyoffice-view | .doc | document\doc\sample1.doc | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1: error: : open file error (89) |
| inf-dir.onlyoffice-view | .vdw | document\vdw\sample_targeted.vdw | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vdx | document\vdx\pronom_Visio2003-Sample1.vdx | running_no_window | -1 |  |  |
| inf-dir.onlyoffice-view | .vdx | document\vdx\sample_targeted.vdx | running_no_window | -1 |  |  |
| inf-dir.onlyoffice-view | .vsd | document\vsd\dan_Visio2002Test.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\dan_VisioTest.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio2000-Sample.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio2002-Sample1-v5.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio2002-Sample1.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio2003-Sample1-2002.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio2003-Sample1.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio4-Sample-v2.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio4-Sample-v3.vsd | running_no_window | -1 |  |  |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_Visio4-Sample.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_VisioDrawingv5-Sample.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\pronom_VisioDrawingv5-Sample2.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsd | document\vsd\sample_targeted.vsd | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vsdm | document\vsdm\sample_targeted.vsdm | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1: error: : open file error (88) |
| inf-dir.onlyoffice-view | .vsdx | document\vsdx\sample_targeted.vsdx | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1: error: : open file error (88) |
| inf-dir.onlyoffice-view | .vss | document\vss\dan_Visio2002Test.vss | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vss | document\vss\dan_VisioTest.vss | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio2002-Sample1-v5.vss | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio2002-Sample1.vss | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio2003-Sample1-2002.vss | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio2003-Sample1.vss | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio4-Sample-v2.vss | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio4-Sample-v3.vss | running_no_window | -1 |  |  |
| inf-dir.onlyoffice-view | .vss | document\vss\pronom_Visio4-Sample.vss | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vss | document\vss\sample_targeted.vss | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vssx | document\vssx\sample_targeted.vssx | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1: error: : open file error (88) |
| inf-dir.onlyoffice-view | .vst | document\vst\dan_Visio2002Test.vst | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vst | document\vst\dan_VisioTest.vst | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio2002-Sample1-v5.vst | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio2002-Sample1.vst | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio2003-Sample1-2002.vst | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio2003-Sample1.vst | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio4-Sample-v2.vst | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio4-Sample-v3.vst | running_no_window | -1 |  |  |
| inf-dir.onlyoffice-view | .vst | document\vst\pronom_Visio4-Sample.vst | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vst | document\vst\sample_targeted.vst | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.onlyoffice-view | .vstm | document\vstm\sample_targeted.vstm | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1: error: : open file error (88) |
| inf-dir.onlyoffice-view | .vstx | document\vstx\sample_targeted.vstx | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1: error: : open file error (88) |
| inf-dir.onlyoffice-view | .vsx | document\vsx\pronom_Visio2003-Sample1.vsx | running_no_window | -1 |  |  |
| inf-dir.onlyoffice-view | .vtx | document\vtx\pronom_Visio2003-Sample1.vtx | running_no_window | -1 |  |  |
| inf-dir.onlyoffice-view | .wps | document\wps\sample_sembiance.wps | exit_nonzero | 0 |  | [onlyoffice-view] conversion failed: docbuilder exited with status exit code: 1 |
| inf-dir.project-view | .mpp | document\mpp\sample_targeted.mpp | running_no_window | -1 |  |  |

Raw per-job results: C:\Users\LYJ514328\Desktop\WorkSpace\Inf-Dir\viewer-sample-test\results\20260829-225810\results.jsonl
