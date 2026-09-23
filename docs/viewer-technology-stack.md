# Inf-Dir Viewer 格式与技术栈记录

本文以当前源码中的 `plugins/*/plugin.json`、构建脚本和各 Viewer 工程文件为准，记录 Quick View 的格式覆盖、解析路径、运行时依赖和发布产物。

## 1. 总体架构

- Flutter 主进程只负责发现 manifest、解析关联、启动和管理 Viewer 进程，不加载第三方 DLL。
- 每个 Viewer 是独立的 Rust 或 .NET Windows 进程，入口由插件目录中的 `plugin.json` 声明。
- `plugins/build.bat` 负责准备外部运行时、构建 Viewer，并把产物安装到 `plugins/dist/<plugin-id>/`。
- `viewer-web-shell` 提供共享的 winit/wry 窗口、窗口定位、导航限制和本地协议基础；HTML/SVG、Markdown、CHM 等 viewer 只保留自己的页面和格式路由。
- WebView2 Viewer 使用本地静态资源和本地协议，不把文档内容交给 Flutter 主进程处理。
- 需要原生 DLL 或大型运行时的格式，优先放在对应 Viewer 目录中隔离发布；格式声明本身只写在 manifest 中。

状态说明：

- **已接入**：manifest 已声明，代码和构建路径已存在。
- **已接入（转换）**：打开前需要调用外部工具或生成临时中间文件。
- **已接入（后备）**：当前 Viewer 能力存在，但可能与另一个 Viewer 形成关联候选，需要在设置中调整顺序。
- **未接入**：当前没有可用的 Quick View manifest 或解析路径。

## 2. 重点格式覆盖

| 格式/类别 | 当前 Viewer | 状态 | 实际处理路径 | 主要依赖 |
| --- | --- | --- | --- | --- |
| PDF | `pdf-view`、`pdfjs-view` | 已接入，两个候选 | 原生 PDFium 渲染，或 WebView2 内嵌 pdf.js | `pdfium.dll`；WebView2；pdf.js 静态资源 |
| EPUB | `ebook-view` | 已接入 | foliate-js 直接排版 | WebView2；`ebook-view-web/` 静态资源 |
| MOBI | `ebook-view` | 已接入 | foliate-js `mobi.js`（内容嗅探 MOBI/KF8） | WebView2；`ebook-view-web/` 静态资源 |
| FB2 | `ebook-view` | 已接入 | foliate-js `fb2.js` | WebView2；`ebook-view-web/` 静态资源 |
| FBZ / FB2Z | `ebook-view` | 已接入（转换） | `.fbz` 由 foliate-js 页面内解压（`view.js` 的 `isFBZ`）；`.fb2z` 在 Rust 启动层从 ZIP 中提取 `.fb2` 后交给 foliate-js | foliate-js 内置 zip.js；Rust `zip` crate |
| TCR | `ebook-view` | 已接入（转换） | 解压 TCR 字典格式为临时 HTML，再交给 foliate-js 的 `html-book.js` | Rust 内置字节解析 |
| CBZ | `ebook-view`、`archive-view` | 已接入，两个候选 | foliate-js `comic-book.js` 渲染；archive-view 可列出归档内容 | WebView2；libarchive |
| CBR | `ebook-view`、`archive-view` | 已接入（转换） | `ebook-view` 启动旁边的 `archive-view.exe --extract-comic`，用 libarchive 解包图片，按自然序重新打包临时 CBZ 后交给 foliate-js | `archive-view.exe` + `archive.dll`；无需新增 RAR 二进制 |
| DjVu / DJV | `ebook-view` | 已接入（转换） | DjVuLibre `ddjvu.exe` 转 PDF，再交给 foliate-js 自带的 pdf.js | 共享 DjVuLibre 运行时（`inf-dir.runtime/`） |
| XPS / OXPS | `pdfjs-view` | 已接入（转换） | 共享运行时里的 GhostXPS `gxpswin64.exe -sDEVICE=pdfwrite` 转 PDF，再交给 pdf.js | 共享 GhostXPS 运行时（`inf-dir.runtime/`） |
| CHM | `chm-view`（CHMate） | 已接入 | CHMate 纯 JS ITSF/ITSP/PMGL + LZX 解析和安全 HTML 渲染，接入现有 WebView2 Viewer 壳 | CHMate（MIT）；WebView2 |
| SVG / SVGZ | `img-view`、`web-view`（`.svg` 还有 `code-view`） | 已接入，多候选 | image-view/resvg 静态渲染，或 WebView2 浏览器语义渲染，或 CodeMirror 源码查看 | `resvg`；WebView2 |
| HTML / XHTML / SHTML | `web-view`、`code-view` | 已接入，两个候选 | WebView2 受限本地资源渲染，或 CodeMirror 源码查看 | WebView2；本地协议路由 |
| MHTML / MHT | `web-view`、`pdfjs-view` | 已接入（转换） | 页面层解析 multipart/related，将 HTML、图片、CSS 和字体转换为 Blob 后渲染；`pdfjs-view` 用 LibreOffice 转 PDF 兜底 | WebView2；内置 MHTML 解析器；LibreOffice |
| 旧 Office：DOC/PPT 等 | `pdfjs-view` | 已接入（转换） | 调用共享运行时里的 `soffice --headless --convert-to pdf`，产物交给 pdf.js | 共享 LibreOffice 运行时（`inf-dir.runtime/`） |
| 旧表格：XLS/XLT/XLSB/ODS/OTS | `excel-view`、`pdfjs-view` | 已接入（转换） | `excel-view` 先用 `soffice --convert-to xlsx` 归一成 OOXML 再走 Web 渲染器；失败时由 `pdfjs-view` 转 PDF 兜底 | WebView2；`@silurus/ooxml`；共享 LibreOffice 运行时 |
| OOXML 表格：XLSX/XLSM/XLTX/XLTM | `excel-view`、`pdfjs-view` | 已接入，两个候选 | WebView2 加载本地 OOXML 表格渲染器；`pdfjs-view` 作为转 PDF 兜底候选 | WebView2；`@silurus/ooxml` 静态资源 |
| OOXML 文档/演示：DOCX/PPTX 等 | `pdfjs-view` | 已接入（转换） | LibreOffice 转 PDF 后由 pdf.js 渲染 | 共享 LibreOffice 运行时（`inf-dir.runtime/`） |
| CAD：DXF/DWG | `pdfjs-view` | 已接入（转换） | LibreOffice Draw 导入后 `soffice --convert-to pdf`，由 pdf.js 渲染 | 共享 LibreOffice 运行时（`inf-dir.runtime/`） |
| Visio：VSD/VSDX 等 | `web-view` | 已接入（转换） | `soffice --headless --convert-to svg` 导出 SVG，由 WebView2 按现有 SVG 页面渲染 | 共享 LibreOffice 运行时（`inf-dir.runtime/`）；WebView2 |
| 图片与 RAW | `img-view` | 已接入 | Rust 原生解码；SVG 用 resvg；V.Flash PTX 由内置 BGR555 解码；RAW 先按内容识别，再走 ImageMagick 的 LibRaw-backed RAW coder，必要时强制 `dng:` 入口，最后读取嵌入 JPEG 预览；manifest 扩展名清单已覆盖现代 RAW 与常见图片别名（`.icon` `.jfif` `.dib` 等） | `image`、`resvg`；ImageMagick（含 LibRaw RAW delegate）、Compface |
| 音频/视频 | `video-view` | 已接入 | libmpv2 渲染和播放 | `libmpv2`；发布时附带 `libmpv-2.dll` |
| 压缩包 | `archive-view` | 已接入 | libarchive 枚举并显示归档内容 | `archive.dll`（libarchive） |
| 邮件：EML/EMLX/MSG/OFT/TNEF | `email-view` | 已接入 | Rust 壳调用 .NET AOT 无头解析器，WebView2 渲染正文 | MimeKit；MSGReader；WebView2；DOMPurify |
| 字体：TTF/OTF/WOFF/WOFF2/TTC/DFONT | `font-view` | 已接入 | Rust 剥出 DFONT 内的 sfnt 流，WebView2 用 `@font-face` 显示字体预览 | WebView2（DirectWrite 渲染） |
| Project：MPP/MPT/MPX | `project-view` | 已接入 | mpxj-rs 读取任务、时间、层级和前置关系；Rust/WebView2 + dhtmlxGantt 渲染 | mpxj-rs 0.1.1；dhtmlxGantt Community 10.0.2 |

## 3. Viewer 工程技术栈

| 插件 | 语言/窗口层 | 核心库 | 随包或系统依赖 | 主要格式 |
| --- | --- | --- | --- | --- |
| `inf-dir.code-view` | Rust + winit/wry/WebView2 | CodeMirror 6、Lezer | WebView2；CodeMirror Web bundle | 代码、文本、JSON、HTML、CSS、配置和日志 |
| `inf-dir.markdown-view` | Rust + winit/wry/WebView2 | markdown-it、highlight.js、KaTeX、Mermaid、GitHub Markdown CSS | WebView2；Markdown 静态资源 | Markdown |
| `inf-dir.image-view` | Rust + egui/eframe | image、resvg | ImageMagick（含 LibRaw RAW delegate）、Compface | 常用位图、SVG、相机 RAW、专业图像格式（HEIF/AVIF、JPEG XL、WebP 由后端能力覆盖） |
| `inf-dir.pdf-view` | Rust + egui/eframe | pdfium-render | `pdfium.dll`，默认构建 PDFium 7881 x64 | PDF |
| `inf-dir.pdfjs-view` | Rust + winit/wry/WebView2 | Mozilla pdf.js 6.2.108 | WebView2；pdf.js `web/` 和 `build/` 资源；Office/ODF/CAD 取自共享 LibreOffice 运行时、XPS/OXPS 取自共享 GhostXPS 运行时 | PDF，以及经转换的 Office/ODF/RTF/WPS/MHT/CAD/XPS |
| `inf-dir.excel-view` | Rust + winit/wry/WebView2 | `@silurus/ooxml` WASM/Web 渲染器 | WebView2；`excel-view-web/`；`xls/xlt/xlsb/ods/ots` 取自共享 LibreOffice 运行时 | XLSX/XLSM/XLTX/XLTM，以及经转换的 XLS/XLT/XLSB/ODS/OTS |
| `inf-dir.archive-view` | Rust + egui/eframe | libarchive、egui_ltreeview | `archive.dll` | ZIP/7z/RAR/TAR/ISO 等归档内容 |
| `inf-dir.video-view` | Rust + egui/eframe | libmpv2 | `libmpv-2.dll`；mpv/FFmpeg 能力由 DLL 提供 | 音频、视频、动图 |
| `inf-dir.email-view` | Rust + viewer-web-shell/wry/WebView2 | 解析子进程 `email-parse.exe`（Native AOT .NET 8）：MimeKit 4.17.0、MSGReader 6.0.7 | WebView2；本地 HTML/CSS/JS；DOMPurify | EML/EMLX/MSG/OFT/TNEF |
| `inf-dir.font-view` | Rust + viewer-web-shell/wry/WebView2 | 自研 DFONT 剥壳（`src/dfont.rs`） | WebView2 | 字体预览 |
| `inf-dir.project-view` | Rust + winit/wry/WebView2 | mpxj-rs 0.1.1；dhtmlxGantt Community 10.0.2 | 单一原生 EXE；WebView2 Runtime | Microsoft Project |
| `inf-dir.ebook-view` | Rust + winit/wry/WebView2 | foliate-js fork（新增 HTML book 适配） | WebView2；随包发布的 `ebook-view-web/` 静态资源（submodule = fork）；DjVu 转换用共享的 DjVuLibre 运行时 | EPUB、MOBI、AZW/AZW3、FB2/FBZ/FB2Z、CBZ、DjVu、TCR、CBR |
| `inf-dir.chm-view` | Rust + winit/wry/WebView2 | CHMate ES modules | WebView2；随包发布的 `chm-view-web/` 静态资源 | CHM |
| `inf-dir.web-view` | Rust + viewer-web-shell/wry/WebView2 | 浏览器原生 HTML/SVG；内置 MHTML 解析器 | WebView2；随包发布的 `web-view-web/` 静态资源；Visio 转换取自共享 LibreOffice 运行时 | SVG、HTML、XHTML、MHTML、Visio（转 SVG） |

## 4. 构建和运行时依赖清单

### 4.1 Rust 通用依赖

- `eframe` / `egui`：原生 Viewer 窗口和绘制。
- `winit` + `wry`：WebView2 Viewer 的窗口和本地资源协议。
- `viewer-window-placement`：统一处理 Viewer 窗口位置参数。
- `serde` / `serde_json`：窗口位置和协议数据。

Rust 原生 Viewer 的第三方 DLL 只在对应插件进程内加载，不进入 Flutter 主进程。

### 4.2 WebView2 运行时

以下插件需要系统 WebView2 Runtime：

- `code-view`
- `markdown-view`
- `excel-view`
- `pdfjs-view`
- `chm-view`
- `email-view`
- `font-view`

Windows 11 通常自带，Windows 10 依赖 Edge/WebView2 Runtime 安装状态。Web Viewer 的 JS/CSS/WASM 资源必须随插件目录发布，不能依赖外网。

### 4.3 原生或外部运行时

| 运行时 | 使用者 | 发布方式 |
| --- | --- | --- |
| PDFium 7881 x64 | `pdf-view` | `pdfium.dll` 放在 `inf-dir.pdf-view/` |
| libmpv2 / FFmpeg | `video-view` | `libmpv-2.dll` 放在 `inf-dir.video-view/` |
| libarchive | `archive-view`、CBR 解包 | `archive.dll` 放在 `inf-dir.archive-view/`；CBR 通过相邻进程复用 |
| 7-Zip Extra `7za.exe` | archive 操作插件、部分转换兜底 | `inf-dir.7z-archive/`；主要格式是 7z/zip，不替代 libarchive 的 RAR 解包路径 |
| DjVuLibre | `ebook-view` | 共享运行时 `inf-dir.runtime/djvulibre/`，核心是 `ddjvu.exe` |
| GhostXPS 10.08.0 | `pdfjs-view` | 共享运行时 `inf-dir.runtime/gxps/`，用 `gxpswin64.exe -sDEVICE=pdfwrite` 把 XPS/OpenXPS 转 PDF；内含 `gxpsdll64.dll` 与全部许可文件，随包的示例 `.xps` 不发布 |
| LibreOffice 26.2.5 | `pdfjs-view`、`excel-view`、`web-view` | 共享运行时 `inf-dir.runtime/libreoffice/`，调用 `program/soffice.exe`；压缩包不是上游发布，按 SHA-256 固定 |
| ImageMagick | `img-view` | `img-view/magick/`，作为解码失败时的子进程 |
| Compface | `img-view` | `img-view/compface/`，用于 X-Face |
| LibRaw decoder | `img-view` 构建辅助 | `img-view/libraw-decoder/`（`libraw-decoder.exe` + `libraw.dll`，LibRaw 0.22.2 Win64 官方包）；保留独立 wrapper 供诊断和后续回退，当前运行时由 ImageMagick 的 RAW delegate 负责解码 |
| CHMate reader | `chm-view` | `chm-view-web/` 中的静态 ES modules，无额外运行时 |

### 4.4 运行时与发布

- `email-view` 外壳是 Rust（viewer-web-shell）；随包的 `email-parse.exe` 是 Native AOT 的 .NET 8 无头解析器（最后一个 .NET 组件，只作子进程、不含 UI），win-x64 自包含单文件，无需用户安装运行时。
- `project-view` 在 Rust/WebView2 进程内直接使用 mpxj-rs，正式发布不再携带 Java 运行时或独立 parser tool。
- .NET Viewer 的第三方包只在独立 Viewer 进程中加载，不由 Flutter 直接引用。
- 被多个 Viewer 共用的运行时作为**共享运行时包**发布，不复制进各 Viewer 包。判定标准是
  "是否被多于一个 Viewer 使用"：DjVuLibre（`ebook-view` 把 DjVu 转 PDF）、
  GhostXPS（`pdfjs-view` 把 XPS/OpenXPS 转 PDF）、LibreOffice（`pdfjs-view` 把
  Office/ODF/CAD 转 PDF，`excel-view` 把 `xls/xlt/xlsb/ods/ots` 转 xlsx，`web-view` 把
  Visio 转 SVG；收进共享包是为了
  将来宿主变化时不必再搬 472 MB）：

  ```text
  plugins/
  ├── runtime/                      # 源码树：runtime/build.bat 准备
  │   ├── djvulibre/                # ddjvu.exe + 4 个 DLL + COPYING
  │   ├── gxps/                     # gxpswin64.exe + gxpsdll64.dll + 许可文件
  │   ├── libreoffice/              # program\soffice.exe + share\ 等（472 MB）
  │   └── THIRD_PARTY_NOTICES.txt
  └── dist/
      ├── inf-dir.runtime/          # 发布产物：build.bat 安装
      │   ├── djvulibre/
      │   ├── gxps/
      │   ├── libreoffice/
      │   └── THIRD_PARTY_NOTICES.txt
      └── inf-dir.<viewer>/         # 各 Viewer 包不携带这些转换运行时
  ```

  该目录没有 `plugin.json`，Flutter 的插件发现会直接跳过，不会被当成 Viewer。三个
  Viewer 都按同一顺序解析 `<工具目录>\<可执行文件>`：先看自身包目录（保持包可自包含），
  再看相邻的 `inf-dir.runtime\` 与 `runtime\`，最后逐级向上检查各级祖先目录的
  `inf-dir.runtime\`、`runtime\` 和本 Viewer 源码目录（覆盖开发布局）。`ddjvu.exe`、
  `gxpswin64.exe` 与 `soffice.exe` 还可用 `INF_DIR_DJVULIBRE_PATH` / `INF_DIR_GXPS_PATH` /
  `INF_DIR_LIBREOFFICE_PATH`（文件或目录）覆盖。
- 共享运行时的压缩包统一缓存在 `plugins/runtime/_cache/`，都按 SHA-256 固定：
  DjVuLibre 3.5.29、GhostXPS 10.08.0、LibreOffice 26.2.5。其中 LibreOffice 的
  `instdir.7z` **不是上游发布**（TDF 的 Windows 包是 .msi，没有这种扁平 `instdir` 树），
  它是唯一来源，因此校验和是防止产物被替换的唯一保障。LibreOffice 的完整性标记用
  `program\soffice.exe` + `program\soffice.bin` + `program\version.ini`：早期版本检查的
  `help\idxcaption.xsl` 并不在这份 instdir 树里，导致每次构建都会白白重解压 472 MB。
- **XPS 转换运行时的选型记录**（2026-09）：GhostXPS 10.08.0，取自 Artifex 挂在
  Ghostscript 发行标签下的资源
  `.../ghostpdl-downloads/releases/download/gs10080/ghostxps-10.08.0-win64.zip`
  （SHA-256 校验写在 `plugins/runtime/build.bat` 里），只发布 `gxpswin64.exe`、
  `gxpsdll64.dll` 与许可文件：

  | | GhostXPS（现用） | `mutool`（先前的临时选型） |
  | --- | --- | --- |
  | 需安装的运行时 | `gxpsdll64.dll` 12.65 MB + `gxpswin64.exe` 0.08 MB = **12.78 MB** | `mutool.exe` 44.3 MB（单文件静态） |
  | 共享运行时包总量 | 约 14.5 MB（含 DjVuLibre） | 46.0 MB |
  | 许可 | GPLv3 / 商业 | AGPLv3 / 商业 |
  | 下载源 | 挂在 `gs<版本>` 发行标签下的资源，URL + SHA-256 可固定 | GitHub release，同样可固定 |
  | 能力范围 | 只做 XPS/OXPS | XPS/OXPS 之外还能转 EPUB/MOBI/FB2/CBZ 与抽文本 |

  切换原因是体积：GhostXPS 让共享运行时包从 46.0 MB 降到约 14.5 MB（-31.5 MB）。转换
  质量两者都够用——96 dpi 与"直开"对比：`.xps` mutool 差 410 px/691,200、gxps 差 0 px；
  `.oxps` mutool 差 167 px/861,696、gxps 差 819 px，均属抗锯齿级别；阿拉伯文样本两边都
  抽不出可用文本层。`mupdf-view` 下线后其余转换格式全部走 LibreOffice/GhostXPS，
  `mutool` 当年"接管 MuPDF 其余格式"的独特优势已不再相关；如未来需要可按同一套共享
  运行时解析顺序从 `mupdf-<版本>-windows.zip` 取回，无需改代码。

## 5. CBR 的特殊依赖关系

CBR 不再引入一个新的 RAR 解压二进制。发布目录应保持以下结构：

```text
plugins/
└── dist/
    ├── inf-dir.archive-view/
    │   ├── archive-view.exe
    │   └── archive.dll
    └── inf-dir.ebook-view/
        └── ebook-view.exe
```

`ebook-view` 会按以下顺序寻找提取器：

1. `INF_DIR_ARCHIVE_VIEW_PATH` 环境变量。
2. 自身目录或相邻的 `inf-dir.archive-view/archive-view.exe`。
3. `7za.exe` / `7z.exe` 作为兜底。

CBR 解包只提取常见漫画图片扩展名，拒绝绝对路径和 `..` 路径，并限制总图片数据为 512 MiB、页数为 10,000。解包结果会按文件名自然排序后写入临时 CBZ，关闭 Viewer 后清理临时目录。

如果已有用户关联配置把 `.cbr` 排在 `archive-view`，该配置会优先于新 manifest 顺序；可在 Viewer 关联设置中将 `ebook-view` 调到前面。`archive-view` 保留 CBR 是为了允许用户查看归档目录，而不是重复实现漫画渲染。

## 6. 当前明确缺口

- `CHM` 已接入 `chm-view` 首版；剩余工作是用更多真实 CHM 样本做兼容性回归，并评估旧式 ActiveX/脚本/特殊 frameset 的降级表现。
- `ebook-view (foliate-js)` 的扩展格式已接入，转换全部在 Rust 启动层完成：
  - **DjVu**：调用 `ddjvu.exe`（从共享运行时包解析）将 `.djvu` 临时转换为 PDF，再交给 foliate-js 自带的 `pdf.js`；
  - **.cbr（RAR 漫画）**：优先调用相邻的 `archive-view.exe --extract-comic`，否则回退
    `7za.exe`，把图片按文件名自然排序后重组为临时 `.cbz`，交给 `comic-book.js` 渲染，
    无需前端 unrar 库；
  - **.tcr**：在 Rust 启动层做 8-bit 字典解压并包装为 HTML 临时流。foliate-js 本身没有
    HTML 解析器，fork 内新增 `html-book.js` 并通过 `view.js` 的 `makeBook` 接入，因此
    HTML 文档同样由 foliate-js 自带的 `reader.html` 阅读界面排版。
  - **.fb2z**：在 Rust 启动层用 `zip` crate 从归档中抽出首个 `.fb2` 条目，作为普通 FB2
    交给 `fb2.js` 排版。
  - 该适配器按元素边界把文档切成 ≤64 KiB 的分节（超大块按行切开并保留外壳元素）、剥离
    脚本与事件属性（分节在同源 iframe 中渲染）、用 blob URL 惰性加载与释放，并按分节大小
    加权阅读进度。
- PDF 同时存在 PDFium 和 pdf.js 两个 Viewer，默认 Viewer 由用户关联配置决定。
- 旧 Office 依赖 LibreOffice headless 转 PDF（`pdfjs-view` 内置转换层），启动和转换体积、耗时明显高于 OOXML Web 渲染。
- `plugins/dist/` 是生成目录。修改源码或 manifest 后必须重新运行 `plugins/build.bat` 才能更新可运行的发布产物。

### 6.1 CHM 实现路线与工作量

CHMate 已作为 submodule 固定在 `ai_refs/CHMate`。它是无 npm 运行时依赖、无原生 DLL、无 WASM 的 ES module 实现，包含：

- ITSF/ITSP/PMGL 容器解析、section 0 直读和 section 1 LZX 解压。
- `#SYSTEM` / `#WINDOWS` 元数据、`.hhc` 目录、`.hhk` 索引和默认主题解析。
- HTML 主题、CSS、图片、字体和嵌套 frame 的资源重写。
- sandbox iframe、严格 CSP、脚本/事件属性/危险协议清理和网络阻断。

当前实现位于 `plugins/chm-view`，复用 `markdown-view` 的 Rust + winit/wry/WebView2 壳：

1. 将 CHMate 的 `src/chm/`、`src/render.js`、`src/app.js` 和必要 CSS/图标作为静态 Web 资源发布。
2. 增加固定 `/file` 本地协议路由，把启动参数中的 CHM 字节安全地提供给页面；不允许页面任意读取本地路径。
3. 隐藏 Demo 入口并改为启动后自动打开 Inf-Dir 传入的 CHM；文件选择和拖放仍保留，便于独立调试。
4. 保留目录、索引、文件列表、历史、缩放和查找；外部链接通过 Rust IPC 交给系统浏览器，并默认拒绝未知协议。
5. 增加 `plugin.json` 的 `.chm` 声明、构建复制规则和解析器 fixture 测试。

工作量评估已兑现为一个独立插件规模：解析器和安全渲染部分基本复用，新增代码集中在 WebView2 壳、固定 `/file` 资源路由、启动参数适配、发布复制和测试。最大的剩余风险不是 LZX，而是少数 CHM 使用的旧式 ActiveX、脚本、外部协议或特殊 frameset；按 CHMate 的安全策略，这些内容会被禁用或降级，而不是放开执行。

## 7. 相关入口

- Viewer manifest：`plugins/*/plugin.json`
- 总构建脚本：`plugins/build.bat`
- 格式覆盖追踪：`docs/viewer-format-matrix.md`
- 插件协议：`docs/plugin-system.md`
- Flutter manifest 覆盖测试：`test/viewer_format_coverage_test.dart`
