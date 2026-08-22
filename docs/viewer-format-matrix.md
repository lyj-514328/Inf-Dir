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
> 支持面判定依据：FFmpeg `libavformat/allformats.c` 的 368 个 demuxer（对应
> shinchiro `mpv-dev` 全量构建）与 ImageMagick 实测 `magick -list format` 输出。
> 注：无扩展名规则的文件可能经 `image/*`、`video/*`、`audio/*`、`text/*`
> MIME 兜底命中（依赖系统注册的 Content Type 与后端解码能力）；同名冲突后缀的
> 常见语义作为默认 viewer、其余语义作为 MIME 子类表达。重新生成：
> `node tools/gen_format_matrix.mjs`。

| 类别 | 后缀名 | 格式说明 | 是否支持，如何支持 |
| --- | --- | --- | --- |
| Text | .diz | Description in Zip File | ✅ code（扩展名规则） |
| Text | .doc | Microsoft Word Document (Legacy) | ✅ onlyoffice（扩展名规则） |
| Text | .docm | Microsoft Word Macro-Enabled Document | ✅ office、onlyoffice（扩展名规则） |
| Text | .docx | Microsoft Word Document | ✅ office、onlyoffice（扩展名规则） |
| Text | .dot | Microsoft Word Document Template | ✅ onlyoffice（扩展名规则） |
| Text | .dotm | Microsoft Word Macro-Enabled Document Template | ✅ office、onlyoffice（扩展名规则） |
| Text | .dotx | Microsoft Word Document Template | ✅ office、onlyoffice（扩展名规则） |
| Text | .epub | EPUB eBook | ✅ mupdf（扩展名规则） |
| Text | .odt | OpenDocument Text Document | ✅ onlyoffice（扩展名规则） |
| Text | .ott | OpenDocument Document Template | ✅ onlyoffice（扩展名规则） |
| Text | .rtf | Rich Text Format File | ✅ onlyoffice（扩展名规则） |
| Text | .txt | Plain Text File | ✅ code（扩展名规则） |
| Text | .wps | Microsoft Works Word Processor Document | ✅ onlyoffice（扩展名规则） |
| PDF & XPS | .oxps | Open XML Paper Specification File | ✅ mupdf（扩展名规则） |
| PDF & XPS | .pdf | Portable Document Format File | ✅ pdf、pdfjs（扩展名规则） |
| PDF & XPS | .xps | XML Paper Specification File | ✅ mupdf（扩展名规则） |
| Spreadsheet | .csv | Comma Separated Values File | ✅ code（扩展名规则） |
| Spreadsheet | .tsv | Tab Separated Values File | ✅ code（扩展名规则） |
| Spreadsheet | .xls | Excel Spreadsheet (Legacy) | ✅ onlyoffice（扩展名规则） |
| Spreadsheet | .xlsm | Excel Macro-Enabled Spreadsheet | ✅ office、onlyoffice（扩展名规则） |
| Spreadsheet | .xlsx | Excel Spreadsheet | ✅ office、onlyoffice（扩展名规则） |
| Spreadsheet | .xlt | Excel Spreadsheet Template | ✅ onlyoffice（扩展名规则） |
| Spreadsheet | .xltm | Excel Macro-Enabled Spreadsheet Template | ✅ office、onlyoffice（扩展名规则） |
| Spreadsheet | .xltx | Excel Spreadsheet Template | ✅ office、onlyoffice（扩展名规则） |
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
| Image | .ani | Windows animated cursor | ❌ ImageMagick 无对应 decoder |
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
| Image | .emz | Compressed Enhanced Metafile | ❌ ImageMagick 无对应 decoder |
| Image | .exr | OpenExr Image | ✅ image（扩展名规则） |
| Image | .fax | GFI fax image | ✅ image（扩展名规则） |
| Image | .gif | Graphical Interchange Format File / Compuserve GIF image | ✅ image、video（扩展名规则） |
| Image | .heic | High Efficiency Image Format | ✅ image（扩展名规则） |
| Image | .icb | Truevision image | ⚠️ ImageMagick 可解，未在配置声明（待实测） |
| Image | .icl | Windows icon library | ❌ ImageMagick 无对应 decoder |
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
| Image | .ptx | V.Flash PTX Image | ❌ ImageMagick 无对应 decoder |
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
| Image | .txd | Renderware Texture Dictionary | ❌ ImageMagick 无对应 decoder |
| Image | .vda | Truevision image | ⚠️ ImageMagick 可解，未在配置声明（待实测） |
| Image | .vst | Truevision image | ✅ onlyoffice（扩展名规则） |
| Image | .wbmp | Wireless Bitmap Image File | ✅ image（扩展名规则） |
| Image | .webp | WebP Image | ✅ image（扩展名规则） |
| Image | .win | Truevision image | ❌ ImageMagick 无对应 decoder |
| Image | .wmf | Windows Metafile / Windows metafile | ✅ image（扩展名规则） |
| Image | .wmz | Compressed Windows Metafile | ❌ ImageMagick 无对应 decoder |
| Image | .xbm | X11 Bitmap Graphic | ✅ image（扩展名规则） |
| Image | .xface | X-Face Image | ✅ image（扩展名规则） |
| Image | .xpm | X11 Pixmap Graphic | ✅ image（扩展名规则） |
| RAW | .3fr | Hasselblad 3F Raw Image / 3fr | ✅ image（扩展名规则） |
| RAW | .ari | ARRIRAW Image | ✅ image（扩展名规则） |
| RAW | .arw | Sony Digital Camera Image / arw | ✅ image（扩展名规则） |
| RAW | .bay | Casio Raw Image / bay | ❌ rawloader/ImageMagick 无对应 coder |
| RAW | .bmq | bmq | ❌ rawloader/ImageMagick 无对应 coder |
| RAW | .cine | cine | ✅ image（扩展名规则） |
| RAW | .cr2 | Canon Raw Image File / cr2 | ✅ image（扩展名规则） |
| RAW | .cr3 | Canon Raw 3 Image File | ✅ image（扩展名规则） |
| RAW | .crw | Canon Raw CIFF Image File / crw | ✅ image（扩展名规则） |
| RAW | .cs1 | cs1 | ❌ rawloader/ImageMagick 无对应 coder |
| RAW | .dc2 | dc2 | ❌ rawloader/ImageMagick 无对应 coder |
| RAW | .dcr | Kodak Raw Image File / dcr | ✅ image（扩展名规则） |
| RAW | .dng | Digital Negative Image File / dng | ✅ image（扩展名规则） |
| RAW | .erf | Epson Raw File / erf | ✅ image（扩展名规则） |
| RAW | .fff | Hasselblad Raw Image / fff | ✅ image（扩展名规则） |
| RAW | .hdr | hdr | ✅ image（扩展名规则） |
| RAW | .ia | ia | ❌ rawloader/ImageMagick 无对应 coder |
| RAW | .iiq | Phase One Raw Image | ✅ image（扩展名规则） |
| RAW | .k25 | k25 | ✅ image（扩展名规则） |
| RAW | .kc2 | Kodak DCS200 Camera Raw Image / kc2 | ❌ rawloader/ImageMagick 无对应 coder |
| RAW | .kdc | Kodak Digital Camera Image / kdc | ✅ image（扩展名规则） |
| RAW | .mdc | Minolta Camera Raw Image / mdc | ✅ image（扩展名规则） |
| RAW | .mef | Mamiya Raw Image / mef | ✅ image（扩展名规则） |
| RAW | .mos | Leaf Camera Raw File / mos | ✅ image（扩展名规则） |
| RAW | .mrw | Minolta Raw Image File / mrw | ✅ image（扩展名规则） |
| RAW | .nef | Nikon Electronic Format RAW Image / nef | ✅ image（扩展名规则） |
| RAW | .nrw | Nikon Raw Image File / nrw | ✅ image（扩展名规则） |
| RAW | .orf | Olympus Raw File / orf | ✅ image（扩展名规则） |
| RAW | .pef | Pentax Electronic File / pef | ✅ image（扩展名规则） |
| RAW | .pxn | pxn | ❌ rawloader/ImageMagick 无对应 coder |
| RAW | .qtk | qtk | ❌ rawloader/ImageMagick 无对应 coder |
| RAW | .raf | Fuji Raw Image File / raf | ✅ image（扩展名规则） |
| RAW | .raw | Raw Image Data File / raw | ✅ image（扩展名规则） |
| RAW | .rdc | rdc | ❌ rawloader/ImageMagick 无对应 coder |
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
| Audio | .aac | Advanced Audio Coding File | ✅ video（扩展名规则） |
| Audio | .ac3 | Audio Codec 3 File | ✅ video（扩展名规则） |
| Audio | .act | S1 MP3 Player Recorded Audio | ✅ video（扩展名规则） |
| Audio | .aea | ATRAC1 Audio File | ✅ video（扩展名规则） |
| Audio | .aif | Audio Interchange File Format | ✅ video（扩展名规则） |
| Audio | .aifc | Compressed Audio Interchange File | ✅ video（扩展名规则） |
| Audio | .amr | Adaptive Multi-Rate Codec File | ✅ video（扩展名规则） |
| Audio | .apc | CRYO Interactive APC Audio File | ✅ video（扩展名规则） |
| Audio | .ape | Monkey's Audio Lossless Audio File | ✅ video（扩展名规则） |
| Audio | .au | Audio File | ✅ video（扩展名规则） |
| Audio | .aud | WestWood Audio File | ❌ FFmpeg 无对应 demuxer |
| Audio | .caf | Core Audio File | ✅ video（扩展名规则） |
| Audio | .dss | Digital Speech Standard Audio File | ✅ video（扩展名规则） |
| Audio | .dts | DTS Encoded Audio File | ✅ video（扩展名规则） |
| Audio | .flac | Free Lossless Audio Codec File | ✅ video（扩展名规则） |
| Audio | .g722 | G.722 ADPCM Audio File | ✅ video（扩展名规则） |
| Audio | .gsm | Global System for Mobile Audio File | ✅ video（扩展名规则） |
| Audio | .htk | Hidden Markov Model Toolkit Audio | ❌ FFmpeg 无对应 demuxer |
| Audio | .iss | Funcom ISS Audio File | ✅ code（扩展名规则） |
| Audio | .m4a | MPEG-4 Audio File | ✅ video（扩展名规则） |
| Audio | .m4b | MPEG-4 Audio Book File | ✅ video（扩展名规则） |
| Audio | .m4r | iPhone Ringtone File | ✅ video（扩展名规则） |
| Audio | .mka | Matroska Audio File | ✅ video（扩展名规则） |
| Audio | .mlp | Meridian Lossless Packing Audio File | ✅ video（扩展名规则） |
| Audio | .mp1 | MPEG-1 Audio File | ✅ video（扩展名规则） |
| Audio | .mp2 | MPEG Layer II Compressed Audio File | ✅ video（扩展名规则） |
| Audio | .mp3 | MP3 Audio File | ✅ video（扩展名规则） |
| Audio | .mpa | MPEG-2 Audio File | ✅ video（扩展名规则） |
| Audio | .mpc | Musepack Compressed Audio File | ✅ video（扩展名规则） |
| Audio | .ogg | Ogg Vorbis Audio File | ✅ video（扩展名规则） |
| Audio | .oma | Sony OpenMG Music File | ✅ video（扩展名规则） |
| Audio | .opus | Opus Audio File | ✅ video（扩展名规则） |
| Audio | .paf | PARIS Audio File | ✅ video（扩展名规则） |
| Audio | .pvf | Portable Voice Format Audio | ✅ video（扩展名规则） |
| Audio | .qcp | PureVoice Audio File | ✅ video（扩展名规则） |
| Audio | .ra | Real Audio File | ✅ video（扩展名规则） |
| Audio | .rso | NXT Brick Audio File | ✅ video（扩展名规则） |
| Audio | .sf | IRCAM Sound File | ❌ FFmpeg 无对应 demuxer |
| Audio | .shn | Shorten Compressed Audio File | ✅ video（扩展名规则） |
| Audio | .snd | Sound File | ✅ video（扩展名规则） |
| Audio | .sol | Sierra On-Line Audio File | ✅ video（扩展名规则） |
| Audio | .son | Beam Software SIFF Audio File | ❌ FFmpeg 无对应 demuxer |
| Audio | .sph | NIST SPHERE Audio File | ✅ video（扩展名规则） |
| Audio | .spx | Ogg Vorbis Speex File | ✅ video（扩展名规则） |
| Audio | .str | PlayStation Video Stream | ✅ video（扩展名规则） |
| Audio | .tak | Tom's Lossless Audio Kompressor File | ✅ video（扩展名规则） |
| Audio | .tta | True Audio File | ✅ video（扩展名规则） |
| Audio | .voc | Creative Labs Audio File | ✅ video（扩展名规则） |
| Audio | .vqf | TwinVQ Audio File | ✅ video（扩展名规则） |
| Audio | .w64 | Sony Wave64 Audio File | ✅ video（扩展名规则） |
| Audio | .wav | WAVE Audio File | ✅ video（扩展名规则） |
| Audio | .wma | Windows Media Audio File | ✅ video（扩展名规则） |
| Audio | .wv | WavPack Audio File | ✅ video（扩展名规则） |
| Audio | .xa | PlayStation Audio File | ✅ video（扩展名规则） |
| Audio | .xma | Xbox Media Audio File | ✅ video（扩展名规则） |
| Video | .3g2 | 3GPP2 Multimedia File | ✅ video（扩展名规则） |
| Video | .3gp | 3GPP Multimedia File | ✅ video（扩展名规则） |
| Video | .4xm | 4X Movie | ✅ video（扩展名规则） |
| Video | .amv | Anime Music Video File | ✅ video（扩展名规则） |
| Video | .anim | Amiga Animation File | ❌ FFmpeg 无对应 demuxer |
| Video | .anm | DeluxePaint Animation | ✅ video（扩展名规则） |
| Video | .asf | Advanced Systems Format File | ✅ video（扩展名规则） |
| Video | .avi | Audio Video Interleave File | ✅ video（扩展名规则） |
| Video | .bfi | Brute Force and Ignorance Video | ✅ video（扩展名规则） |
| Video | .bik | Bink Video File | ✅ video（扩展名规则） |
| Video | .bmv | Discworld II Video File | ✅ video（扩展名规则） |
| Video | .c93 | Interplay C93 Video | ✅ video（扩展名规则） |
| Video | .cak | SEGA FILM Video | ❌ FFmpeg 无对应 demuxer |
| Video | .cam | MSN Messenger Webcam Recording | ❌ FFmpeg 无对应 demuxer |
| Video | .cdxl | Commodore CDXL Video | ✅ video（扩展名规则） |
| Video | .cin | Delphine Software CIN Video | ✅ image（扩展名规则） |
| Video | .cmv | Electronic Arts CMV Video | ❌ FFmpeg 无对应 demuxer |
| Video | .dat | VCD Video File | ✅ email（扩展名规则） |
| Video | .dct | Electronic Arts DCT Video | ❌ FFmpeg 无对应 demuxer |
| Video | .dfa | DreamForge Intertainment Video | ✅ video（扩展名规则） |
| Video | .divx | DivX Video File | ✅ video（扩展名规则） |
| Video | .drc | BBC Dirac Video | ❌ FFmpeg 无对应 demuxer |
| Video | .duk | Duck TrueMotion 1 Video | ❌ FFmpeg 无对应 demuxer |
| Video | .dv | Digital Video File | ✅ video（扩展名规则） |
| Video | .dxa | Feeble Files Video | ✅ video（扩展名规则） |
| Video | .f4v | Flash MP4 Video File | ✅ video（扩展名规则） |
| Video | .flc | FLIC Animation | ✅ video（扩展名规则） |
| Video | .flv | Flash Video File | ✅ video（扩展名规则） |
| Video | .gdv | Gremlin Digital Video File | ✅ video（扩展名规则） |
| Video | .gxf | General Exchange Format Video File | ✅ video（扩展名规则） |
| Video | .h263 | H.263 Video | ✅ video（扩展名规则） |
| Video | .h264 | Raw H.264 Video File | ✅ video（扩展名规则） |
| Video | .hevc | High Efficiency Video Coding File | ✅ video（扩展名规则） |
| Video | .jv | Bitmap Brothers Video File | ✅ video（扩展名规则） |
| Video | .k3g | 3GP Mobile Phone Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .lvf | DVR LVF Video File | ✅ video（扩展名规则） |
| Video | .lxf | Harris/Leitch DVR Video File | ✅ video（扩展名规则） |
| Video | .m2t | Blu-ray BDAV Video File | ✅ video（扩展名规则） |
| Video | .m2v | MPEG-2 Video File | ✅ video（扩展名规则） |
| Video | .m4v | iTunes Video File | ✅ video（扩展名规则） |
| Video | .mad | Electronic Arts Madcow Video | ❌ FFmpeg 无对应 demuxer |
| Video | .mk3d | Matroska 3D Video File | ✅ video（扩展名规则） |
| Video | .mkv | Matroska Video File | ✅ video（扩展名规则） |
| Video | .mmv | Sony MicroMV Video | ❌ FFmpeg 无对应 demuxer |
| Video | .mod | JVC Everio Video Recording | ✅ video（扩展名规则） |
| Video | .mov | Apple QuickTime Movie | ✅ video（扩展名规则） |
| Video | .mp4 | MPEG-4 Video File | ✅ video（扩展名规则） |
| Video | .mpc | Electronic Arts MPCh Video File | ✅ video（扩展名规则） |
| Video | .mpg | MPEG Video File | ✅ video（扩展名规则） |
| Video | .mts | AVCHD Video File | ✅ video（扩展名规则） |
| Video | .mve | Interplay MVE Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .mvi | Motion Pixels MVI1 Video File | ✅ video（扩展名规则） |
| Video | .mxf | Material Exchange Format File | ✅ video（扩展名规则） |
| Video | .nsv | Nullsoft Streaming Video File | ✅ video（扩展名规则） |
| Video | .nut | FFmpeg NUT Video File | ✅ video（扩展名规则） |
| Video | .nuv | NuppelVideo File | ✅ video（扩展名规则） |
| Video | .ogm | Ogg Media File | ✅ video（扩展名规则） |
| Video | .ogv | Ogg Video File | ✅ video（扩展名规则） |
| Video | .p64 | H.261 Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .pmf | PSP Movie File | ❌ FFmpeg 无对应 demuxer |
| Video | .pva | PVA Video File | ✅ video（扩展名规则） |
| Video | .qt | QuickTime RLE Video File | ✅ video（扩展名规则） |
| Video | .rl2 | Voyeur Game Video File | ✅ video（扩展名规则） |
| Video | .rm | Real Media File | ✅ video（扩展名规则） |
| Video | .rmvb | RealMedia Variable Bit Rate File | ✅ video（扩展名规则） |
| Video | .roq | id RoQ Video | ✅ video（扩展名规则） |
| Video | .rpl | Escape Video File | ✅ video（扩展名规则） |
| Video | .san | LucasArts Smush Video | ❌ FFmpeg 无对应 demuxer |
| Video | .sfd | Sofdec Dreamcast Movie | ❌ FFmpeg 无对应 demuxer |
| Video | .smk | Smacker Movie File | ✅ video（扩展名规则） |
| Video | .tgq | Electronic Arts TGQ Video | ❌ FFmpeg 无对应 demuxer |
| Video | .tgv | Electronic Arts TGV Video | ❌ FFmpeg 无对应 demuxer |
| Video | .thp | Wii/GameCube Video File | ✅ video（扩展名规则） |
| Video | .tmv | 8088flex Video File | ✅ video（扩展名规则） |
| Video | .tp | Beyond TV Transport Stream File | ✅ video（扩展名规则） |
| Video | .trp | HD Video Transport Stream | ✅ video（扩展名规则） |
| Video | .ts | Video Transport Stream File | ✅ code、video（扩展名规则） |
| Video | .vb | Beam Game SIFF Video | ✅ code（扩展名规则） |
| Video | .vc1 | VC-1 Video File | ✅ video（扩展名规则） |
| Video | .vid | Bethesda Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .vmd | Sierra VMD Video File | ✅ video（扩展名规则） |
| Video | .vob | DVD Video Object File | ✅ video（扩展名规则） |
| Video | .vp3 | On2 VP3 Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .vp5 | On2 VP5 Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .vp6 | On2 VP6 Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .vp7 | On2 VP7 Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .vqa | Westwood Studios VQA Video | ❌ FFmpeg 无对应 demuxer |
| Video | .vsr | CPCAM CCTV Recording | ❌ FFmpeg 无对应 demuxer |
| Video | .webm | WebM Video File | ✅ video（扩展名规则） |
| Video | .wmv | Windows Media Video File | ✅ video（扩展名规则） |
| Video | .wtv | Windows Recorded TV Show File | ✅ video（扩展名规则） |
| Video | .wve | Electronic Arts TQI Video File | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Video | .xesc | Microsoft Expression Screen Capture Video File | ❌ FFmpeg 无对应 demuxer |
| Video | .xmv | Xbox Media Video File | ✅ video（扩展名规则） |
| Video | .yop | Psygnosis YOP Video | ✅ video（扩展名规则） |
| Archive | .7z | 7-Zip Compressed File | ✅ archive（扩展名规则） |
| Archive | .apk | Android Package | ✅ archive（扩展名规则） |
| Archive | .arj | ARJ Compressed Archive | ✅ archive（扩展名规则） |
| Archive | .bz2 | Bzip2 Compressed Archive | ✅ archive（扩展名规则） |
| Archive | .cab | Windows Cabinet File | ✅ archive（扩展名规则） |
| Archive | .cbr | Comic Book RAR Archive | ✅ mupdf、archive（扩展名规则） |
| Archive | .cbz | Comic Book Zip Archive | ✅ mupdf、archive（扩展名规则） |
| Archive | .chm | Compiled HTML Help File | ✅ chm（扩展名规则） |
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
| Archive | .vhd | Virtual Hard Disk File | ✅ code（扩展名规则） |
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
| Source Code | .asp | Active Server Page | ✅ code（扩展名规则） |
| Source Code | .aspx | Active Server Page Extended File | ✅ code（扩展名规则） |
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
| Source Code | .css | Cascading Style Sheet | ✅ code（扩展名规则） |
| Source Code | .dfm | Delphi Form | ✅ code（扩展名规则） |
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
| Source Code | .nsh | NSIS Header File | ✅ code（扩展名规则） |
| Source Code | .nsi | NSIS Script | ✅ code（扩展名规则） |
| Source Code | .ob2 | Oberon Source Code File | ✅ code（扩展名规则） |
| Source Code | .pas | Pascal Source File | ✅ code（扩展名规则） |
| Source Code | .php | PHP Source Code File | ✅ code（扩展名规则） |
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
| Source Code | .v | Verilog Source Code File | ✅ code（扩展名规则） |
| Source Code | .vb | VBScript File | ✅ code（扩展名规则） |
| Source Code | .vhd | VHDL File | ✅ code（扩展名规则） |
| Source Code | .xml | XML File | ✅ code、web（扩展名规则） |
| Source Code | .xsd | XML Schema Definition | ✅ code（扩展名规则） |
| Source Code | .xsl | XML Style Sheet | ✅ code、web（扩展名规则） |
| Source Code | .xslt | XSL Transformation File | ✅ code、web（扩展名规则） |
| Source Code | .yml | YAML Document | ✅ code（扩展名规则） |
| Web | .asp | Active Server Page script | ✅ code（扩展名规则） |
| Web | .aspx | Active Server Page script | ✅ code（扩展名规则） |
| Web | .css | Cascaded stylesheet | ✅ code（扩展名规则） |
| Web | .htm | HTML page | ✅ web、code（扩展名规则） |
| Web | .html | Hypertext Markup Language File / HTML page | ✅ web、code（扩展名规则） |
| Web | .mht | MHTML Web Archive / Microsoft HTML archive | ✅ web、onlyoffice（扩展名规则） |
| Web | .php | PHP source code | ✅ code（扩展名规则） |
| Web | .shtm | HTML page | ✅ web、code（扩展名规则） |
| Web | .shtml | HTML page | ✅ web、code（扩展名规则） |
| Web | .stm | HTML page | ✅ code（扩展名规则） |
| Web | .xml | XML container | ✅ code、web（扩展名规则） |
| Web | .xsl | XML stylesheet | ✅ code、web（扩展名规则） |
| Documents/Spreadsheets | .cbr | Comic Book archive | ✅ mupdf、archive（扩展名规则） |
| Documents/Spreadsheets | .cbz | Comic Book archive | ✅ mupdf、archive（扩展名规则） |
| Documents/Spreadsheets | .chm | Microsoft HTML Help | ✅ chm（扩展名规则） |
| Documents/Spreadsheets | .diz | Plain text files | ✅ code（扩展名规则） |
| Documents/Spreadsheets | .djv | DejaVu document | ✅ mupdf（扩展名规则） |
| Documents/Spreadsheets | .djvu | DejaVu document | ✅ mupdf（扩展名规则） |
| Documents/Spreadsheets | .doc | Microsoft Word | ✅ onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .docm | Microsoft Word 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .docx | Microsoft Word 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .dot | Microsoft Word | ✅ onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .dotm | Microsoft Word 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .dotx | Microsoft Word 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .epub | ePub e-book | ✅ mupdf（扩展名规则） |
| Documents/Spreadsheets | .fb2 | FictionBook e-book | ✅ mupdf（扩展名规则） |
| Documents/Spreadsheets | .fb2z | FictionBook e-book | ✅ mupdf（扩展名规则） |
| Documents/Spreadsheets | .fbz | FictionBook e-book | ✅ mupdf（扩展名规则） |
| Documents/Spreadsheets | .mobi | Mobipocket e-book | ✅ mupdf（扩展名规则） |
| Documents/Spreadsheets | .nfo | Plain text files | ✅ code（扩展名规则） |
| Documents/Spreadsheets | .pdf | Adobe Portable Document Format | ✅ pdf、pdfjs（扩展名规则） |
| Documents/Spreadsheets | .rtf | Rich Text Format | ✅ onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .tcr | TCR e-book | ✅ mupdf（扩展名规则） |
| Documents/Spreadsheets | .txt | Plain text files | ✅ code（扩展名规则） |
| Documents/Spreadsheets | .wbk | Microsoft Word backup | ✅ onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .xls | Microsoft Excel | ✅ onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .xlsx | Microsoft Excel 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .xlt | Microsoft Excel | ✅ onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .xltx | Microsoft Excel 2007/2010 | ✅ office、onlyoffice（扩展名规则） |
| Documents/Spreadsheets | .xps | Microsoft XML Paper Specification | ✅ mupdf（扩展名规则） |
| Audio/Video | .3g2 | 3GP2 format | ✅ video（扩展名规则） |
| Audio/Video | .3gp | 3GP format | ✅ video（扩展名规则） |
| Audio/Video | .4xm | 4X Technologies format | ✅ video（扩展名规则） |
| Audio/Video | .a64 | a64 - video for Commodore 64 | ❌ FFmpeg 无对应 demuxer |
| Audio/Video | .aac | raw ADTS AAC | ✅ video（扩展名规则） |
| Audio/Video | .ac3 | raw AC-3 | ✅ video（扩展名规则） |
| Audio/Video | .adts | ADTS AAC | ✅ video（扩展名规则） |
| Audio/Video | .aea | MD STUDIO audio | ✅ video（扩展名规则） |
| Audio/Video | .aiff | Audio IFF | ✅ video（扩展名规则） |
| Audio/Video | .alaw | PCM A-law format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .amr | 3GPP AMR file format | ✅ video（扩展名规则） |
| Audio/Video | .anm | Deluxe Paint Animation | ✅ video（扩展名规则） |
| Audio/Video | .apc | CRYO APC format | ✅ video（扩展名规则） |
| Audio/Video | .ape | Monkey's Audio | ✅ video（扩展名规则） |
| Audio/Video | .applehttp | Apple HTTP Live Streaming format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .asf | ASF format | ✅ video（扩展名规则） |
| Audio/Video | .ass | Advanced SubStation Alpha subtitle format | ❌ 字幕文件（播放时内嵌显示） |
| Audio/Video | .au | SUN AU format | ✅ video（扩展名规则） |
| Audio/Video | .avi | AVI format | ✅ video（扩展名规则） |
| Audio/Video | .avm2 | Flash 9 (AVM2) format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .avs | AVISynth | ✅ video（扩展名规则） |
| Audio/Video | .bethsoftvid | Bethesda Softworks VID format | ✅ video（扩展名规则） |
| Audio/Video | .bfi | Brute Force & Ignorance | ✅ video（扩展名规则） |
| Audio/Video | .bink | Bink | ✅ video（扩展名规则） |
| Audio/Video | .c93 | Interplay C93 | ✅ video（扩展名规则） |
| Audio/Video | .caf | Apple Core Audio Format | ✅ video（扩展名规则） |
| Audio/Video | .cavsvideo | raw Chinese AVS video | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .cdg | CD Graphics Format | ✅ video（扩展名规则） |
| Audio/Video | .crc | CRC testing format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .daud | D-Cinema audio format | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Audio/Video | .dirac | raw Dirac | ✅ video（扩展名规则） |
| Audio/Video | .dnxhd | raw DNxHD (SMPTE VC-3) | ✅ video（扩展名规则） |
| Audio/Video | .dsicin | Delphine Software International CIN format | ✅ video（扩展名规则） |
| Audio/Video | .dts | raw DTS | ✅ video（扩展名规则） |
| Audio/Video | .dv | DV video format | ✅ video（扩展名规则） |
| Audio/Video | .dvd | MPEG-2 PS format (DVD VOB) | ❌ FFmpeg 无对应 demuxer |
| Audio/Video | .dxa | DXA | ✅ video（扩展名规则） |
| Audio/Video | .ea | Electronic Arts Multimedia Format | ✅ video（扩展名规则） |
| Audio/Video | .eac3 | raw E-AC-3 | ✅ video（扩展名规则） |
| Audio/Video | .f32be | PCM 32 bit floating-point big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .f32le | PCM 32 bit floating-point little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .f64be | PCM 64 bit floating-point big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .f64le | PCM 64 bit floating-point little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .ffm | FFM (FFserver live feed) format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .ffmetadata | FFmpeg metadata in text format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .filmstrip | Adobe Filmstrip | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .flac | raw FLAC | ✅ video（扩展名规则） |
| Audio/Video | .flic | FLI/FLC/FLX animation format | ✅ video（扩展名规则） |
| Audio/Video | .flv | FLV format | ✅ video（扩展名规则） |
| Audio/Video | .framecrc | framecrc testing format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .framemd5 | Per-frame MD5 testing format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .g722 | raw G.722 | ✅ video（扩展名规则） |
| Audio/Video | .gif | GIF Animation | ✅ image、video（扩展名规则） |
| Audio/Video | .gsm | raw GSM | ✅ video（扩展名规则） |
| Audio/Video | .gxf | GXF format | ✅ video（扩展名规则） |
| Audio/Video | .h261 | raw H.261 | ✅ video（扩展名规则） |
| Audio/Video | .h263 | raw H.263 | ✅ video（扩展名规则） |
| Audio/Video | .h264 | raw H.264 video format | ✅ video（扩展名规则） |
| Audio/Video | .idcin | id Cinematic format | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Audio/Video | .iff | IFF format | ✅ video（扩展名规则） |
| Audio/Video | .image2 | image2 sequence | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .image2pipe | piped image2 sequence | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .ingenient | raw Ingenient MJPEG | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Audio/Video | .ipmovie | Interplay MVE format | ✅ video（扩展名规则） |
| Audio/Video | .ipod | iPod H.264 MP4 format | ❌ FFmpeg 无对应 demuxer |
| Audio/Video | .iss | Funcom ISS format | ✅ code（扩展名规则） |
| Audio/Video | .iv8 | A format generated by IndigoVision 8000 video server | ✅ video（扩展名规则） |
| Audio/Video | .ivf | On2 IVF | ✅ video（扩展名规则） |
| Audio/Video | .lmlm4 | lmlm4 raw format | ✅ video（扩展名规则） |
| Audio/Video | .lxf | VR native stream format (LXF) | ✅ video（扩展名规则） |
| Audio/Video | .m4v | raw MPEG-4 video format | ✅ video（扩展名规则） |
| Audio/Video | .matroska | Matroska file format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .md5 | MD5 testing format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .mjpeg | raw MJPEG video | ✅ video（扩展名规则） |
| Audio/Video | .mlp | raw MLP | ✅ video（扩展名规则） |
| Audio/Video | .mm | American Laser Games MM format | ✅ video（扩展名规则） |
| Audio/Video | .mmf | Yamaha SMAF | ✅ video（扩展名规则） |
| Audio/Video | .mov | MOV format | ✅ video（扩展名规则） |
| Audio/Video | .mp2 | MPEG audio layer 2 | ✅ video（扩展名规则） |
| Audio/Video | .mp3 | MPEG audio layer 3 | ✅ video（扩展名规则） |
| Audio/Video | .mp3id3v1 | MPEG audio layer 3 with id3v1 only | ❌ FFmpeg 无对应 demuxer |
| Audio/Video | .mp3id3v2 | MPEG audio layer 3 with id3v2 only | ❌ FFmpeg 无对应 demuxer |
| Audio/Video | .mp4 | MP4 format | ✅ video（扩展名规则） |
| Audio/Video | .mpc | Musepack | ✅ video（扩展名规则） |
| Audio/Video | .mpc8 | Musepack SV8 | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Audio/Video | .mpeg | MPEG-1 System format | ✅ video（扩展名规则） |
| Audio/Video | .mpeg1video | raw MPEG-1 video | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .mpeg2video | raw MPEG-2 video | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .mpegts | MPEG-2 transport stream format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .mpegtsraw | MPEG-2 raw transport stream format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .mpegvideo | raw MPEG video | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .mpjpeg | MIME multipart JPEG format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .msnwctcp | MSN TCP Webcam stream | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .mtv | MTV format | ✅ video（扩展名规则） |
| Audio/Video | .mulaw | PCM mu-law format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .mvi | Motion Pixels MVI format | ✅ video（扩展名规则） |
| Audio/Video | .mxf | Material eXchange Format | ✅ video（扩展名规则） |
| Audio/Video | .mxg | MxPEG clip file format | ✅ video（扩展名规则） |
| Audio/Video | .nc | NC camera feed format | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Audio/Video | .nsv | Nullsoft Streaming Video | ✅ video（扩展名规则） |
| Audio/Video | .null | raw null video format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .nut | NUT format | ✅ video（扩展名规则） |
| Audio/Video | .nuv | NuppelVideo format | ✅ video（扩展名规则） |
| Audio/Video | .ogg | Ogg | ✅ video（扩展名规则） |
| Audio/Video | .oma | Sony OpenMG audio | ✅ video（扩展名规则） |
| Audio/Video | .psp | PSP MP4 format | ❌ FFmpeg 无对应 demuxer |
| Audio/Video | .psxstr | Sony Playstation STR format | ❌ FFmpeg 无对应 demuxer |
| Audio/Video | .pva | TechnoTrend PVA file and stream format | ✅ video（扩展名规则） |
| Audio/Video | .qcp | QCP format | ✅ video（扩展名规则） |
| Audio/Video | .r3d | REDCODE R3D format | ✅ video（扩展名规则） |
| Audio/Video | .rawvideo | raw video format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .rcv | VC-1 test bitstream | ✅ video（扩展名规则） |
| Audio/Video | .rl2 | RL2 format | ✅ video（扩展名规则） |
| Audio/Video | .rm | RealMedia format | ✅ video（扩展名规则） |
| Audio/Video | .roq | raw id RoQ format | ✅ video（扩展名规则） |
| Audio/Video | .rpl | RPL/ARMovie format | ✅ video（扩展名规则） |
| Audio/Video | .rso | Lego Mindstorms RSO format | ✅ video（扩展名规则） |
| Audio/Video | .rtp | RTP output format | ❌ 网络协议，非文件 |
| Audio/Video | .rtsp | RTSP output format | ❌ 网络协议，非文件 |
| Audio/Video | .s16be | PCM signed 16 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .s16le | PCM signed 16 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .s24be | PCM signed 24 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .s24le | PCM signed 24 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .s32be | PCM signed 32 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .s32le | PCM signed 32 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .s8 | PCM signed 8 bit format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .sap | SAP output format | ❌ 网络协议，非文件 |
| Audio/Video | .sdp | SDP | ❌ 网络协议，非文件 |
| Audio/Video | .shn | raw Shorten | ✅ video（扩展名规则） |
| Audio/Video | .siff | Beam Software SIFF | ✅ video（扩展名规则） |
| Audio/Video | .smk | Smacker video | ✅ video（扩展名规则） |
| Audio/Video | .sol | Sierra SOL format | ✅ video（扩展名规则） |
| Audio/Video | .sox | SoX native format | ✅ video（扩展名规则） |
| Audio/Video | .spdif | IEC 61937 (used on S/PDIF - IEC958) | ✅ video（扩展名规则） |
| Audio/Video | .srt | SubRip subtitle format | ❌ 字幕文件（播放时内嵌显示） |
| Audio/Video | .svcd | MPEG-2 PS format (VOB) | ✅ video（扩展名规则） |
| Audio/Video | .swf | Flash format | ✅ video（扩展名规则） |
| Audio/Video | .thp | THP | ✅ video（扩展名规则） |
| Audio/Video | .tiertexseq | Tiertex Limited SEQ format | ✅ video（扩展名规则） |
| Audio/Video | .tmv | 8088flex TMV | ✅ video（扩展名规则） |
| Audio/Video | .truehd | raw TrueHD | ✅ video（扩展名规则） |
| Audio/Video | .tta | True Audio | ✅ video（扩展名规则） |
| Audio/Video | .tty | Tele-typewriter | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Audio/Video | .txd | Renderware TeXture Dictionary | ⚠️ FFmpeg 可解，未在配置声明（待实测） |
| Audio/Video | .u16be | PCM unsigned 16 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .u16le | PCM unsigned 16 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .u24be | PCM unsigned 24 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .u24le | PCM unsigned 24 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .u32be | PCM unsigned 32 bit big-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .u32le | PCM unsigned 32 bit little-endian format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .u8 | PCM unsigned 8 bit format | ❌ 原始采样流（扩展名不含编码参数） |
| Audio/Video | .vc1 | raw VC-1 | ✅ video（扩展名规则） |
| Audio/Video | .vc1test | VC-1 test bitstream format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .vcd | MPEG-1 System format (VCD) | ✅ video（扩展名规则） |
| Audio/Video | .vfwcap | VFW video capture | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
| Audio/Video | .vmd | Sierra VMD format | ✅ video（扩展名规则） |
| Audio/Video | .vob | MPEG-2 PS format (VOB) | ✅ video（扩展名规则） |
| Audio/Video | .voc | Creative Voice file format | ✅ video（扩展名规则） |
| Audio/Video | .vqf | Nippon Telegraph and Telephone Corporation (NTT) TwinVQ | ✅ video（扩展名规则） |
| Audio/Video | .w64 | Sony Wave64 format | ✅ video（扩展名规则） |
| Audio/Video | .wav | WAV format | ✅ video（扩展名规则） |
| Audio/Video | .wc3movie | Wing Commander III movie format | ✅ video（扩展名规则） |
| Audio/Video | .webm | WebM file format | ✅ video（扩展名规则） |
| Audio/Video | .wsaud | Westwood Studios audio format | ✅ video（扩展名规则） |
| Audio/Video | .wsvqa | Westwood Studios VQA format | ✅ video（扩展名规则） |
| Audio/Video | .wtv | Windows Television (WTV) | ✅ video（扩展名规则） |
| Audio/Video | .wv | WavPack | ✅ video（扩展名规则） |
| Audio/Video | .xa | Maxis XA File Format | ✅ video（扩展名规则） |
| Audio/Video | .yop | Psygnosis YOP Format | ✅ video（扩展名规则） |
| Audio/Video | .yuv4mpegpipe | YUV4MPEG pipe format | ❌ 非文件类型（FFmpeg 流/管线名），无需覆盖 |
