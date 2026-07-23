# Inf-Dir 项目说明

## 项目目标

从零实现一个 Q-Dir 风格的四宫格 GUI 文件管理器（Windows 平台）。

当前分支（master3）探索 **Flutter** 技术路线。

## 技术栈

- **UI 框架**：Flutter（Windows desktop）
- **语言**：Dart
- **构建**：Flutter CLI（`flutter build windows`）

## 核心特性（对标 Q-Dir）

- 四宫格面板布局，每个面板独立浏览文件系统
- 文件列表：图标、排序、筛选、快速搜索
- 地址栏导航、面包屑路径
- 标签页支持（每个面板可多标签）
- 右键菜单、拖放、剪贴板操作

## 参考代码

`ai_refs/` 目录下存放参考源码，**仅作为功能与架构参考**，不作为基础框架或代码依赖。

## 目录结构

```
Inf-Dir/
├── ai_refs/             # 参考源码（已 gitignore）
├── lib/                 # Dart 源代码
├── windows/             # Flutter Windows 平台配置
├── AGENTS.md            # 本文件
└── qdir截图.png         # Q-Dir UI 参考截图
```

## 开发约定

- 文件系统操作及 Shell 集成通过 `win32` 包调用 Win32 / COM / Shell API
- 状态管理方案待定（Provider / Riverpod / 其他）
- 保持轻量，避免过度抽象
