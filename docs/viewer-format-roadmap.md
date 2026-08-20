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
| `inf-dir.code-view` | CodeMirror（WebView2） | Text / Web / Source Code / 配置 / 日志 | 只读文本与代码，语法高亮 + 行号 |
| `inf-dir.markdown-view` | WebView2 | Markdown | 渲染预览 |
| `inf-dir.image-view` | image crate | Image（栅格） | 常用 + 扩展位图 |
| `inf-dir.pdf-view` | PDFium | PDF | PDF 渲染 |
| `inf-dir.office-view` | WebView2 + ooxml | Word/Excel/PowerPoint | OOXML 文档 |
| `inf-dir.video-view` | mpv / libmpv2（FFmpeg） | **Audio + Video** | 全量音视频播放（含字幕） |
| `inf-dir.archive-view` | libarchive | Archive | 归档内容列表 |
| `inf-dir.email-view` | C# / MimeKit / MSGReader / WebView2 | Email | 邮件正文预览 |
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
| code-view | CodeMirror 语言模式 76 项（含 `.txt .log .csv .tsv .cfg .cmd .nfo .diz .shtm .shtml .stm` 纯文本子集，见 `plugins/code-view/plugin.json`） |
| markdown-view | `.md .markdown .mdown .mkd` |
| image-view | `.png .jpg .jpeg .gif .bmp .webp .avif .tiff .tif .ico .hdr .pbm .pgm .ppm .pnm .tga .dds .exr .ff .qoi .svg .svgz` |
| pdf-view | `.pdf` |
| office-view | `.docx .docm .dotx .dotm .xlsx .xlsm .xltx .xltm .pptx .pptm .potx .potm .ppsx .ppsm` |
| video-view | 99 项音视频 + `.gif .apng`（见 `plugins/video-view/plugin.json`） |
| archive-view | 38 项（见 `plugins/archive-view/plugin.json`） |

## 5. P1：扩展现有 viewer

### 5.1 video-view（mpv）—— 覆盖全部 Audio + Video

mpv 内嵌 FFmpeg，扩展名声明几乎无需成本，只需把 manifest 的 `extensions` 扩到 FFmpeg
真实可解码清单。目标把 FVP 的 Audio(59) + Video(96) 与 UV 的 Audio/Video(174) 全部纳入。

- 已完成：`plugins/video-view/plugin.json` 扩展名由 12 → 99 项（`mimeTypes` 增加
  `audio/*`），viewer 更名「媒体查看器」。已声明的 99 项（含 `.gif .apng` 动画图片，
  由 mpv 播放；image-view 保留 `.gif` 作静态首帧回退）：

  `.3ga .3g2 .3gp .8svx .aa .aa3 .aac .ac3 .aif .aifc .aiff .amr .amv .apng .ape .asf .au .avi .bik .caf .divx .dts .dv .dvr-ms .f4v .flac .flc .fli .flv .gif .gsm .gxf .h264 .h265 .hevc .m2t .m2ts .m2v .m4a .m4b .m4r .m4v .mk3d .mka .mkv .mlp .mod .mov .mp1 .mp2 .mp3 .mp4 .mpa .mpc .mpeg .mpg .mts .mxf .nsv .nuv .ogg .ogm .ogv .oma .opus .pva .qcp .ra .rm .rmvb .roq .shn .smk .snd .spx .svcd .swf .tak .thp .tod .tp .trp .ts .tta .vcd .vc1 .vob .voc .vqf .w64 .wav .webm .wma .wmv .wtv .wv .xa .xma .yop`

- 内嵌字幕（mpv 播放时显示）：`.srt .ass .ssa .sub .vtt`

验收：FVP/UV 音视频两类的扩展名解析后均可通过 F3 打开并播放，失败才回退图标。

### 5.2 image-view —— 扩展位图 + 矢量

- 已完成：`plugins/img-view/plugin.json` 扩展名由 11 → 22 项，新增位图解码器
  `pnm`（`.pbm .pgm .ppm .pnm`）、`tga`、`dds`、`exr`、`ff`（farbfeld）、`qoi`
  （image crate 零额外依赖），并新增 `resvg` 矢量后端渲染 `.svg .svgz`（含系统字体加载）。
- 未完成：`pcx`（需第三方 `pcx` 解码）、`icns`。

SVG 引擎权衡：

- resvg/usvg 覆盖 SVG 1.1 静态渲染的绝大部分（形状、路径、渐变、图案、蒙版、裁剪、
  大部分滤镜、`<use>`、`<defs>`、文本与 `textPath`、marker 等），适合 Quick View 只读预览。
- 不支持脚本（`<script>`/事件/SMIL）、SVG 字体、`foreignObject`（内嵌 HTML）、动画
  （`<animate>` 等）及部分 CSS 高级特性；这些场景会渲染不完整或报错。
- 结论：对图标、示意图、Illustrator/Inkscape 导出的静态矢量覆盖良好；若未来需要完整
  SVG 2.0 与动画，改用 WebView2 内核渲染（原生浏览器支持，代价是更重）。当前采用 resvg。

目标覆盖 FVP Image(57) 中除 PSD/JP2/JXL/JXR/DICOM 外的常见项，以及 UV Images(46)
中除 `.cel .cut .icb .pal .ras .rla .rpf .sgi .vda .win .fax` 等冷门外的全部。

### 5.3 code-view —— 补齐 Source Code 全量

- 已完成：`text-view` 插件已移除（纯文本与代码统一走 code-view）。code-view 已补入
  纯文本子集 `.txt .log .csv .tsv .cfg .cmd .nfo .diz .shtm .shtml .stm`（共 76 项），
  `.nfo .diz` 无语法可高亮时由 CodeMirror 以 Plain text 渲染。
- 待补全：把 FVP Source Code(79) 的其余扩展名映射到 CodeMirror 已有语言模式：

`.a2l .ads .ahk .as .asm .asp .aspx .au3 .bas .bpk .bpr .cbl .cfm .cgi .clp .csh .dfm .dpk .dpr .eba .erl .ex .f .haml .hs .inc .inf .iss .iwb .kix .lhs .ml .nsh .nsi .ob2 .pas .pl .pm .pod .prg .rc .sas .scm .ss .st .sty .tcl .v .vhd .xsd .xsl .xslt`

### 5.4 office-view —— 补全 OOXML 模板/放映

- 已完成：`plugins/office-view/plugin.json` 由 6 → 14 项，补齐 Word/Excel/PowerPoint 的
  OOXML 模板与放映类型（OOXML 引擎已支持，仅补 manifest + index.html 分发分支）：
  Word `.dotx .dotm`、Excel `.xltx .xltm`、PowerPoint `.potx .potm .ppsx .ppsm`。
- 未覆盖：旧二进制 `.doc .xls .ppt`（P2）、`.xlsb`（二进制 OOXML，待评估）、
  `.dot .xlt .pot .pps`（旧二进制模板/放映，P2）。

### 5.5 archive-view（libarchive）—— 扩读取格式

- 已完成：`plugins/archive-view/plugin.json` 由 11 → 38 项，补齐 libarchive 已内置的
  读取格式（`archive_read_support_format_all` + `support_filter_all` 已就绪，仅补 manifest）：

`.cpio .xar .rpm .deb .wim .lzma .lz4 .z .lha .lzip .tgz .tbz .tbz2 .txz .tlz .tar.gz .tar.bz2 .tar.xz .ar .zipx .pk3 .pk4 .jar .war .apk .dmg .hfs`

（`.pk3/.pk4/.jar/.war/.apk` 本质是 zip，`.dmg/.hfs` 为磁盘镜像，libarchive 均可读。）

### 5.6 email-view（P1，已完成）

- 已完成：支持 `.eml .emlx .msg .oft .dat`。首版直接声明 `.dat` 扩展名关联，以覆盖
  `winmail.dat`、`win.dat` 和 `ATTxxxxx.dat` 等 TNEF 文件；这会与其他 `.dat` 语义冲突，
  暂接受误命中，待 Viewer 补全后随内容嗅探和 MIME 关联一起修复。
- 实现：C# / .NET 8 `win-x64` self-contained 独立进程，WebView2 渲染邮件头、HTML/纯文本
  正文、CID 内嵌图片和附件列表。MimeKit 负责 EML/TNEF，EMLX 先剥离 Apple 包装再按 EML
  解析，MSGReader 负责 MSG/OFT；第三方 DLL 不加载进 Flutter 主进程。
- 安全边界：默认禁用脚本和远程资源，清洗邮件 HTML；附件导出由宿主进程处理，不向
  WebView 暴露任意文件系统访问。

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
| `.dat` | VCD 视频 / Winmail.dat | 首版直接走 email-view，后续内容嗅探区分 |
| `.cin` | Kodak Cineon 位图 / Delphine CIN 视频 | 内容嗅探 |
| `.iss` | Funcom 音频 / Inno Setup 脚本 | 默认 code-view（Inno Setup 更常见） |
| `.mpc` | Musepack 音频 / EA MPCh 视频 | 均走 mpv（FFmpeg 两者都解码） |
| `.vb` | Beam SIFF 视频 / VBScript | 默认 code-view（VBScript 更常见） |
| `.vhd` | 虚拟硬盘 / VHDL | 默认 code-view（VHDL），虚拟硬盘走 archive-view |

## 8. 覆盖矩阵（目标态）

| 类别（FVP/UV） | 总量 | 主要 viewer | 阶段 |
| --- | ---: | --- | --- |
| Source Code | 79 | code-view | P0 部分 / P1 补全 |
| Text | 13 | code-view | P0 |
| Web / Internet | 2 / 12 | code-view | P0 |
| PDF | 1 | pdf-view | P0 |
| XPS | 2 | xps-view | P2 |
| Spreadsheet | 8 | office-view | P0(OXML) / P1(模板已扩展) / P2(legacy .xls) |
| Presentation | 9 | office-view | P0 / P1(模板放映已扩展) / P2(legacy .ppt) |
| Image | 57 | image-view | P0(11) / P1(位图+矢量已扩展) / P2(psd/jp2/jxl/dcm 等) |
| Camera Raw / RAW | 30 / 36 | raw（并入 image-view） | P2 |
| Audio | 59 | video-view（mpv） | P1（已完成） |
| Video | 96 | video-view（mpv） | P0(12) / P1 补全（已完成） |
| Archive | 39 | archive-view | P0(11) / P1 补全（已完成） |
| Email | 5 | email-view | P1（已完成；`.dat` 临时直接关联，后续内容嗅探） |
| Visio | 12 | visio-view | P2 |
| Project | 3 | project-view | P2 |
| CAD | 2 | cad-view | P2 |

## 9. 里程碑

1. **M1（P1 主体）**：video-view 全量音视频 + image-view 扩展 + code-view 源码补全 +
   archive-view 扩展 + office-view 模板。完成后 FVP/UV 两数据源除 Image 冷门、RAW、XPS、
   Email、Visio、Project、CAD 外的全部扩展名均可用 F3 打开。
2. **M2（P1 收尾 + 长尾入口）**：email-view（eml/emlx/msg/oft/TNEF）已完成；后续补冲突
   扩展名内容嗅探和 "暂不支持"占位提示（mpp/dwg 等先给出可理解反馈）。
3. **M3（P2 按需）**：raw 支持 → xps-view → djvu/font/ebook → visio/cad/project（按用户
   需求与授权评估逐个落地）。

## 10. 验收标准

- 每个阶段落地后，对应扩展名经关联解析（路径/文件名/扩展名/MIME 规则树）命中正确 viewer；
- 独立进程启动失败、插件缺失、格式不支持均给出可见反馈（toast），不回退主进程 DLL；
- 冲突扩展名（`.dat .cin .iss .mpc .vb .vhd`）有内容嗅探或默认规则，用户可经关联配置覆盖；
- 新增扩展名同步更新 `plugin.json`（规范化：小写、点前缀、复合后缀如 `.tar.gz`）；
- `flutter analyze` / `flutter test` 通过；Rust 插件 `cargo build --release`、email-view 的
  `npm run build` / `dotnet publish` 与解析自检通过。

## 11. Viewer 补全后处理的覆盖审计项

> 记录于 2026-08-20。以下问题不阻塞当前 Viewer 补全工作；待 M1-M3 的 Viewer 与
> manifest 补齐后统一处理，避免在格式实现阶段反复调整关联和发布逻辑。

1. **区分引擎能力与关联覆盖**：当前源码 manifest 共声明 252 个唯一扩展名。按扩展名
   与参考清单直接比对，命中 FVP 182/411（44.3%）、UV 85/294（28.9%）。mpv、libarchive
   等引擎能够解析的格式多于 manifest 可命中的格式，因此路线图中的“全量”或“已完成”
   需要在 Viewer 补齐后重新校准。最终验收同时检查“引擎可解析”和“F3 可命中”，并用
   代表性样本实测，不能只统计后端库的理论格式数。
2. **补充真实关联冲突**：除第 7 节列出的冲突外，当前 manifest 还同时声明了 `.gif`
   （image-view / video-view）和 `.ts`（code-view / video-view）。默认 Viewer 按显示名称排序，
   因而 `.gif` 先进入 image-view、`.ts` 先进入 code-view；这与动画 GIF 交给 mpv 的预期不完全
   一致。后续明确默认语义、回退顺序或内容嗅探规则，并补关联解析测试。
3. **收紧 MIME 通配边界**：`MimeTypeService` 读取 Windows 按扩展名注册的 Content Type，
   不是内容嗅探。`image/*`、`audio/*`、`video/*` 可能让未显式声明的文件偶然命中，也可能
   把后端无法解码的格式送入 Viewer。email-view 首版还会临时直接关联 `.dat`，因此普通
   二进制或 VCD `.dat` 也可能误命中。Viewer 补全后再定义统一的内容探测、误命中回退和
   无扩展名文件策略，并用 TNEF 文件签名替代 `.dat` 的无条件关联。
4. **清理构建产物漂移**：本地 `plugins/dist/` 可能残留已从源码移除的插件，例如
   `inf-dir.text-view`。`plugins/build.bat` 当前不会清空废弃插件目录，而 Windows 发布会安装
   整个 `plugins/dist/`。后续为构建增加受控清理或产物白名单，并增加源码 manifest 与 dist
   插件集合一致性测试，避免旧 Viewer 被开发环境或发布包继续加载。
5. **补充文本编码覆盖**：code-view 当前明确处理 UTF-8 与带 BOM 的 UTF-16 LE/BE；GBK、
   Shift-JIS、Windows-1252 等旧日志和源码可能乱码。Viewer 补全后评估编码探测、手动切换
   编码及相应测试样本。
