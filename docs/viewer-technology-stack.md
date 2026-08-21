# Inf-Dir Viewer 格式与技术栈记录

本文以当前源码中的 `plugins/*/plugin.json`、构建脚本和各 Viewer 工程文件为准，记录 Quick View 的格式覆盖、解析路径、运行时依赖和发布产物。

## 1. 总体架构

- Flutter 主进程只负责发现 manifest、解析关联、启动和管理 Viewer 进程，不加载第三方 DLL。
- 每个 Viewer 是独立的 Rust 或 .NET Windows 进程，入口由插件目录中的 `plugin.json` 声明。
- `plugins/build.bat` 负责准备外部运行时、构建 Viewer，并把产物安装到 `plugins/dist/<plugin-id>/`。
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
| EPUB | `mupdf-view` | 已接入 | MuPDF.NET 直接打开 | MuPDF.NET / MuPDF 原生资产 |
| MOBI | `mupdf-view` | 已接入 | MuPDF.NET 直接打开 | MuPDF.NET / MuPDF 原生资产 |
| FB2 | `mupdf-view` | 已接入 | MuPDF.NET 直接打开 | MuPDF.NET |
| FBZ / FB2Z | `mupdf-view` | 已接入（转换） | ZIP 中提取 FB2，再交给 MuPDF.NET | .NET `System.IO.Compression`；MuPDF.NET |
| TCR | `mupdf-view` | 已接入（转换） | 解压 TCR 字典格式为临时 HTML，再交给 MuPDF.NET | .NET 内置字节解析；MuPDF.NET |
| CBZ | `mupdf-view`、`archive-view` | 已接入，两个候选 | MuPDF 直接读取 ZIP 漫画；archive-view 可列出归档内容 | MuPDF.NET；libarchive |
| CBR | `mupdf-view`、`archive-view` | 已接入，两个候选 | `mupdf-view` 启动旁边的 `archive-view.exe --extract-comic`，用 libarchive 解包图片，按自然序重新打包临时 CBZ 后交给 MuPDF | `archive-view.exe` + `archive.dll`；MuPDF.NET；无需新增 RAR 二进制 |
| DjVu / DJV | `mupdf-view` | 已接入（转换） | DjVuLibre `ddjvu.exe` 转 PDF，再交给 MuPDF.NET | 内置 DjVuLibre 运行时 |
| XPS / OXPS | `mupdf-view` | 已接入 | MuPDF.NET 直接打开 | MuPDF.NET |
| CHM | 计划 `chm-view`（CHMate） | 未接入（方案已确定） | 复用 CHMate 的纯 JS ITSF/ITSP/PMGL + LZX 解析和安全 HTML 渲染，接入现有 WebView2 Viewer 壳 | CHMate（MIT）；WebView2 |
| 旧 Office：DOC/XLS/PPT 等 | `mupdf-view` | 已接入（转换） | 调用 `soffice --headless` 转 PDF，再交给 MuPDF.NET | 内置或系统 LibreOffice |
| OOXML：DOCX/XLSX/PPTX | `office-view` | 已接入 | WebView2 加载本地 OOXML Web 渲染器 | WebView2；`@silurus/ooxml` 静态资源 |
| 图片与 RAW | `img-view` | 已接入 | Rust 原生解码；SVG 用 resvg；RAW 用 rawloader；失败时调用侧车程序 | `image`、`resvg`、`rawloader`；可选 ImageMagick、Compface、Windows WIC |
| 音频/视频 | `video-view` | 已接入 | libmpv2 渲染和播放 | `libmpv2`；发布时附带 `libmpv-2.dll` |
| 压缩包 | `archive-view` | 已接入 | libarchive 枚举并显示归档内容 | `archive.dll`（libarchive） |
| 邮件：EML/EMLX/MSG/OFT/TNEF | `email-view` | 已接入 | .NET 解析邮件，WebView2 渲染正文 | MimeKit；MSGReader；WebView2；DOMPurify |
| 字体：TTF/OTF/WOFF/WOFF2/TTC/DFONT | `font-view` | 已接入 | .NET 处理 DFONT，WebView2 显示字体预览 | .NET 8；WebView2；Windows 字体能力 |
| Project：MPP/MPT/MPX | `project-view` | 已接入 | MPXJ.Net 读取任务、时间和层级 | .NET 10；MPXJ.Net |

## 3. Viewer 工程技术栈

| 插件 | 语言/窗口层 | 核心库 | 随包或系统依赖 | 主要格式 |
| --- | --- | --- | --- | --- |
| `inf-dir.code-view` | Rust + winit/wry/WebView2 | CodeMirror 6、Lezer | WebView2；CodeMirror Web bundle | 代码、文本、JSON、HTML、CSS、配置和日志 |
| `inf-dir.markdown-view` | Rust + winit/wry/WebView2 | markdown-it、highlight.js、KaTeX、Mermaid、GitHub Markdown CSS | WebView2；Markdown 静态资源 | Markdown |
| `inf-dir.image-view` | Rust + egui/eframe | image、resvg、rawloader | 可选 ImageMagick、Compface、WIC decoder | 常用位图、SVG、RAW、专业图像格式 |
| `inf-dir.pdf-view` | Rust + egui/eframe | pdfium-render | `pdfium.dll`，默认构建 PDFium 7881 x64 | PDF |
| `inf-dir.pdfjs-view` | Rust + winit/wry/WebView2 | Mozilla pdf.js 6.2.108 | WebView2；pdf.js `web/` 和 `build/` 资源 | PDF |
| `inf-dir.office-view` | Rust + winit/wry/WebView2 | `@silurus/ooxml` WASM/Web 渲染器 | WebView2；`office-view-web/` | DOCX/XLSX/PPTX 及 OOXML 模板 |
| `inf-dir.mupdf-view` | .NET Windows Forms | MuPDF.NET 3.28.1.6 | MuPDF 原生资产；DjVuLibre 3.5.29；LibreDWG 0.14；LibreOffice 26.2.5；CBR 时依赖相邻 archive-view | PDF 衍生文档、电子书、漫画、DjVu、XPS、旧 Office、Visio、CAD |
| `inf-dir.archive-view` | Rust + egui/eframe | libarchive、egui_ltreeview | `archive.dll` | ZIP/7z/RAR/TAR/ISO 等归档内容 |
| `inf-dir.video-view` | Rust + egui/eframe | libmpv2 | `libmpv-2.dll`；mpv/FFmpeg 能力由 DLL 提供 | 音频、视频、动图 |
| `inf-dir.email-view` | .NET 8 Windows Forms + WebView2 | MimeKit 4.17.0、MSGReader 6.0.7 | WebView2；本地 HTML/CSS/JS；DOMPurify | EML/EMLX/MSG/OFT/TNEF |
| `inf-dir.font-view` | .NET 8 Windows Forms + WebView2 | 自研 DFONT 提取器 | WebView2；self-contained .NET 运行时 | 字体预览 |
| `inf-dir.project-view` | .NET 10 Windows Forms | MPXJ.Net 16.7.0 | self-contained .NET 运行时 | Microsoft Project |

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
- `office-view`
- `pdfjs-view`
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
| DjVuLibre | `mupdf-view` | `mupdf-view/djvulibre/`，核心是 `ddjvu.exe` |
| LibreDWG | `mupdf-view` | `mupdf-view/libredwg/`，包含 `dwg2SVG.exe` / `dxf2dwg.exe` |
| LibreOffice | `mupdf-view` | `mupdf-view/libreoffice/`，调用 `program/soffice.exe` |
| ImageMagick | `img-view` | `img-view/magick/`，作为解码失败时的子进程 |
| Compface | `img-view` | `img-view/compface/`，用于 X-Face |
| Windows WIC decoder | `img-view` | `img-view/wic-decoder/wic-decoder.exe` |

### 4.4 .NET 运行时

- `email-view` 和 `font-view` 使用 .NET 8、Windows Forms、win-x64 self-contained 发布。
- `mupdf-view` 和 `project-view` 使用 .NET 10；当前开发环境需要对应 SDK，正式发布按构建脚本发布 self-contained 产物。
- .NET Viewer 的第三方包只在独立 Viewer 进程中加载，不由 Flutter 直接引用。

## 5. CBR 的特殊依赖关系

CBR 不再引入一个新的 RAR 解压二进制。发布目录应保持以下结构：

```text
plugins/
└── dist/
    ├── inf-dir.archive-view/
    │   ├── archive-view.exe
    │   └── archive.dll
    └── inf-dir.mupdf-view/
        └── mupdf-view.exe
```

`mupdf-view` 会按以下顺序寻找提取器：

1. `INF_DIR_ARCHIVE_VIEW_PATH` 环境变量。
2. 自身目录或相邻的 `inf-dir.archive-view/archive-view.exe`。
3. `7za.exe` / `7z.exe` 作为兜底。

CBR 解包只提取常见漫画图片扩展名，拒绝绝对路径和 `..` 路径，并限制总图片数据为 512 MiB、页数为 10,000。解包结果会按文件名自然排序后写入临时 CBZ，关闭 Viewer 后清理临时目录。

如果已有用户关联配置把 `.cbr` 排在 `archive-view`，该配置会优先于新 manifest 顺序；可在 Viewer 关联设置中将 MuPDF 调到前面。`archive-view` 保留 CBR 是为了允许用户查看归档目录，而不是重复实现漫画渲染。

## 6. 当前明确缺口

- `CHM` 当前尚未接入运行时；解析方案已确定为 `ai_refs/CHMate`。需要把它封装成现有 manifest 驱动的 `chm-view` WebView2 进程，并保留其安全 iframe、CSP、资源 blob 化和禁止脚本策略。
- PDF 同时存在 PDFium 和 pdf.js 两个 Viewer，默认 Viewer 由用户关联配置决定。
- 旧 Office 依赖 LibreOffice headless 转 PDF，启动和转换体积、耗时明显高于 OOXML Web 渲染。
- `plugins/dist/` 是生成目录。修改源码或 manifest 后必须重新运行 `plugins/build.bat` 才能更新可运行的发布产物。

### 6.1 CHM 实现路线与工作量

CHMate 已作为 submodule 固定在 `ai_refs/CHMate`。它是无 npm 运行时依赖、无原生 DLL、无 WASM 的 ES module 实现，包含：

- ITSF/ITSP/PMGL 容器解析、section 0 直读和 section 1 LZX 解压。
- `#SYSTEM` / `#WINDOWS` 元数据、`.hhc` 目录、`.hhk` 索引和默认主题解析。
- HTML 主题、CSS、图片、字体和嵌套 frame 的资源重写。
- sandbox iframe、严格 CSP、脚本/事件属性/危险协议清理和网络阻断。

预计新增一个 `plugins/chm-view`，复用 `markdown-view` 或 `office-view` 的 Rust + winit/wry/WebView2 壳：

1. 将 CHMate 的 `src/chm/`、`src/render.js`、`src/app.js` 和必要 CSS/图标作为静态 Web 资源发布。
2. 增加 `/file?path=...` 本地协议路由，把启动参数中的 CHM 字节安全地提供给页面；不允许页面任意读取本地路径。
3. 去掉文件选择、Demo 和浏览器专属逻辑，改为启动后自动打开 Inf-Dir 传入的 CHM。
4. 保留目录、索引、文件列表、历史、缩放和查找；外部链接通过 Rust IPC 交给系统浏览器，并默认拒绝未知协议。
5. 增加 `plugin.json` 的 `.chm` 声明、构建复制规则和解析器 fixture 测试。

工作量估计：解析器和安全渲染部分基本可复用，约 60%--70% 不需要重写；新增代码主要是 WebView2 壳、资源路由、启动参数适配、发布复制和测试，约 1 个独立插件规模，预计 1--2 个开发日可完成首版，另需用多个真实 CHM 样本做兼容性回归。最大的风险不是 LZX，而是少数 CHM 使用的旧式 ActiveX、脚本、外部协议或特殊 frameset；按 CHMate 的安全策略，这些内容会被禁用或降级，而不是放开执行。

## 7. 相关入口

- Viewer manifest：`plugins/*/plugin.json`
- 总构建脚本：`plugins/build.bat`
- 格式覆盖路线图：`docs/viewer-format-roadmap.md`
- 插件协议：`docs/plugin-system.md`
- Flutter manifest 覆盖测试：`test/viewer_format_coverage_test.dart`
