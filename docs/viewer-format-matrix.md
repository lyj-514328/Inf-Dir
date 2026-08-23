# Inf-Dir Viewer 格式总表

> 本表为 Quick View 格式覆盖的**唯一追踪表**，替代原 `docs/viewer-format-roadmap.md`。
> 数据源：`docs/file-type-reference/`（File Viewer Plus，FVP）与
> `docs/uvviewer-formats/`（Universal Viewer，UV）。同名不同义的后缀分多行列出
> （如 `.dat`：Winmail 邮件 / VCD 视频；`.cin`：Cineon 位图 / Delphine 视频）。
>
> 状态列图例：
> - `✅` 已支持（同时给出 viewer 与命中方式：扩展名/文件名规则或 MIME 子类）；
> - `🔮` 依赖更强的内容/MIME 嗅探器（规则体系已就绪，嗅探器上线后自动命中）；
> - `⚠️` 后端可解但未在配置声明（待实测后补 manifest 与默认配置）；
> - `❌` 后端无对应能力或非文件类型（伪格式、网络协议、原始采样流、字幕等）。
>
> 支持面判定依据（image-view 的解码链：image crate → Windows WIC 子进程 →
> ImageMagick 子进程；video-view：mpv/FFmpeg）：
> - FFmpeg `libavformat/allformats.c` 的 368 个 demuxer（对应 shinchiro `mpv-dev`
>   全量构建）；
> - ImageMagick 实测 `magick -list format` 输出；
> - Windows WIC：系统内置 codec（JXR、HEIF[+扩展]、WMF/EMF、DIB 等），优先于
>   ImageMagick 兜底；其中 Raw Image Decoder 注册了 `.BAY` `.PXN` `.PTX` 等相机 RAW
>   后缀（`wic-decoder --list` 实测），超出 ImageMagick 能力评估范围，
>   随 OS 版本/厂商 codec 安装情况浮动，不作为覆盖判定的确定性依据。
>
> RAW 清单考古（dcraw 体系）：UV 的 RAW 扩展名清单（36 项）是 dcraw 2003 年前后
> 扩展名表的快照，含早已被删除的后缀——`.bmq` 为 Nucore 相机 RAW（dcraw 2003-05-29
> 添加，2007-04-29 以 "not used outside Nucore" 为由移除；另有 Re-Volt 游戏
> mipmap 纹理的同名语义，与相机格式无关），`.rdc` 为 Rollei 相机 RAW（2003-09-15
> 添加，后被移除），`.cs1` 在 dcraw 9.28 识别表中仍保留而 LibRaw 未继承。
> 依据：LibRaw 论坛帖 <https://www.libraw.org/node/2152> 与 ncruces/dcraw 全历史
> （commit `01bf793` / `2bc1e21` / `773559d`）。
>
> 注：无扩展名规则的文件可能经 `image/*`、`video/*`、`audio/*`、`text/*`
> MIME 兜底命中（依赖系统注册的 Content Type 与后端解码能力）；同名冲突后缀的
> 常见语义作为默认 viewer、其余语义作为 MIME 子类表达。
>
> **本表手工维护**：格式说明沿用两份参考清单的命名，同义重复（如
> "Plain Text File / Plain text files"）已酌情精简；后续修正直接编辑本文件。
> 类别按使用语义整理：**Text**（纯文本，已并入 Source Code，由 code-view 统一处理）、
> **Documents**（编辑型/字处理文档）、
> **Page Documents**（页面式文档：PDF/XPS/DjVu，固定排版或扫描件）、
> **eBooks**（可重排电子书：EPUB/MOBI/FB2 系）。
>
> 同名不同义/双语义的后缀（按参考清单分多行列出）：
- `.vst`：Visio（Visio Drawing Template）；Image（Truevision image）
- `.dat`：Email（Winmail.dat File）；Video（VCD Video File）
- `.cdg`：Image（CD Graphics File）；Video（CD Graphics Format）
- `.cin`：Image（Kodak Cineon Bitmap File）；Video（Delphine Software CIN Video）
- `.gif`：Image（Graphical Interchange Format File / Compuserve GIF image）；Video（GIF Animation）
- `.psp`：Image（Paintshop Pro image）；Video（PSP MP4 format）
- `.iss`：Audio（Funcom ISS Audio File / Funcom ISS format）；Source Code（Inno Setup Script）
- `.mpc`：Audio（Musepack Compressed Audio File）；Video（Electronic Arts MPCh Video File / Musepack）
- `.vb`：Video（Beam Game SIFF Video）；Source Code（VBScript File）
- `.vhd`：Archive（Virtual Hard Disk File）；Source Code（VHDL File）

| 类别 | 后缀名 | 格式说明 | 是否支持，如何支持 |
| --- | --- | --- | --- |
| Documents | .chm | Compiled HTML Help File / Microsoft HTML Help | ✅ chm（扩展名规则） |
| Documents | .doc | Microsoft Word Document (Legacy) / Microsoft Word | ✅ onlyoffice（扩展名规则） |
| Documents | .docm | Microsoft Word Macro-Enabled Document / Microsoft Word 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Documents | .docx | Microsoft Word Document / Microsoft Word 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Documents | .dot | Microsoft Word Document Template / Microsoft Word | ✅ onlyoffice（扩展名规则） |
| Documents | .dotm | Microsoft Word Macro-Enabled Document Template / Microsoft Word 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Documents | .dotx | Microsoft Word Document Template / Microsoft Word 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Documents | .odt | OpenDocument Text Document | ✅ onlyoffice（扩展名规则） |
| Documents | .ott | OpenDocument Document Template | ✅ onlyoffice（扩展名规则） |
| Documents | .rtf | Rich Text Format File / Rich Text Format | ✅ onlyoffice（扩展名规则） |
| Documents | .wbk | Microsoft Word backup | ✅ onlyoffice（扩展名规则） |
| Documents | .wps | Microsoft Works Word Processor Document | ✅ onlyoffice（扩展名规则） |
| eBooks | .epub | EPUB eBook | ✅ mupdf（扩展名规则） |
| eBooks | .fb2 | FictionBook e-book | ✅ mupdf（扩展名规则） |
| eBooks | .fb2z | FictionBook e-book | ✅ mupdf（扩展名规则） |
| eBooks | .fbz | FictionBook e-book | ✅ mupdf（扩展名规则） |
| eBooks | .mobi | Mobipocket e-book | ✅ mupdf（扩展名规则） |
| eBooks | .tcr | TCR e-book | ✅ mupdf（扩展名规则） |
| Page Documents | .oxps | Open XML Paper Specification File | ✅ mupdf（扩展名规则） |
| Page Documents | .pdf | Portable Document Format File / Adobe Portable Document Format | ✅ pdf、pdfjs（扩展名规则） |
| Page Documents | .xps | XML Paper Specification File / Microsoft XML Paper Specification | ✅ mupdf（扩展名规则） |
| Page Documents | .djvu | DejaVu document | ✅ mupdf（扩展名规则） |
| Page Documents | .djv | DejaVu document | ✅ mupdf（扩展名规则） |
| Spreadsheet | .csv | Comma Separated Values File | ✅ code（扩展名规则） |
| Spreadsheet | .tsv | Tab Separated Values File | ✅ code（扩展名规则） |
| Spreadsheet | .xls | Excel Spreadsheet (Legacy) / Microsoft Excel | ✅ onlyoffice（扩展名规则） |
| Spreadsheet | .xlsm | Excel Macro-Enabled Spreadsheet | ✅ office、onlyoffice（扩展名规则） |
| Spreadsheet | .xlsx | Excel Spreadsheet / Microsoft Excel 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Spreadsheet | .xlt | Excel Spreadsheet Template / Microsoft Excel | ✅ onlyoffice（扩展名规则） |
| Spreadsheet | .xltm | Excel Macro-Enabled Spreadsheet Template | ✅ office、onlyoffice（扩展名规则） |
| Spreadsheet | .xltx | Excel Spreadsheet Template / Microsoft Excel 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Presentation | .odp | OpenDocument Presentation | ✅ onlyoffice（扩展名规则） |
| Presentation | .pot | PowerPoint Template | ✅ onlyoffice（扩展名规则） |
| Presentation | .potm | PowerPoint Macro-Enabled Presentation Template | ✅ office、onlyoffice（扩展名规则） |
| Presentation | .potx | PowerPoint Template | ✅ office、onlyoffice（扩展名规则） |
| Presentation | .pps | PowerPoint Slide Show | ✅ onlyoffice（扩展名规则） |
| Presentation | .ppsx | PowerPoint Slide Show | ✅ office、onlyoffice（扩展名规则） |
| Presentation | .ppt | PowerPoint Presentation (Legacy) | ✅ onlyoffice（扩展名规则） |
| Presentation | .pptm | PowerPoint Macro-Enabled Presentation | ✅ office、onlyoffice（扩展名规则） |
| Presentation | .pptx | PowerPoint Presentation | ✅ office、onlyoffice（扩展名规则） |
| Visio | .vdw | Visio Web Drawing | ✅ onlyoffice（扩展名规则） |
| Visio | .vdx | Visio Drawing XML File | ✅ onlyoffice（扩展名规则） |
| Visio | .vsd | Visio Drawing | ✅ onlyoffice（扩展名规则） |
| Visio | .vsdm | Visio Macro-Enabled Drawing | ✅ onlyoffice（扩展名规则） |
| Visio | .vsdx | Visio Drawing | ✅ onlyoffice（扩展名规则） |
| Visio | .vss | Visio Stencils File | ✅ onlyoffice（扩展名规则） |
| Visio | .vssx | Visio Stencils File | ✅ onlyoffice（扩展名规则） |
| Visio | .vst | Visio Drawing Template | ✅ onlyoffice（扩展名规则） |
| Visio | .vstm | Visio Macro-Enabled Drawing Template | ✅ onlyoffice（扩展名规则） |
| Visio | .vstx | Visio Drawing Template | ✅ onlyoffice（扩展名规则） |
| Visio | .vsx | Visio Stencil XML File | ✅ onlyoffice（扩展名规则） |
| Visio | .vtx | Visio Template XML File | ✅ onlyoffice（扩展名规则） |
| Project | .mpp | Microsoft Project File | ✅ project（扩展名规则） |
| Project | .mpt | Microsoft Project Template | ✅ project（扩展名规则） |
| Project | .mpx | Microsoft Project Exchange File | ✅ project（扩展名规则） |
| CAD | .dwg | AutoCAD Drawing | ✅ mupdf（扩展名规则） |
| CAD | .dxf | Drawing Exchange Format File | ✅ mupdf（扩展名规则） |
| Email | .dat | Winmail.dat File | ✅ email（扩展名规则） |
| Email | .eml | Apple Mail Message | ✅ email（扩展名规则） |
| Email | .emlx | Apple Mail Message | ✅ email（扩展名规则） |
| Email | .msg | Outlook Mail Message | ✅ email（扩展名规则） |
| Email | .oft | Outlook Email Template | ✅ email（扩展名规则） |
| Image | .aai | Dune HD Image | ✅ image（扩展名规则） |
| Image | .ani | Windows animated cursor | ❌ WIC/ImageMagick 无对应 codec；Windows 光标 API（GDI）可读，image-view 未接入（待评估） |
| Image | .apng | Animated PNG File | ✅ video（扩展名规则） |
| Image | .avif | AVIF Image | ✅ image（扩展名规则） |
| Image | .bmp | Bitmap Image File / Windows bitmap | ✅ image（扩展名规则） |
| Image | .bw | BW File / SGI image | ✅ image（扩展名规则） |
| Image | .cdg | CD Graphics File | ✅ video（扩展名规则） |
| Image | .cel | Autodesk image | ❌ ImageMagick 无对应 decoder |
| Image | .cin | Kodak Cineon Bitmap File | ✅ image（扩展名规则） |
| Image | .cur | Windows Cursor / Windows cursor | ✅ image（扩展名规则） |
| Image | .cut | Dr. Halo image | ⚠️ ImageMagick 可解，未在配置声明（待实测） |
| Image | .dcm | DICOM Image | ✅ image（扩展名规则） |
| Image | .dds | DirectDraw Surface | ✅ image（扩展名规则） |
| Image | .dfont | Mac OS X Data Fork Font | ✅ font（扩展名规则） |
| Image | .dib | Device Independent Bitmap File / Windows bitmap | ✅ image（扩展名规则） |
| Image | .dpx | Digital Picture Exchange File | ✅ image（扩展名规则） |
| Image | .emf | Enhanced Windows Metafile / Windows enhanced metafile | ✅ image（扩展名规则） |
| Image | .emz | Compressed Enhanced Metafile | ⚠️ gzip 压缩的 EMF；ImageMagick EMF 渲染器已就绪，image-view 未做解压包装（低成本可支持） |
| Image | .exr | OpenExr Image | ✅ image（扩展名规则） |
| Image | .fax | GFI fax image | ✅ image（扩展名规则） |
| Image | .gif | Graphical Interchange Format File / Compuserve GIF image | ✅ image、video（扩展名规则） |
| Image | .heic | High Efficiency Image Format | ✅ image（扩展名规则） |
| Image | .icb | Truevision image | ⚠️ ImageMagick 可解，未在配置声明（待实测） |
| Image | .icl | Windows icon library | ❌ WIC/ImageMagick 无对应 codec；Windows 图标资源 API（GDI）可读，image-view 未接入（待评估） |
| Image | .ico | Icon File / Windows icon | ✅ image（扩展名规则） |
| Image | .jfif | JPEG format | ✅ image（扩展名规则） |
| Image | .jls | JPEG-LS Image | ❌ ImageMagick 无对应 decoder |
| Image | .jng | JPEG Network Graphic | ✅ image（扩展名规则） |
| Image | .jp2 | JPEG 2000 Core Image File / JPEG 2000 format | ✅ image（扩展名规则） |
| Image | .jpc | JPEG 2000 format | ✅ image（扩展名规则） |
| Image | .jpe | JPEG format | ✅ image（扩展名规则） |
| Image | .jpeg | JPEG format | ✅ image（扩展名规则） |
| Image | .jpg | JPEG Image / JPEG format | ✅ image（扩展名规则） |
| Image | .jxl | JPEG XL Image | ✅ image（扩展名规则） |
| Image | .jxr | JPEG XR Image | ✅ image（扩展名规则） |
| Image | .miff | Magick Image File | ✅ image（扩展名规则） |
| Image | .mvg | Magick Vector Graphics File | ✅ image（扩展名规则） |
| Image | .ora | OpenRaster Image | ✅ image（扩展名规则） |
| Image | .pal | Dr. Halo image | ⚠️ ImageMagick 可解，未在配置声明（待实测） |
| Image | .pbm | Portable Bitmap Image / Portable pixmap | ✅ image（扩展名规则） |
| Image | .pcc | ZSoft Paintbrush image | ❌ ImageMagick 无对应 decoder |
| Image | .pcd | Kodak Photo CD Image File / Kodak Photo-CD image | ✅ image（扩展名规则） |
| Image | .pcx | Paintbrush Bitmap Image File / ZSoft Paintbrush image | ✅ image（扩展名规则） |
| Image | .pdd | Photoshop image | ❌ ImageMagick 无对应 decoder |
| Image | .pes | Brother Embroidery Format | ✅ image（扩展名规则） |
| Image | .pgm | Portable Gray Map Image / Portable pixmap | ✅ image（扩展名规则） |
| Image | .pic | Pictor Paint Image / Autodesk image | ❌ ImageMagick 无对应 decoder |
| Image | .pix | BRender PIX Image | ✅ image（扩展名规则） |
| Image | .png | Portable Network Graphic | ✅ image（扩展名规则） |
| Image | .pnm | Portable AnyMap Image / Portable pixmap | ✅ image（扩展名规则） |
| Image | .ppm | Portable Pixmap Image File / Portable pixmap | ✅ image（扩展名规则） |
| Image | .psb | Adobe Photoshop Large Document Format | ✅ image（扩展名规则） |
| Image | .psd | Adobe Photoshop Document / Photoshop image | ✅ image（扩展名规则） |
| Image | .psp | Paintshop Pro image | ❌ ImageMagick 无对应 decoder |
| Image | .ptx | V.Flash PTX Image | ❌ ImageMagick 无对应 decoder（同名 `.ptx` 的 Pentax RAW 语义已支持，见 RAW 段） |
| Image | .ras | SunOS Unix raster format | ✅ image（扩展名规则） |
| Image | .rgb | RGB Bitmap / SGI image | ✅ image（扩展名规则） |
| Image | .rgba | SGI image | ⚠️ ImageMagick 可解，未在配置声明（待实测） |
| Image | .rla | SGI Wavefront image | ✅ image（扩展名规则） |
| Image | .rle | Windows bitmap | ✅ image（扩展名规则） |
| Image | .rpf | SGI Wavefront image | ❌ ImageMagick 无对应 decoder |
| Image | .sfw | Seattle FilmWorks Image | ✅ image（扩展名规则） |
| Image | .sgi | Silicon Graphics Image File / SGI image | ✅ image（扩展名规则） |
| Image | .svg | Scalable Vector Graphics File | ✅ image、web、code（扩展名规则） |
| Image | .svgz | Compressed SVG File | ✅ image、web（扩展名规则） |
| Image | .tga | Targa Graphic / TrueVision Targa | ✅ image（扩展名规则） |
| Image | .tif | Tagged Image File Format | ✅ image（扩展名规则） |
| Image | .tiff | Tagged Image File / Tagged Image File Format | ✅ image（扩展名规则） |
| Image | .ttf | TrueType Font | ✅ font（扩展名规则） |
| Image | .txd | Renderware Texture Dictionary / Renderware TeXture Dictionary | ❌ ImageMagick 无对应 decoder |
| Image | .vda | Truevision image | ⚠️ ImageMagick 可解，未在配置声明（待实测） |
| Image | .vst | Truevision image | 🔮 默认 .vst 规则为 Visio 模板（onlyoffice）；Truevision 图像属 MIME/内容嗅探子类，待嗅探器 |
| Image | .wbmp | Wireless Bitmap Image File | ✅ image（扩展名规则） |
| Image | .webp | WebP Image | ✅ image（扩展名规则） |
| Image | .win | Truevision image | ❌ ImageMagick 无对应 decoder |
| Image | .wmf | Windows Metafile / Windows metafile | ✅ image（扩展名规则） |
| Image | .wmz | Compressed Windows Metafile | ⚠️ gzip 压缩的 WMF；ImageMagick WMF 渲染器已就绪，image-view 未做解压包装（低成本可支持） |
| Image | .xbm | X11 Bitmap Graphic | ✅ image（扩展名规则） |
| Image | .xface | X-Face Image | ✅ image（扩展名规则） |
| Image | .xpm | X11 Pixmap Graphic | ✅ image（扩展名规则） |
| RAW | .3fr | Hasselblad 3F Raw Image / 3fr | ✅ image（扩展名规则） |
| RAW | .ari | ARRIRAW Image | ✅ image（扩展名规则） |
| RAW | .arw | Sony Digital Camera Image / arw | ✅ image（扩展名规则） |
| RAW | .bay | Casio Raw Image / bay | ✅ image（扩展名规则；系统 WIC Raw Image Decoder，`wic-decoder --list` 实测注册 `.BAY`） |
| RAW | .bmq | bmq | ❌ WIC/ImageMagick 无对应 coder |
| RAW | .cine | cine | ✅ image（扩展名规则） |
| RAW | .cr2 | Canon Raw Image File / cr2 | ✅ image（扩展名规则） |
| RAW | .cr3 | Canon Raw 3 Image File | ✅ image（扩展名规则） |
| RAW | .crw | Canon Raw CIFF Image File / crw | ✅ image（扩展名规则） |
| RAW | .cs1 | cs1 | ❌ WIC/ImageMagick 无对应 coder |
| RAW | .dc2 | dc2 | ❌ WIC/ImageMagick 无对应 coder |
| RAW | .dcr | Kodak Raw Image File / dcr | ✅ image（扩展名规则） |
| RAW | .dng | Digital Negative Image File / dng | ✅ image（扩展名规则） |
| RAW | .erf | Epson Raw File / erf | ✅ image（扩展名规则） |
| RAW | .fff | Hasselblad Raw Image / fff | ✅ image（扩展名规则） |
| RAW | .hdr | hdr | ✅ image（扩展名规则） |
| RAW | .ia | ia | ❌ WIC/ImageMagick 无对应 coder |
| RAW | .iiq | Phase One Raw Image | ✅ image（扩展名规则） |
| RAW | .k25 | k25 | ✅ image（扩展名规则） |
| RAW | .kc2 | Kodak DCS200 Camera Raw Image / kc2 | ❌ WIC/ImageMagick 无对应 coder |
| RAW | .kdc | Kodak Digital Camera Image / kdc | ✅ image（扩展名规则） |
| RAW | .mdc | Minolta Camera Raw Image / mdc | ✅ image（扩展名规则） |
| RAW | .mef | Mamiya Raw Image / mef | ✅ image（扩展名规则） |
| RAW | .mos | Leaf Camera Raw File / mos | ✅ image（扩展名规则） |
| RAW | .mrw | Minolta Raw Image File / mrw | ✅ image（扩展名规则） |
| RAW | .nef | Nikon Electronic Format RAW Image / nef | ✅ image（扩展名规则） |
| RAW | .nrw | Nikon Raw Image File / nrw | ✅ image（扩展名规则） |
| RAW | .orf | Olympus Raw File / orf | ✅ image（扩展名规则） |
| RAW | .pef | Pentax Electronic File / pef | ✅ image（扩展名规则） |
| RAW | .ptx | Pentax RAW / ptx | ✅ image（扩展名规则；系统 WIC Raw Image Decoder，`wic-decoder --list` 实测注册 `.PTX`；同名 V.Flash 图像语义见 Image 段） |
| RAW | .pxn | pxn | ✅ image（扩展名规则；系统 WIC Raw Image Decoder，`wic-decoder --list` 实测注册 `.PXN`） |
| RAW | .qtk | qtk | ❌ WIC/ImageMagick 无对应 coder |
| RAW | .raf | Fuji Raw Image File / raf | ✅ image（扩展名规则） |
| RAW | .raw | Raw Image Data File / raw | ✅ image（扩展名规则） |
| RAW | .rdc | rdc | ❌ WIC/ImageMagick 无对应 coder |
| RAW | .rw2 | Panasonic Raw Image / rw2 | ✅ image（扩展名规则） |
| RAW | .rwl | Leica Raw Image | ✅ image（扩展名规则） |
| RAW | .sr2 | Sony Raw Image / sr2 | ✅ image（扩展名规则） |
| RAW | .srf | Sony Raw Image / srf | ✅ image（扩展名规则） |
| RAW | .srw | Samsung Raw Image | ✅ image（扩展名规则） |
| RAW | .sti | sti | ⚠️ ImageMagick 可解，未在配置声明（待实测） |
| RAW | .x3f | SIGMA X3F Camera Raw File / x3f | ✅ image（扩展名规则） |
| Audio | .3ga | 3GP Audio File | ✅ video（扩展名规则） |
| Audio | .8svx | Amiga 8-Bit Sound File | ✅ video（扩展名规则） |
| Audio | .aa | Audible Audio Book File | ✅ video（扩展名规则） |
| Audio | .aa3 | ATRAC3 Audio File | ✅ video（扩展名规则） |
| Audio | .aac | Advanced Audio Coding File / raw ADTS AAC | ✅ video（扩展名规则） |
| Audio | .ac3 | Audio Codec 3 File / raw AC-3 | ✅ video（扩展名规则） |
| Audio | .act | S1 MP3 Player Recorded Audio | ✅ video（扩展名规则） |
| Audio | .adts | ADTS AAC | ✅ video（扩展名规则） |
| Audio | .aea | ATRAC1 Audio File / MD STUDIO audio | ✅ video（扩展名规则） |
| Audio | .aif | Audio Interchange File Format | ✅ video（扩展名规则） |
| Audio | .aifc | Compressed Audio Interchange File | ✅ video（扩展名规则） |
| Audio | .aiff | Audio IFF | ✅ video（扩展名规则） |
| Audio | .amr | Adaptive Multi-Rate Codec File / 3GPP AMR file format | ✅ video（扩展名规则） |
| Audio | .apc | CRYO Interactive APC Audio File / CRYO APC format | ✅ video（扩展名规则） |
| Audio | .ape | Monkey's Audio Lossless Audio File / Monkey's Audio | ✅ video（扩展名规则） |
| Audio | .au | Audio File / SUN AU format | ✅ video（扩展名规则） |
| Audio | .aud | WestWood Audio File | ❌ FFmpeg 无对应 demuxer |
| Audio | .caf | Core Audio File / Apple Core Audio Format | ✅ video（扩展名规则） |
| Audio | .daud | D-Cinema audio format | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Audio | .dss | Digital Speech Standard Audio File | ✅ video（扩展名规则） |
| Audio | .dts | DTS Encoded Audio File / raw DTS | ✅ video（扩展名规则） |
| Audio | .eac3 | raw E-AC-3 | ✅ video（扩展名规则） |
| Audio | .flac | Free Lossless Audio Codec File / raw FLAC | ✅ video（扩展名规则） |
| Audio | .g722 | G.722 ADPCM Audio File / raw G.722 | ✅ video（扩展名规则） |
| Audio | .gsm | Global System for Mobile Audio File / raw GSM | ✅ video（扩展名规则） |
| Audio | .htk | Hidden Markov Model Toolkit Audio | ❌ FFmpeg 无对应 demuxer |
| Audio | .iss | Funcom ISS Audio File / Funcom ISS format | 🔮 默认 .iss 规则为 Inno Setup（code）；Funcom ISS 音频属 MIME/内容嗅探子类，待嗅探器 |
| Audio | .m4a | MPEG-4 Audio File | ✅ video（扩展名规则） |
| Audio | .m4b | MPEG-4 Audio Book File | ✅ video（扩展名规则） |
| Audio | .m4r | iPhone Ringtone File | ✅ video（扩展名规则） |
| Audio | .mka | Matroska Audio File | ✅ video（扩展名规则） |
| Audio | .mlp | Meridian Lossless Packing Audio File / raw MLP | ✅ video（扩展名规则） |
| Audio | .mmf | Yamaha SMAF | ✅ video（扩展名规则） |
| Audio | .mp1 | MPEG-1 Audio File | ✅ video（扩展名规则） |
| Audio | .mp2 | MPEG Layer II Compressed Audio File / MPEG audio layer 2 | ✅ video（扩展名规则） |
| Audio | .mp3 | MP3 Audio File / MPEG audio layer 3 | ✅ video（扩展名规则） |
| Audio | .mpa | MPEG-2 Audio File | ✅ video（扩展名规则） |
| Audio | .mpc | Musepack Compressed Audio File | ✅ video（扩展名规则） |
| Audio | .mpc8 | Musepack SV8 | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Audio | .ogg | Ogg Vorbis Audio File / Ogg | ✅ video（扩展名规则） |
| Audio | .oma | Sony OpenMG Music File / Sony OpenMG audio | ✅ video（扩展名规则） |
| Audio | .opus | Opus Audio File | ✅ video（扩展名规则） |
| Audio | .paf | PARIS Audio File | ✅ video（扩展名规则） |
| Audio | .pvf | Portable Voice Format Audio | ✅ video（扩展名规则） |
| Audio | .qcp | PureVoice Audio File / QCP format | ✅ video（扩展名规则） |
| Audio | .ra | Real Audio File | ✅ video（扩展名规则） |
| Audio | .rso | NXT Brick Audio File / Lego Mindstorms RSO format | ✅ video（扩展名规则） |
| Audio | .sf | IRCAM Sound File | ❌ FFmpeg 无对应 demuxer |
| Audio | .shn | Shorten Compressed Audio File / raw Shorten | ✅ video（扩展名规则） |
| Audio | .snd | Sound File | ✅ video（扩展名规则） |
| Audio | .sol | Sierra On-Line Audio File / Sierra SOL format | ✅ video（扩展名规则） |
| Audio | .son | Beam Software SIFF Audio File | ❌ FFmpeg 无对应 demuxer |
| Audio | .sox | SoX native format | ✅ video（扩展名规则） |
| Audio | .spdif | IEC 61937 (used on S/PDIF - IEC958) | ✅ video（扩展名规则） |
| Audio | .sph | NIST SPHERE Audio File | ✅ video（扩展名规则） |
| Audio | .spx | Ogg Vorbis Speex File | ✅ video（扩展名规则） |
| Audio | .str | PlayStation Video Stream | ✅ video（扩展名规则） |
| Audio | .tak | Tom's Lossless Audio Kompressor File | ✅ video（扩展名规则） |
| Audio | .tta | True Audio File / True Audio | ✅ video（扩展名规则） |
| Audio | .voc | Creative Labs Audio File / Creative Voice file format | ✅ video（扩展名规则） |
| Audio | .vqf | TwinVQ Audio File / Nippon Telegraph and Telephone Corporation (NTT) TwinVQ | ✅ video（扩展名规则） |
| Audio | .w64 | Sony Wave64 Audio File / Sony Wave64 format | ✅ video（扩展名规则） |
| Audio | .wav | WAVE Audio File / WAV format | ✅ video（扩展名规则） |
| Audio | .wma | Windows Media Audio File | ✅ video（扩展名规则） |
| Audio | .wsaud | Westwood Studios audio format | ✅ video（扩展名规则） |
| Audio | .wv | WavPack Audio File / WavPack | ✅ video（扩展名规则） |
| Audio | .xa | PlayStation Audio File / Maxis XA File Format | ✅ video（扩展名规则） |
| Audio | .xma | Xbox Media Audio File | ✅ video（扩展名规则） |
| Video | .3g2 | 3GPP2 Multimedia File / 3GP2 format | ✅ video（扩展名规则） |
| Video | .3gp | 3GPP Multimedia File / 3GP format | ✅ video（扩展名规则） |
| Video | .4xm | 4X Movie / 4X Technologies format | ✅ video（扩展名规则） |
| Video | .a64 | a64 - video for Commodore 64 | ❌ FFmpeg 无对应 demuxer |
| Video | .amv | Anime Music Video File | ✅ video（扩展名规则） |
| Video | .anim | Amiga Animation File | ❌ FFmpeg 无对应 demuxer |
| Video | .anm | DeluxePaint Animation / Deluxe Paint Animation | ✅ video（扩展名规则） |
| Video | .asf | Advanced Systems Format File / ASF format | ✅ video（扩展名规则） |
| Video | .avi | Audio Video Interleave File / AVI format | ✅ video（扩展名规则） |
| Video | .avs | AVISynth | ✅ video（扩展名规则） |
| Video | .bethsoftvid | Bethesda Softworks VID format | ✅ video（扩展名规则） |
| Video | .bfi | Brute Force and Ignorance Video / Brute Force & Ignorance | ✅ video（扩展名规则） |
| Video | .bik | Bink Video File | ✅ video（扩展名规则） |
| Video | .bink | Bink | ✅ video（扩展名规则） |
| Video | .bmv | Discworld II Video File | ✅ video（扩展名规则） |
| Video | .c93 | Interplay C93 Video / Interplay C93 | ✅ video（扩展名规则） |
| Video | .cak | SEGA FILM Video | ❌ FFmpeg 无对应 demuxer |
| Video | .cam | MSN Messenger Webcam Recording | ❌ FFmpeg 无对应 demuxer |
| Video | .cdg | CD Graphics Format | ✅ video（扩展名规则） |
| Video | .cdxl | Commodore CDXL Video | ✅ video（扩展名规则） |
| Video | .cin | Delphine Software CIN Video | ⚠️ 默认 .cin 规则为 Cineon 位图（image）；Delphine CIN 视频可由 FFmpeg（cine）解码，待实测/嗅探 |
| Video | .cmv | Electronic Arts CMV Video | ❌ FFmpeg 无对应 demuxer |
| Video | .dat | VCD Video File | ✅ email（扩展名规则） |
| Video | .dct | Electronic Arts DCT Video | ❌ FFmpeg 无对应 demuxer |
| Video | .dfa | DreamForge Intertainment Video | ✅ video（扩展名规则） |
| Video | .dirac | raw Dirac | ✅ video（扩展名规则） |
| Video | .divx | DivX Video File | ✅ video（扩展名规则） |
| Video | .dnxhd | raw DNxHD (SMPTE VC-3) | ✅ video（扩展名规则） |
| Video | .drc | BBC Dirac Video | ❌ FFmpeg 无对应 demuxer |
| Video | .dsicin | Delphine Software International CIN format | ✅ video（扩展名规则） |
| Video | .duk | Duck TrueMotion 1 Video | ❌ FFmpeg 无对应 demuxer |
| Video | .dv | Digital Video File / DV video format | ✅ video（扩展名规则） |
| Video | .dvd | MPEG-2 PS format (DVD VOB) | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Video | .dxa | Feeble Files Video / DXA | ✅ video（扩展名规则） |
| Video | .ea | Electronic Arts Multimedia Format | ✅ video（扩展名规则） |
| Video | .f4v | Flash MP4 Video File | ✅ video（扩展名规则） |
| Video | .flc | FLIC Animation | ✅ video（扩展名规则） |
| Video | .flic | FLI/FLC/FLX animation format | ✅ video（扩展名规则） |
| Video | .flv | Flash Video File / FLV format | ✅ video（扩展名规则） |
| Video | .gdv | Gremlin Digital Video File | ✅ video（扩展名规则） |
| Video | .gif | GIF Animation | ✅ image、video（扩展名规则） |
| Video | .gxf | General Exchange Format Video File / GXF format | ✅ video（扩展名规则） |
| Video | .h261 | raw H.261 | ✅ video（扩展名规则） |
| Video | .h263 | H.263 Video / raw H.263 | ✅ video（扩展名规则） |
| Video | .h264 | Raw H.264 Video File / raw H.264 video format | ✅ video（扩展名规则） |
| Video | .hevc | High Efficiency Video Coding File | ✅ video（扩展名规则） |
| Video | .idcin | id Cinematic format | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Video | .iff | IFF format | ✅ video（扩展名规则） |
| Video | .ingenient | raw Ingenient MJPEG | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Video | .ipmovie | Interplay MVE format | ✅ video（扩展名规则） |
| Video | .ipod | iPod H.264 MP4 format | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Video | .iv8 | A format generated by IndigoVision 8000 video server | ✅ video（扩展名规则） |
| Video | .ivf | On2 IVF | ✅ video（扩展名规则） |
| Video | .jv | Bitmap Brothers Video File | ✅ video（扩展名规则） |
| Video | .k3g | 3GP Mobile Phone Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .lmlm4 | lmlm4 raw format | ✅ video（扩展名规则） |
| Video | .lvf | DVR LVF Video File | ✅ video（扩展名规则） |
| Video | .lxf | Harris/Leitch DVR Video File / VR native stream format (LXF) | ✅ video（扩展名规则） |
| Video | .m2t | Blu-ray BDAV Video File | ✅ video（扩展名规则） |
| Video | .m2v | MPEG-2 Video File | ✅ video（扩展名规则） |
| Video | .m4v | iTunes Video File / raw MPEG-4 video format | ✅ video（扩展名规则） |
| Video | .mad | Electronic Arts Madcow Video | ❌ FFmpeg 无对应 demuxer |
| Video | .mjpeg | raw MJPEG video | ✅ video（扩展名规则） |
| Video | .mk3d | Matroska 3D Video File | ✅ video（扩展名规则） |
| Video | .mkv | Matroska Video File | ✅ video（扩展名规则） |
| Video | .mm | American Laser Games MM format | ✅ video（扩展名规则） |
| Video | .mmv | Sony MicroMV Video | ❌ FFmpeg 无对应 demuxer |
| Video | .mod | JVC Everio Video Recording | ✅ video（扩展名规则） |
| Video | .mov | Apple QuickTime Movie / MOV format | ✅ video（扩展名规则） |
| Video | .mp3id3v1 | MPEG audio layer 3 with id3v1 only | ❌ FFmpeg 无对应 demuxer |
| Video | .mp3id3v2 | MPEG audio layer 3 with id3v2 only | ❌ FFmpeg 无对应 demuxer |
| Video | .mp4 | MPEG-4 Video File / MP4 format | ✅ video（扩展名规则） |
| Video | .mpc | Electronic Arts MPCh Video File / Musepack | ✅ video（扩展名规则） |
| Video | .mpeg | MPEG-1 System format | ✅ video（扩展名规则） |
| Video | .mpg | MPEG Video File | ✅ video（扩展名规则） |
| Video | .mts | AVCHD Video File | ✅ video（扩展名规则） |
| Video | .mtv | MTV format | ✅ video（扩展名规则） |
| Video | .mve | Interplay MVE Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .mvi | Motion Pixels MVI1 Video File / Motion Pixels MVI format | ✅ video（扩展名规则） |
| Video | .mxf | Material Exchange Format File / Material eXchange Format | ✅ video（扩展名规则） |
| Video | .mxg | MxPEG clip file format | ✅ video（扩展名规则） |
| Video | .nc | NC camera feed format | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Video | .nsv | Nullsoft Streaming Video File / Nullsoft Streaming Video | ✅ video（扩展名规则） |
| Video | .nut | FFmpeg NUT Video File / NUT format | ✅ video（扩展名规则） |
| Video | .nuv | NuppelVideo File / NuppelVideo format | ✅ video（扩展名规则） |
| Video | .ogm | Ogg Media File | ✅ video（扩展名规则） |
| Video | .ogv | Ogg Video File | ✅ video（扩展名规则） |
| Video | .p64 | H.261 Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .pmf | PSP Movie File | ❌ FFmpeg 无对应 demuxer |
| Video | .psp | PSP MP4 format | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Video | .psxstr | Sony Playstation STR format | ❌ FFmpeg 无对应 demuxer |
| Video | .pva | PVA Video File / TechnoTrend PVA file and stream format | ✅ video（扩展名规则） |
| Video | .qt | QuickTime RLE Video File | ✅ video（扩展名规则） |
| Video | .r3d | REDCODE R3D format | ✅ video（扩展名规则） |
| Video | .rcv | VC-1 test bitstream | ✅ video（扩展名规则） |
| Video | .rl2 | Voyeur Game Video File / RL2 format | ✅ video（扩展名规则） |
| Video | .rm | Real Media File / RealMedia format | ✅ video（扩展名规则） |
| Video | .rmvb | RealMedia Variable Bit Rate File | ✅ video（扩展名规则） |
| Video | .roq | id RoQ Video / raw id RoQ format | ✅ video（扩展名规则） |
| Video | .rpl | Escape Video File / RPL/ARMovie format | ✅ video（扩展名规则） |
| Video | .san | LucasArts Smush Video | ❌ FFmpeg 无对应 demuxer |
| Video | .sfd | Sofdec Dreamcast Movie | ❌ FFmpeg 无对应 demuxer |
| Video | .siff | Beam Software SIFF | ✅ video（扩展名规则） |
| Video | .smk | Smacker Movie File / Smacker video | ✅ video（扩展名规则） |
| Video | .svcd | MPEG-2 PS format (VOB) | ✅ video（扩展名规则） |
| Video | .swf | Flash format | ✅ video（扩展名规则） |
| Video | .tgq | Electronic Arts TGQ Video | ❌ FFmpeg 无对应 demuxer |
| Video | .tgv | Electronic Arts TGV Video | ❌ FFmpeg 无对应 demuxer |
| Video | .thp | Wii/GameCube Video File / THP | ✅ video（扩展名规则） |
| Video | .tiertexseq | Tiertex Limited SEQ format | ✅ video（扩展名规则） |
| Video | .tmv | 8088flex Video File / 8088flex TMV | ✅ video（扩展名规则） |
| Video | .tp | Beyond TV Transport Stream File | ✅ video（扩展名规则） |
| Video | .trp | HD Video Transport Stream | ✅ video（扩展名规则） |
| Video | .truehd | raw TrueHD | ✅ video（扩展名规则） |
| Video | .ts | Video Transport Stream File | ✅ code、video（扩展名规则） |
| Video | .tty | Tele-typewriter | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Video | .vb | Beam Game SIFF Video | ❌ 默认 .vb 规则为 VBScript（code）；Beam SIFF 视频无对应 demuxer |
| Video | .vc1 | VC-1 Video File / raw VC-1 | ✅ video（扩展名规则） |
| Video | .vcd | MPEG-1 System format (VCD) | ✅ video（扩展名规则） |
| Video | .vid | Bethesda Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .vmd | Sierra VMD Video File / Sierra VMD format | ✅ video（扩展名规则） |
| Video | .vob | DVD Video Object File / MPEG-2 PS format (VOB) | ✅ video（扩展名规则） |
| Video | .vp3 | On2 VP3 Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .vp5 | On2 VP5 Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .vp6 | On2 VP6 Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .vp7 | On2 VP7 Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .vqa | Westwood Studios VQA Video | ❌ FFmpeg 无对应 demuxer |
| Video | .vsr | CPCAM CCTV Recording | ❌ FFmpeg 无对应 demuxer |
| Video | .wc3movie | Wing Commander III movie format | ✅ video（扩展名规则） |
| Video | .webm | WebM Video File / WebM file format | ✅ video（扩展名规则） |
| Video | .wmv | Windows Media Video File | ✅ video（扩展名规则） |
| Video | .wsvqa | Westwood Studios VQA format | ✅ video（扩展名规则） |
| Video | .wtv | Windows Recorded TV Show File / Windows Television (WTV) | ✅ video（扩展名规则） |
| Video | .wve | Electronic Arts TQI Video File | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Video | .xesc | Microsoft Expression Screen Capture Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .xmv | Xbox Media Video File | ✅ video（扩展名规则） |
| Video | .yop | Psygnosis YOP Video / Psygnosis YOP Format | ✅ video（扩展名规则） |
| Archive | .7z | 7-Zip Compressed File | ✅ archive（扩展名规则） |
| Archive | .apk | Android Package | ✅ archive（扩展名规则） |
| Archive | .arj | ARJ Compressed Archive | ✅ archive（扩展名规则） |
| Archive | .bz2 | Bzip2 Compressed Archive | ✅ archive（扩展名规则） |
| Archive | .cab | Windows Cabinet File | ✅ archive（扩展名规则） |
| Archive | .cbr | Comic Book RAR Archive / Comic Book archive | ✅ mupdf、archive（扩展名规则） |
| Archive | .cbz | Comic Book Zip Archive / Comic Book archive | ✅ mupdf、archive（扩展名规则） |
| Archive | .cpio | Unix CPIO Archive | ✅ archive（扩展名规则） |
| Archive | .dd | Disk Doubler Archive | ❌ 非压缩包（原始磁盘镜像），libarchive 不处理 |
| Archive | .deb | Debian Software Package | ✅ archive（扩展名规则） |
| Archive | .deskthemepack | Windows Desktop Theme Pack | ✅ archive（扩展名规则） |
| Archive | .dmg | Mac OS X Disk Image | ✅ archive（扩展名规则） |
| Archive | .gz | Gzip Archive | ✅ archive（扩展名规则） |
| Archive | .hfs | HFS Disk Image | ✅ archive（扩展名规则） |
| Archive | .iso | ISO Disc Image | ✅ archive（扩展名规则） |
| Archive | .jar | Java Archive | ✅ archive（扩展名规则） |
| Archive | .lha | LHARC Compressed File | ✅ archive（扩展名规则） |
| Archive | .lzh | LZH Compressed File | ✅ archive（扩展名规则） |
| Archive | .lzma | LZMA Compressed File | ✅ archive（扩展名规则） |
| Archive | .pk3 | id Tech 3 Engine Game Data File | ✅ archive（扩展名规则） |
| Archive | .pk4 | id Tech 4 Engine Game Data File | ✅ archive（扩展名规则） |
| Archive | .pkz | Video Game Package | ✅ archive（扩展名规则） |
| Archive | .rar | RAR Compressed Archive | ✅ archive（扩展名规则） |
| Archive | .rpm | Red Hat Package Manager File | ✅ archive（扩展名规则） |
| Archive | .tar | TAR Archive | ✅ archive（扩展名规则） |
| Archive | .tar.lzma | LZMA Compressed Tar Archive | ✅ archive（扩展名规则） |
| Archive | .taz | Z Compressed Tar File | ✅ archive（扩展名规则） |
| Archive | .tbz | Bzip2 Compressed Tar Archive | ✅ archive（扩展名规则） |
| Archive | .tgz | Gzipped Tar File | ✅ archive（扩展名规则） |
| Archive | .txz | XZ Compressed Tar File | ✅ archive（扩展名规则） |
| Archive | .vhd | Virtual Hard Disk File | 🔮 默认 .vhd 规则为 VHDL（code）；虚拟硬盘属 MIME/内容嗅探子类，待嗅探器 |
| Archive | .war | Java Web Archive | ✅ archive（扩展名规则） |
| Archive | .wim | Windows Imaging Format File | ✅ archive（扩展名规则） |
| Archive | .xar | Extensible Archive Format File | ✅ archive（扩展名规则） |
| Archive | .xz | XZ Compressed Archive | ✅ archive（扩展名规则） |
| Archive | .z | Unix Compressed File | ✅ archive（扩展名规则） |
| Archive | .zip | Zipped File | ✅ archive（扩展名规则） |
| Archive | .zipx | Extended Zip File | ✅ archive（扩展名规则） |
| Source Code | .a2l | ASAP2 ECU Description File | ✅ code（扩展名规则） |
| Source Code | .ads | Ada Source Code File | ✅ code（扩展名规则） |
| Source Code | .ahk | AutoHotkey Script | ✅ code（扩展名规则） |
| Source Code | .as | ActionScript File | ✅ code（扩展名规则） |
| Source Code | .asm | Assembly Language Source Code File | ✅ code（扩展名规则） |
| Source Code | .au3 | AutoIt Script | ✅ code（扩展名规则） |
| Source Code | .bas | Basic Source Code File | ✅ code（扩展名规则） |
| Source Code | .bat | DOS Batch File | ✅ code（扩展名规则） |
| Source Code | .bpk | Borland C++Builder Package | ✅ code（扩展名规则） |
| Source Code | .bpr | Borland C++Builder Project File | ✅ code（扩展名规则） |
| Source Code | .c | C/C++ Source Code File | ✅ code（扩展名规则） |
| Source Code | .cbl | COBOL Source Code File | ✅ code（扩展名规则） |
| Source Code | .cfg | Configuration File | ✅ code（扩展名规则） |
| Source Code | .cfm | ColdFusion Markup File | ✅ code（扩展名规则） |
| Source Code | .cgi | CGI Script | ✅ code（扩展名规则） |
| Source Code | .clp | Clipper Source Code File | ✅ code（扩展名规则） |
| Source Code | .cmake | CMake File | ✅ code（扩展名规则） |
| Source Code | .cmd | Windows Command File | ✅ code（扩展名规则） |
| Source Code | .cpp | C++ Source Code File | ✅ code（扩展名规则） |
| Source Code | .cs | C# Source Code File | ✅ code（扩展名规则） |
| Source Code | .csh | C Shell Script | ✅ code（扩展名规则） |
| Source Code | .dfm | Delphi Form | ✅ code（扩展名规则） |
| Source Code | .diz | Description in Zip File | ✅ code（扩展名规则） |
| Source Code | .dpk | Delphi Package | ✅ code（扩展名规则） |
| Source Code | .dpr | Delphi Project File | ✅ code（扩展名规则） |
| Source Code | .eba | EBasic Source Code File | ✅ code（扩展名规则） |
| Source Code | .erl | Erlang Source Code File | ✅ code（扩展名规则） |
| Source Code | .ex | Euphoria Source Code File | ✅ code（扩展名规则） |
| Source Code | .f | Fortran Source Code File | ✅ code（扩展名规则） |
| Source Code | .h | C/C++/Objective-C Header File | ✅ code（扩展名规则） |
| Source Code | .haml | Haml Source Code File | ✅ code（扩展名规则） |
| Source Code | .hpp | C++ Header File | ✅ code（扩展名规则） |
| Source Code | .hs | Haskell Script | ✅ code（扩展名规则） |
| Source Code | .inc | Include File | ✅ code（扩展名规则） |
| Source Code | .inf | Setup Information File | ✅ code（扩展名规则） |
| Source Code | .ini | Windows Initialization File | ✅ code（扩展名规则） |
| Source Code | .iss | Inno Setup Script | ✅ code（扩展名规则） |
| Source Code | .iwb | IWBasic Source Code File | ✅ code（扩展名规则） |
| Source Code | .java | Java Source Code File | ✅ code（扩展名规则） |
| Source Code | .js | JavaScript File | ✅ code（扩展名规则） |
| Source Code | .json | JSON File | ✅ code（扩展名规则） |
| Source Code | .kix | KiXstart Script | ✅ code（扩展名规则） |
| Source Code | .lhs | Haskell Script | ✅ code（扩展名规则） |
| Source Code | .log | Log File | ✅ code（扩展名规则） |
| Source Code | .lua | LUA Source Code File | ✅ code（扩展名规则） |
| Source Code | .ml | ML Script | ✅ code（扩展名规则） |
| Source Code | .nfo | Plain text files | ✅ code（扩展名规则） |
| Source Code | .nsh | NSIS Header File | ✅ code（扩展名规则） |
| Source Code | .nsi | NSIS Script | ✅ code（扩展名规则） |
| Source Code | .ob2 | Oberon Source Code File | ✅ code（扩展名规则） |
| Source Code | .pas | Pascal Source File | ✅ code（扩展名规则） |
| Source Code | .pl | Perl Script | ✅ code（扩展名规则） |
| Source Code | .pm | Perl Module | ✅ code（扩展名规则） |
| Source Code | .pod | Perl POD File | ✅ code（扩展名规则） |
| Source Code | .prg | FoxPro Program File | ✅ code（扩展名规则） |
| Source Code | .ps1 | PowerShell Script | ✅ code（扩展名规则） |
| Source Code | .py | Python Script | ✅ code（扩展名规则） |
| Source Code | .r | R Script | ✅ code（扩展名规则） |
| Source Code | .rb | Ruby Source Code File | ✅ code（扩展名规则） |
| Source Code | .rc | Resource Script | ✅ code（扩展名规则） |
| Source Code | .sas | SAS Program File | ✅ code（扩展名规则） |
| Source Code | .scm | Scheme Source Code File | ✅ code（扩展名规则） |
| Source Code | .sh | Bash Shell Script | ✅ code（扩展名规则） |
| Source Code | .sql | SQL File | ✅ code（扩展名规则） |
| Source Code | .ss | Scheme Source Code File | ✅ code（扩展名规则） |
| Source Code | .st | Smalltalk Source Code File | ✅ code（扩展名规则） |
| Source Code | .sty | LaTeX Style | ✅ code（扩展名规则） |
| Source Code | .tcl | Tcl Script | ✅ code（扩展名规则） |
| Source Code | .tex | LaTeX Source Document | ✅ code（扩展名规则） |
| Source Code | .txt | Plain Text File | ✅ code（扩展名规则） |
| Source Code | .v | Verilog Source Code File | ✅ code（扩展名规则） |
| Source Code | .vb | VBScript File | ✅ code（扩展名规则） |
| Source Code | .vhd | VHDL File | ✅ code（扩展名规则） |
| Source Code | .xsd | XML Schema Definition | ✅ code（扩展名规则） |
| Source Code | .xslt | XSL Transformation File | ✅ code、web（扩展名规则） |
| Source Code | .yml | YAML Document | ✅ code（扩展名规则） |
| Web | .htm | HTML page | ✅ web、code（扩展名规则） |
| Web | .html | Hypertext Markup Language File / HTML page | ✅ web、code（扩展名规则） |
| Web | .mht | MHTML Web Archive / Microsoft HTML archive | ✅ web、onlyoffice（扩展名规则） |
| Web | .shtm | HTML page | ✅ web、code（扩展名规则） |
| Web | .shtml | HTML page | ✅ web、code（扩展名规则） |
| Web | .stm | HTML page | ✅ code（扩展名规则） |
| Source Code / Web | .asp | Active Server Page / Active Server Page script | ✅ code（扩展名规则） |
| Source Code / Web | .aspx | Active Server Page Extended File / Active Server Page script | ✅ code（扩展名规则） |
| Source Code / Web | .css | Cascading Style Sheet / Cascaded stylesheet | ✅ code（扩展名规则） |
| Source Code / Web | .php | PHP Source Code File / PHP source code | ✅ code（扩展名规则） |
| Source Code / Web | .xml | XML File / XML container | ✅ code、web（扩展名规则） |
| Source Code / Web | .xsl | XML Style Sheet / XML stylesheet | ✅ code、web（扩展名规则） |

## 附录：非文件类型项（不追踪）

> UV 参考清单照搬了 FFmpeg 的 demuxer/muxer 清单，包含非文件的格式名：伪格式（流/管线/
> 调试输出）、网络协议、无编码参数的原始采样流、字幕。它们不是文件类型，不参与关联，
> 仅留档备查。

| 类别 | 后缀名 | 格式说明 | 是否支持，如何支持 |
| --- | --- | --- | --- |
| FFmpeg Pseudo Formats | .applehttp | Apple HTTP Live Streaming format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .avm2 | Flash 9 (AVM2) format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .cavsvideo | raw Chinese AVS video | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .crc | CRC testing format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .ffm | FFM (FFserver live feed) format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .ffmetadata | FFmpeg metadata in text format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .filmstrip | Adobe Filmstrip | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .framecrc | framecrc testing format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .framemd5 | Per-frame MD5 testing format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .image2 | image2 sequence | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .image2pipe | piped image2 sequence | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .matroska | Matroska file format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .md5 | MD5 testing format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .mpeg1video | raw MPEG-1 video | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .mpeg2video | raw MPEG-2 video | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .mpegts | MPEG-2 transport stream format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .mpegtsraw | MPEG-2 raw transport stream format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .mpegvideo | raw MPEG video | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .mpjpeg | MIME multipart JPEG format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .msnwctcp | MSN TCP Webcam stream | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .null | raw null video format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .rawvideo | raw video format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .vc1test | VC-1 test bitstream format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .vfwcap | VFW video capture | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| FFmpeg Pseudo Formats | .yuv4mpegpipe | YUV4MPEG pipe format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Raw PCM Streams | .alaw | PCM A-law format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .f32be | PCM 32 bit floating-point big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .f32le | PCM 32 bit floating-point little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .f64be | PCM 64 bit floating-point big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .f64le | PCM 64 bit floating-point little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .mulaw | PCM mu-law format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .s16be | PCM signed 16 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .s16le | PCM signed 16 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .s24be | PCM signed 24 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .s24le | PCM signed 24 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .s32be | PCM signed 32 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .s32le | PCM signed 32 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .s8 | PCM signed 8 bit format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .u16be | PCM unsigned 16 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .u16le | PCM unsigned 16 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .u24be | PCM unsigned 24 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .u24le | PCM unsigned 24 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .u32be | PCM unsigned 32 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .u32le | PCM unsigned 32 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Raw PCM Streams | .u8 | PCM unsigned 8 bit format | ❌ 原始采样流（扩展名不含编码参数） |
| Network Protocols | .rtp | RTP output format | ❌ 网络协议，非文件 |
| Network Protocols | .rtsp | RTSP output format | ❌ 网络协议，非文件 |
| Network Protocols | .sap | SAP output format | ❌ 网络协议，非文件 |
| Network Protocols | .sdp | SDP | ❌ 网络协议，非文件 |
| Subtitles | .ass | Advanced SubStation Alpha subtitle format | ❌ 字幕文件（播放时内嵌显示） |
| Subtitles | .srt | SubRip subtitle format | ❌ 字幕文件（播放时内嵌显示） |
