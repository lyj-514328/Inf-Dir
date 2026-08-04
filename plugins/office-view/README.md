# office-view

Inf-Dir QuickView 的 Office 文档查看器，支持 **docx / xlsx / pptx**（含 docm / xlsm / pptm）。
不支持旧的二进制格式（.doc / .xls / .ppt）。

## 架构

与其他插件（egui 原生绘制）不同，Office 排版渲染的复杂度不适合自绘，
因此本插件采用 **WebView2 壳 + Web 渲染器** 的方案：

```
office-view.exe (winit + wry/WebView2)
    │  自定义协议 http://office-view.local/
    ▼
office-view-web/            （随 exe 发布的静态资源）
├── index.html              （加载页：按扩展名分发到对应 Viewer）
└── *.mjs / *.js / *.wasm   （@silurus/ooxml 渲染器，MIT 许可）
```

- `src/main.rs`：窗口创建、`http://office-view.local/` 协议路由
  （静态资源 + `/file?path=` 读目标文档字节）。
  协议伪装成 http 而非自定义 scheme：Chromium 的 `fetch()`/Worker/wasm
  只认 http(s) 源；`office-view.local` 无 DNS 记录，WebView2 在网络层之前拦截。
- `web/index.html`：加载页，根据扩展名实例化 `DocxViewer` / `XlsxViewer` / `PptxViewer`。

渲染器来自 [yukiyokotani/office-open-xml-viewer](https://github.com/yukiyokotani/office-open-xml-viewer)
（npm 包 `@silurus/ooxml`，MIT 许可，许可证见 `office-view-web/LICENSE` 与
`THIRD_PARTY_NOTICES.md`）。解析在 WASM 中完成，渲染为 Canvas 2D，全程离线、无遥测。

## 构建

`plugins/build.bat` 会：

1. 从 npm registry 下载 `@silurus/ooxml` tarball，解压 dist 到 `plugins/office-view-web/`；
2. `cargo build --release`（MSVC）；
3. 安装 `office-view.exe` 到 `plugins/`。

依赖系统已安装 WebView2 运行时（Win11 预装；Win10 随 Edge 更新）。

## 用法

```
office-view.exe [--width 960] [--height 720] <file.docx|xlsx|pptx>
```
