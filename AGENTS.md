# Inf-Dir 项目说明

## 项目目标

从零实现一个 Q-Dir 风格的四宫格 GUI 文件管理器（Windows 平台）。

## 技术栈

- **UI 框架**：WTL（Windows Template Library）— 负责窗口布局、控件管理（ListView / TreeView / SplitterWindow 等）
- **系统资源管理**：WIL（Windows Implementation Library）— 负责 Shell 集成、COM 智能指针、句柄 RAII 封装、错误处理
- **语言**：C++（Win32 原生）
- **构建**：MSVC / CMake（待定）

## 核心特性（对标 Q-Dir）

- 四宫格面板布局，每个面板独立浏览文件系统
- Windows Shell 集成：图标、右键菜单、拖放、剪贴板操作
- 地址栏导航、面包屑路径
- 文件排序、筛选、快速搜索
- 标签页支持（每个面板可多标签）

## 参考代码

`ai_refs/doublecmd/` 目录下存放 Double Commander 源码，**仅作为功能与架构参考**，不作为基础框架或代码依赖。

## 目录结构

```
Inf-Dir/
├── ai_refs/doublecmd/   # Double Commander 参考源码（已 gitignore）
├── src/                 # 项目源代码（待创建）
├── AGENTS.md            # 本文件
└── qdir截图.png         # Q-Dir UI 参考截图
```

## 开发约定

- WTL 管 UI 控件，WIL 管系统资源，职责不交叉
- 优先使用 Windows Shell API（IShellFolder / IShellItem）获取文件信息
- 不引入额外运行时依赖，保持原生轻量
