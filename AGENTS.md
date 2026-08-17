# Inf-Dir 项目说明

## 项目目标

从零实现一个多面板 GUI 文件管理器（Windows 平台）：布局采用 **Hyprland Dwindle 风格递归分割树**（默认初始为 2×2 四宫格，可任意拆分），并通过 manifest 驱动的 **viewer 插件体系**为各类文件提供快速预览。

## 技术栈

- **UI 框架**：Flutter（Windows desktop）
- **语言**：Dart
- **构建**：Flutter CLI（`flutter build windows`）
- **窗口**：无边框自定义顶栏（`window_manager` 运行时隐藏原生标题栏，自绘窗口控制按钮）
- **Viewer 插件**：Rust（egui）与 WebView2（wry）独立进程查看器，`plugins/build.bat` 构建

## 核心特性

- Hyprland Dwindle 风格布局树：多 workspace、水平/垂直分割、关闭、拖拽缩放、Alt 交换面板（`LayoutTree` + `LayoutView` 递归渲染）
- 每个面板独立浏览文件系统
- 文件列表：图标、排序、筛选、快速搜索
- 地址栏导航、面包屑路径
- 标签页支持（每个面板可多标签）
- 右键菜单、拖放、剪贴板操作
- 快速查看（Quick View）：manifest 驱动的 viewer 插件关联（text/pdf/img/video/archive/office）
- 侧边栏驱动器树与云盘状态列（CfAPI：SyncRootManager 检测 + StorageProviderState 状态）
- 显示隐藏/系统文件开关（会话级）

## 参考代码

`ai_refs/` 目录下存放参考源码（以 git submodule 管理），**仅作为功能与架构参考**，不作为基础框架或代码依赖。布局树主要参考 `ai_refs/Hyprland/src/layout/algorithm/tiled/dwindle/`。

## 目录结构

```
Inf-Dir/
├── ai_refs/             # 参考源码（git submodule）
├── docs/                # 设计文档（plugin-system.md、sidebar-sync-refactor.md）
├── lib/
│   ├── features/        # 功能模块（quick_view 插件集成）
│   ├── models/          # 数据模型（file_entry、layout_node 等）
│   ├── services/        # 文件/图标/Shell/侧边栏/云盘服务
│   ├── state/           # 状态管理（app_state、pane_controller、theme_controller 等）
│   ├── utils/           # 工具（path_utils、perf_log）
│   └── widgets/         # UI 组件与主题 token
├── plugins/             # viewer 插件源码、构建脚本与产物（产物已 gitignore）
├── test/                # 单元/widget 测试
├── windows/             # Flutter Windows 平台配置
└── AGENTS.md            # 本文件
```

## 开发约定

- 文件系统操作及 Shell 集成通过原生 FFI（`dart:ffi` + `package:ffi`）直接调用 Win32 / COM / Shell API
- 状态管理使用 Provider
- 保持轻量，避免过度抽象
- 样式统一走 `lib/widgets/app_theme.dart` 的设计 token（`context.colors` / `AppMetrics`），widget 中禁止新增 `Color(0x...)` / `Colors.xxx` 字面量（`Colors.transparent` 除外）；明暗双主题由 `lib/state/theme_controller.dart` 切换并持久化（`lib/services/theme_store.dart`）
- 界面风格为现代极简：一体化无边框顶栏（`app_shell.dart` 的 `_TopBar` + `window_controls.dart`）、胶囊式标签/选中态、面包屑地址栏（`address_bar.dart`）、ghost 按钮命令栏
- Viewer 插件运行于独立进程，不把第三方 DLL 加载进 Flutter 主进程；Manifest、用户关联与解析规则见 `docs/plugin-system.md`

## 常用命令

- `flutter test` — 运行测试
- `flutter analyze` — 静态检查
- `plugins/build.bat` — 一键构建全部 viewer 插件（依赖 rustup / cargo / 7z，网络依赖见脚本内 URL）
