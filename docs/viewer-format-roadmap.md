# Inf-Dir Viewer 格式覆盖路线图

本文基于两份第三方格式调研数据（`docs/file-type-reference/` 的 File Viewer Plus、
`docs/uvviewer-formats/` 的 Universal Viewer），规划 Inf-Dir Quick View viewer 插件的
格式覆盖阶段。规划遵循 `docs/plugin-system.md` 的 manifest 驱动、独立进程、递归规则树
关联体系，不引入主进程第三方 DLL。

## 1. 数据源与目标

| 数据源 | 条目 / 唯一扩展名 | 分类粒度 |
| --- | ---: | --- |
| File Viewer Plus（FVP） | 417 / 411 | Text、PDF & XPS、Spreadsheet、Presentation、Visio、Project、CAD、Email、Image、Camera Raw、Audio、Video、Archive、Source Code、Web |
| Universal Viewer（UV） | 296 / 294 | Documents/Spreadsheets、Internet、Images、RAW Images、Audio/Video |

两者的 Audio/Video 部分高度重合，且 UV 的 174 条 A/V 与 FFmpeg demuxer 清单一致；
Image/RAW、Source Code、Archive 也有大量交集。因此**单一 viewer 往往能承载一整类格式**，
规划按"viewer 角色"而非"逐扩展名"组织。

## 2. Viewer 角色与引擎

| Viewer（plugin id） | 引擎 | 承担类别 | 定位 |
| --- | --- | --- | --- |
| `inf-dir.text-view` | two-face | Text / Web / 配置 / 日志 | 轻量文本，无行号，快速打开 |
| `inf-dir.code-view` | CodeMirror（WebView2） | Source Code | 只读代码，语法高亮 + 行号 |
| `inf-dir.markdown-view` | WebView2 | Markdown | 渲染预览 |
| `inf-dir.image-view` | image crate | Image（栅格） | 常用 + 扩展位图 |
| `inf-dir.pdf-view` | PDFium | PDF | PDF 渲染 |
| `inf-dir.office-view` | WebView2 + ooxml | Word/Excel/PowerPoint | OOXML 文档 |
| `inf-dir.video-view` | mpv / libmpv2（FFmpeg） | **Audio + Video** | 全量音视频播放（含字幕） |
| `inf-dir.archive-view` | libarchive | Archive | 归档内容列表 |
| `inf-dir.email-view`（新增） | mail-parser / WebView2 | Email | 邮件正文预览 |
| `inf-dir.raw-view`（并入 image-view） | rawloader | Camera Raw / RAW | 相机原始格式 |
| `inf-dir.xps-view`（新增） | 系统 XPS / 自研 | PDF & XPS 中的 XPS | XPS/OXPS |
| `inf-dir.cad-view` / `visio-view` / `font-view` / `djvu-view` / `ebook-view`（新增） | 见 P2 | CAD / Visio / 字体 / DjVu / 电子书 | 长尾 |

> 说明：mpv 是"一 viewer 多角色"的典型——它内嵌 FFmpeg，可同时覆盖 Audio 与 Video 两个
> 大类；`image-view` 与 `archive-view` 同理，通过开启/新增后端库扩展而无需新建插件进程。

## 3. 阶段定义

- **P0（基线）**：已实现并随当前构建分发，见各 `plugin.json` 的 `extensions`。
- **P1（扩展现有 viewer）**：在不新增插件进程的前提下，扩展现有 manifest 的扩展名与
  后端能力，优先收割高频格式与长尾中的常见项。
- **P2（新增 viewer / 长尾）**：需要新引擎（或高成本解析库）的类别，按需逐个落地。

## 4. P0：当前基线（已实现）

| Viewer | 已声明扩展名 |
| --- | --- |
| text-view | `.txt .md .log .csv .json .xml .yaml .yml .ini .conf .cfg .bat .cmd .ps1 .sh .dart .py .js .ts .rs .go .c .cpp .h .hpp .java .cs .html .css .sql .toml .gradle .properties`（+ `.env .gitignore dockerfile`） |
| code-view | CodeMirror 语言模式约 70 项（见 `plugins/code-view/plugin.json`） |
| markdown-view | `.md .markdown .mdown .mkd` |
| image-view | `.png .jpg .jpeg .gif .bmp .webp .avif .tiff .tif .ico .hdr` |
| pdf-view | `.pdf` |
| office-view | `.docx .xlsx .pptx .docm .xlsm .pptm` |
| video-view | 97 项音视频（见 `plugins/video-view/plugin.json`） |
| archive-view | `.zip .7z .rar .tar .gz .xz .bz2 .iso .cab .arj .lzh` |

## 5. P1：扩展现有 viewer

### 5.1 video-view（mpv）—— 覆盖全部 Audio + Video

mpv 内嵌 FFmpeg，扩展名声明几乎无需成本，只需把 manifest 的 `extensions` 扩到 FFmpeg
真实可解码清单。目标把 FVP 的 Audio(59) + Video(96) 与 UV 的 Audio/Video(174) 全部纳入。

- 已完成：`plugins/video-view/plugin.json` 扩展名由 12 → 97 项（`mimeTypes` 增加
  `audio/*`），viewer 更名「媒体查看器」。已声明的 97 项：

  `.3ga .3g2 .3gp .8svx .aa .aa3 .aac .ac3 .aif .aifc .aiff .amr .amv .ape .asf .au .avi .bik .caf .divx .dts .dv .dvr-ms .f4v .flac .flc .fli .flv .gsm .gxf .h264 .h265 .hevc .m2t .m2ts .m2v .m4a .m4b .m4r .m4v .mk3d .mka .mkv .mlp .mod .mov .mp1 .mp2 .mp3 .mp4 .mpa .mpc .mpeg .mpg .mts .mxf .nsv .nuv .ogg .ogm .ogv .oma .opus .pva .qcp .ra .rm .rmvb .roq .shn .smk .snd .spx .svcd .swf .tak .thp .tod .tp .trp .ts .tta .vcd .vc1 .vob .voc .vqf .w64 .wav .webm .wma .wmv .wtv .wv .xa .xma .yop`

- 内嵌字幕（mpv 播放时显示）：`.srt .ass .ssa .sub .vtt`

验收：FVP/UV 音视频两类的扩展名解析后均可通过 F3 打开并播放，失败才回退图标。

### 5.2 image-view —— 扩展位图 + 矢量

- 启用 image crate 额外解码器：`pnm`（`.pbm .pgm .ppm .pnm`）、`tga`、`exr`、`qoi`、
  `farbfeld`（`.ff`）、`pcx`（第三方 `pcx` 解码）。
- 新增矢量后端 resvg/usvg：`.svg .svgz`。
- 新增 `dds`（image-dds）、`icns`。

目标覆盖 FVP Image(57) 中除 PSD/JP2/JXL/JXR/DICOM 外的常见项，以及 UV Images(46)
中除 `.cel .cut .icb .pal .ras .rla .rpf .sgi .vda .win .fax` 等冷门外的全部。

### 5.3 code-view —— 补齐 Source Code 全量

把 FVP Source Code(79) 的扩展名映射到 CodeMirror 已有语言模式，manifest 补全：

`.a2l .ads .ahk .as .asm .asp .aspx .au3 .bas .bat .bpk .bpr .c .cbl .cfg .cfm .cgi .clp .cmake .cmd .cpp .cs .csh .css .dfm .dpk .dpr .eba .erl .ex .f .h .haml .hpp .hs .inc .inf .ini .iss .iwb .java .js .json .kix .lhs .log .lua .ml .nsh .nsi .ob2 .pas .php .pl .pm .pod .prg .ps1 .py .r .rb .rc .sas .scm .sh .sql .ss .st .sty .tcl .tex .v .vb .vhd .xml .xsd .xsl .xslt .yml`

同时 `text-view` 增加 `.diz .nfo .tsv .shtm .shtml .stm`（纯文本子集），与 code-view
按关联规则顺序共存（code-view 优先，text-view 回退）。

### 5.4 office-view —— 补全 OOXML 模板/放映

- Word：`.dotx .dotm .dot`
- Excel：`.xltx .xltm .xlt .xlsb`
- PowerPoint：`.potx .potm .ppsx .ppsm .pot .pps`

（OOXML 全部由现有 ooxml 引擎支持，仅需补 manifest。）

### 5.5 archive-view（libarchive）—— 扩读取格式

libarchive 已内置以下读取器，仅补 manifest：

`.cpio .xar .rpm .deb .wim .lzma .lz4 .z .lha .lzip .tgz .tbz .tbz2 .txz .tlz .tar.gz .tar.bz2 .tar.xz .ar .zipx .pk3 .pk4 .jar .war .apk .dmg .hfs`

（`.pk3/.pk4/.jar/.war/.apk` 本质是 zip，`.dmg/.hfs` 为磁盘镜像，libarchive 均可读。）

### 5.6 新增 email-view（P1）

- 范围：`.eml .emlx`（纯文本 MIME，mail-parser 即可）、`.dat`（winmail，低优先级）。
- `.msg .oft`（OLE 复合文档）依赖 COM/第三方解析，先放入 P2，P1 仅做扩展名登记与
  "暂不支持"提示。
- 实现：WebView2 渲染 HTML 正文 + 附件列表；不加载第三方 DLL 进主进程。

## 6. P2：新增 viewer 覆盖长尾

| 新 viewer | 覆盖格式 | 引擎建议 |
| --- | --- | --- |
| raw（并入 image-view） | `.cr2 .cr3 .nef .arw .dng .raf .orf .rw2 .pef .srw .x3f .erf .rwl .dcr .mrw .kdc .mos .mef .srf .3fr .fff .iiq .raw .nrw .orf`（FVP Camera Raw 30 + UV RAW 36 的全集） | rawloader / dcraw |
| xps-view | `.xps .oxps` | 系统 XPS 或自研（WebView2 不支持，需评估） |
| cad-view | `.dwg .dxf` | libdxfrw / ODA（商用，需授权评估） |
| visio-view | `.vsd .vsdx .vst .vss .vdx .vdw .vsx .vtx .vstx .vssx .vstm .vsdm` | 解析 vsdx（OOXML）优先，vsd 二进制延后 |
| project-view | `.mpp .mpt .mpx` | 低优先级，可先登记"暂不支持" |
| font-view | `.ttf .otf .woff .woff2 .ttc .dfont` | fontdue / freetype |
| djvu-view | `.djvu .djv` | djvulibre |
| ebook-view | `.epub .mobi .fb2 .fbz .fb2z .tcr`（epub 可先由 office-view/html 渲染） | epub=zip+html，mobi/fb2 独立 |
| 图像补充 | `.psd .jp2 .j2k .jxl .jxr .dcm .dpx .cin .sgi .rgb .xpm .xbm .xface .dds(未覆盖部分) .exr` | psd-rs / openjpeg / jxl-rs / dicom / openexr |

## 7. 同名冲突扩展名

两数据源存在 6 个同名不同义扩展名，解析时需按上下文（MIME / 内容嗅探 / 扩展名规则树
子规则）区分，默认取最常见语义，其余以用户关联规则覆盖：

| 扩展名 | 冲突语义 | 默认处理 |
| --- | --- | --- |
| `.dat` | VCD 视频 / Winmail.dat | 内容嗅探，视频走 video-view |
| `.cin` | Kodak Cineon 位图 / Delphine CIN 视频 | 内容嗅探 |
| `.iss` | Funcom 音频 / Inno Setup 脚本 | 默认 code-view（Inno Setup 更常见） |
| `.mpc` | Musepack 音频 / EA MPCh 视频 | 均走 mpv（FFmpeg 两者都解码） |
| `.vb` | Beam SIFF 视频 / VBScript | 默认 code-view（VBScript 更常见） |
| `.vhd` | 虚拟硬盘 / VHDL | 默认 code-view（VHDL），虚拟硬盘走 archive-view |

## 8. 覆盖矩阵（目标态）

| 类别（FVP/UV） | 总量 | 主要 viewer | 阶段 |
| --- | ---: | --- | --- |
| Source Code | 79 | code-view（text-view 回退） | P0 部分 / P1 补全 |
| Text | 13 | text-view / code-view | P0 |
| Web / Internet | 2 / 12 | text-view / code-view | P0 |
| PDF | 1 | pdf-view | P0 |
| XPS | 2 | xps-view | P2 |
| Spreadsheet | 8 | office-view | P0(OXML) / P1(模板) / P2(legacy .xls) |
| Presentation | 9 | office-view | P0 / P1 / P2(legacy .ppt) |
| Image | 57 | image-view | P0(11) / P1(补常见) / P2(psd/jp2/jxl/dcm 等) |
| Camera Raw / RAW | 30 / 36 | raw（并入 image-view） | P2 |
| Audio | 59 | video-view（mpv） | P1（已完成） |
| Video | 96 | video-view（mpv） | P0(12) / P1 补全（已完成） |
| Archive | 39 | archive-view | P0(11) / P1 补全 |
| Email | 5 | email-view | P1(eml/emlx) / P2(msg/oft) |
| Visio | 12 | visio-view | P2 |
| Project | 3 | project-view | P2 |
| CAD | 2 | cad-view | P2 |

## 9. 里程碑

1. **M1（P1 主体）**：video-view 全量音视频 + image-view 扩展 + code-view 源码补全 +
   archive-view 扩展 + office-view 模板。完成后 FVP/UV 两数据源除 Image 冷门、RAW、XPS、
   Email、Visio、Project、CAD 外的全部扩展名均可用 F3 打开。
2. **M2（P1 收尾 + 长尾入口）**：email-view(eml/emlx) + 冲突扩展名内容嗅探 + "暂不支持"
   占位提示（msg/oft/mpp/dwg 等先给出可理解反馈）。
3. **M3（P2 按需）**：raw 支持 → xps-view → djvu/font/ebook → visio/cad/project（按用户
   需求与授权评估逐个落地）。

## 10. 验收标准

- 每个阶段落地后，对应扩展名经关联解析（路径/文件名/扩展名/MIME 规则树）命中正确 viewer；
- 独立进程启动失败、插件缺失、格式不支持均给出可见反馈（toast），不回退主进程 DLL；
- 冲突扩展名（`.dat .cin .iss .mpc .vb .vhd`）有内容嗅探或默认规则，用户可经关联配置覆盖；
- 新增扩展名同步更新 `plugin.json`（规范化：小写、点前缀、复合后缀如 `.tar.gz`）；
- `flutter analyze` / `flutter test` 通过，插件 `cargo build --release` 通过。
