# excel-view

Inf-Dir QuickView 的 Excel 表格查看器，支持 **xlsx / xls / xlsb / ods**
（含 xlsm / xltx / xltm / xlt / ots）。Word 与 PowerPoint 由 pdfjs-view 负责。

## 架构

表格排版渲染的复杂度不适合自绘，因此本插件采用
**WebView2 壳 + Web 渲染器** 的方案：

```
excel-view.exe (winit + wry/WebView2)
    │  自定义协议 http://excel-view.local/
    ▼
excel-view-web/             （随 exe 发布的静态资源）
├── index.html              （加载页：实例化 XlsxViewer）
└── *.mjs / *.js / *.wasm   （@silurus/ooxml 渲染器，MIT 许可）
```

- `src/main.rs`：窗口创建、`http://excel-view.local/` 协议路由
  （静态资源 + `/file?path=` 读目标文档字节）。
  协议伪装成 http 而非自定义 scheme：Chromium 的 `fetch()`/Worker/wasm
  只认 http(s) 源；`excel-view.local` 无 DNS 记录，WebView2 在网络层之前拦截。
- `src/conversion.rs`：OOXML 之外的表格（`xls/xlt/xlsb/ods/ots`）先用共享的
  LibreOffice 运行时（`inf-dir.runtime`）`--convert-to xlsx` 转成 OOXML，
  临时目录由 `PreparedDocument` 持有并在进程退出时清理。
- `web/index.html`：加载页，按**实际提供的文件**扩展名实例化 `XlsxViewer`，
  标题与报错沿用原始文件名。

渲染器来自 [yukiyokotani/office-open-xml-viewer](https://github.com/yukiyokotani/office-open-xml-viewer)
（npm 包 `@silurus/ooxml`，MIT 许可，许可证见 `excel-view-web/LICENSE` 与
`THIRD_PARTY_NOTICES.md`）。解析在 WASM 中完成，渲染为 Canvas 2D，全程离线、无遥测。

## 构建

`plugins/build.bat` 会：

1. 从 npm registry 下载 `@silurus/ooxml` tarball，解压 dist 到 `plugins/excel-view-web/`；
2. `cargo build --release`（MSVC）；
3. 安装到 `plugins/dist/inf-dir.excel-view/`，`@silurus/ooxml` 的 dist 整份拷入不做
   裁剪（三种渲染器共用带 hash 的 chunk，按名删只省几 MB 且会随升级失效），
   仅校验 `xlsx.mjs` 与 `xlsx_parser_bg.wasm` 是否存在。

依赖系统已安装 WebView2 运行时（Win11 预装；Win10 随 Edge 更新）。
老格式转换依赖 LibreOffice，由 `plugins/build.bat` 一并装进 `inf-dir.runtime`；
也可用 `INF_DIR_LIBREOFFICE_PATH` 指向已有的安装。

## 用法

```
excel-view.exe <file.xlsx|xls|ods|...> [--window-placement <JSON>]
```
