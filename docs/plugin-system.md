# Inf-Dir 插件规范

本文定义 Inf-Dir Quick View 与搜索提供器插件包、Manifest、构建方式、用户关联配置和 F3 解析规则。

## 1. 设计原则

- 插件使用独立进程运行，不把第三方 DLL 加载到 Flutter 主进程。
- WebView2 viewer 复用 `plugins/viewer-web-shell` 的窗口定位、生命周期和本地协议基础；格式 viewer 只负责页面资源和内容解析。
- `quickView` 与 `search` 是独立能力；搜索插件不参与 Viewer 关联解析。
- Manifest 只声明插件能力，不声明插件优先级。
- 用户关联配置保存递归规则树、Viewer 顺序和启用状态；Manifest 新增声明以追加方式合并。
- `path`、`extension`、`fileName`、`mimeType` 是四种可混合、可嵌套的规则类型。
- Manifest 负责生成默认规则和默认 Viewer；用户规则可关联任意已安装的 Quick View Viewer。
- 路径规则只由用户创建，插件不能在 Manifest 中声明路径规则。
- 主程序通过参数数组传递文件路径，不拼接或重新解析命令行字符串。

## 2. 发布目录

```text
Inf-Dir/
├── inf_dir.exe
├── data/
└── plugins/
    ├── inf-dir.image-view/
    │   ├── plugin.json
    │   └── img-view.exe
    ├── inf-dir.pdf-view/
    │   ├── plugin.json
    │   ├── pdf-view.exe
    │   └── pdfium.dll
    ├── inf-dir.fd-search/
    │   ├── plugin.json
    │   ├── fd.exe
    │   └── LICENSE-MIT
    └── inf-dir.ripgrep-search/
        ├── plugin.json
        ├── rg.exe
        └── LICENSE-MIT
```

每个插件拥有独立目录。`entrypoint` 相对于 `plugin.json` 所在目录解析，且不得逃逸插件目录。

开发构建产物位于 `plugins/dist/<plugin-id>/`。Windows 发布构建会把 `plugins/dist/` 安装到主程序旁的 `plugins/`。

## 3. Manifest

文件名固定为 `plugin.json`，编码为 UTF-8。

```json
{
  "manifestVersion": 1,
  "id": "inf-dir.code-view",
  "name": "代码查看器",
  "version": "1.0.0",
  "entrypoint": "code-view.exe",
  "capabilities": {
    "quickView": {
      "extensions": [".txt", ".md", ".json"],
      "fileNames": [".gitignore", ".env", "dockerfile"],
      "mimeTypes": ["text/*", "application/json"]
    }
  }
}
```

### 3.1 必填字段

| 字段 | 说明 |
| --- | --- |
| `manifestVersion` | 当前固定为 `1` |
| `id` | 全局稳定 ID，仅允许小写字母、数字、点和连字符 |
| `name` | 配置界面显示名称 |
| `version` | 插件版本 |
| `entrypoint` | 插件目录内的 EXE 相对路径；仅对携带可执行程序的插件（`quickView`）必填 |
| `capabilities` | 至少声明一个受支持能力：`quickView`、`search`、`archive` 或 `openDirectory` |

Viewer 插件的 `quickView` 至少要包含一个非空匹配组。绝大多数 Viewer 插件只需要 `extensions`。

### 3.2 规范化

- `extensions`：小写、以点开头，例如 `.pdf`；允许 `.tar.gz` 等复合后缀。
- `fileNames`：Windows 下不区分大小写，必须是文件名而不是路径。
- `mimeTypes`：小写、不带参数，允许 `type/*` 通配符。
- 同一数组内的重复项在加载时去重。

插件启动协议第一版为：

```text
<entrypoint> <absolute-file-path>
```

插件工作目录设为插件包目录。所有 Quick View viewer 都必须接受可选的窗口位置参数；替换
attached viewer 时按下面的形式启动：

```text
<entrypoint> <absolute-file-path> --window-placement <json>
```

`<json>` 由参数数组直接传递，是一个完整的命令行参数，不经过 shell 拼接或再次解析：

```json
{"version":2,"x":1024,"y":0,"clientWidth":1008,"clientHeight":1113,"maximized":false}
```

`x`、`y` 是 Win32 物理像素下的窗口外框位置，`clientWidth`、`clientHeight` 是客户区物理
像素尺寸，可直接传给 winit/egui 的 inner size。最大化时这些字段表示恢复后的窗口位置与客户区
尺寸。版本 2 不兼容旧版把外框宽高写入 `width`、`height` 的协议。
首次打开或已 detach 后重新打开时没有可继承窗口，因此不传该参数。viewer 不再支持旧的
`--width` / `--height` 参数，也不通过 Manifest 协商窗口位置协议。

Inf-Dir 同一时间只管理一个 attached Quick View 进程。再次快速查看时，主程序读取旧
viewer 的顶层窗口位置、大小和最大化状态，把完整位置作为启动参数交给新 viewer。主程序发现
新 HWND 且窗口尺寸稳定后关闭旧进程，不再对新窗口执行二次 Win32 位置校正。viewer 不需要
实现文件热切换或 IPC。

顶栏的“分离快速查看窗口”命令会解除当前 viewer 与 Inf-Dir 的管理关系。分离后的进程不会因
Inf-Dir 退出或后续快速查看而关闭；下一次快速查看会创建新的 attached viewer。Inf-Dir 正常
退出时只关闭仍处于 attached 状态的 viewer。

### 3.3 WebView2 Viewer 窗口规范

使用 winit + wry/WebView2 的 Quick View viewer 必须遵循以下窗口初始化规范：

- 使用共享的 `viewer-window-placement` crate 解析 `--window-placement`，不得自行解释或扩展
  placement JSON。
- `x`、`y` 直接传给 `PhysicalPosition`；`clientWidth`、`clientHeight` 直接传给
  `PhysicalSize`。不得将外框宽高传给 `with_inner_size`，也不得在物理像素和逻辑像素之间
  进行不必要的往返换算。
- 顶层窗口必须使用 `with_visible(false)` 隐藏创建。WebView2 controller 创建成功并已覆盖
  客户区后，才能显示窗口。WebView2 初始化失败时应保持窗口隐藏并退出进程。
- 单个 WebView 占满整个客户区时必须使用 `WebViewBuilder::build(&window)`。wry 的 Windows
  后端会设置初始全尺寸 bounds，并自动跟随父窗口 resize。
- 最大化应在 WebView 创建成功后、窗口显示前调用 `window.set_maximized(true)`，不得依赖
  初始窗口属性提前显示一个尚未完成的窗口。
- 完成初始化后依次调用 `window.set_visible(true)` 和 `window.focus_window()`。`Window` 和
  `WebView` 必须保存在应用状态中，直到事件循环退出。
- 不得在正常启动路径中额外调用 `SetWindowPos`，也不得为整窗 WebView 监听
  `WindowEvent::Resized` 后手工调用 `WebView::set_bounds`。

整窗 WebView2 viewer 的推荐初始化方式如下。代码应放在 winit
`ApplicationHandler::resumed` 中，并在重复进入 `resumed` 时避免再次创建窗口：

```rust
use dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use viewer_window_placement::WindowPlacement;
use winit::event_loop::ActiveEventLoop;
use winit::window::{Window, WindowAttributes};
use wry::{WebView, WebViewBuilder};

fn create_webview_window(
    event_loop: &ActiveEventLoop,
    placement: Option<WindowPlacement>,
    start_url: &str,
) -> (Window, WebView) {
    let start_maximized = placement.is_some_and(|value| value.maximized);
    let mut attributes: WindowAttributes = Window::default_attributes()
        .with_title("Example View")
        .with_min_inner_size(LogicalSize::new(480u32, 360u32))
        .with_visible(false);

    attributes = match placement {
        Some(value) => attributes
            .with_position(PhysicalPosition::new(value.x, value.y))
            .with_inner_size(PhysicalSize::new(
                value.client_width,
                value.client_height,
            )),
        None => attributes.with_inner_size(LogicalSize::new(960u32, 720u32)),
    };

    let window = event_loop
        .create_window(attributes)
        .expect("failed to create viewer window");
    let webview = WebViewBuilder::new()
        .with_url(start_url)
        .build(&window)
        .expect("failed to initialize WebView2");

    if start_maximized {
        window.set_maximized(true);
    }
    window.set_visible(true);
    window.focus_window();

    (window, webview)
}
```

只有一个顶层窗口内存在多个 WebView，或 WebView 明确只占客户区一部分时，才允许使用
`build_as_child`。此时必须在创建时通过 `with_bounds` 提供基于当前客户区的完整初始 bounds，
并在每次父窗口 resize 时同步更新；不得依赖 wry 默认的 `200x200` child bounds。页面自身还应
保证 `html`、`body` 高宽为 `100%`、边距为 `0`，避免 Web 内容内部产生未覆盖区域。

### 3.4 搜索提供器

搜索插件通过 `capabilities.search` 声明后端类型和主程序支持的输出协议：

```json
{
  "manifestVersion": 1,
  "id": "inf-dir.ripgrep-search",
  "name": "ripgrep 文本搜索",
  "version": "15.2.0",
  "entrypoint": "rg.exe",
  "capabilities": {
    "search": {
      "type": "content",
      "protocol": "ripgrep-json-v1"
    }
  }
}
```

当前支持：

| `type` | 内置插件 | 协议 | 用途 |
| --- | --- | --- | --- |
| `fileName` | `inf-dir.fd-search` | `fd-nul-v1` | 文件名、Glob、正则搜索，NUL 分隔输出 |
| `content` | `inf-dir.ripgrep-search` | `ripgrep-json-v1` | 文件内容搜索，JSON Lines 输出 |

主程序优先读取 `INF_DIR_FD_PATH` / `INF_DIR_RG_PATH` 显式覆盖；否则依次从
`INF_DIR_PLUGIN_DIR`、程序旁 `plugins/`、开发目录 `plugins/dist/` 和用户插件目录发现
对应 manifest。插件不可用时才回退到旧式程序目录、`tools/` 和 `PATH` 查找。

### 3.5 搜索插件构建

`plugins/search/build.bat` 从官方 GitHub Release 构建两个自包含插件包：

- `fd 10.4.2`：`sharkdp/fd` 的 Windows x64 MSVC ZIP；
- `ripgrep 15.2.0`：`BurntSushi/ripgrep` 的 Windows x64 MSVC ZIP。

版本、下载 URL 和 SHA-256 均固定在脚本内。脚本会验证下载、解压 EXE，并把上游许可证与
`THIRD_PARTY_NOTICES.txt` 一起安装到 `plugins/dist/<plugin-id>/`。主
`plugins/build.bat` 会自动调用该脚本；也可以单独运行 `plugins/search/build.bat` 只构建搜索插件。

### 3.6 压缩操作插件

压缩操作插件通过 `capabilities.archive` 声明，不参与 Quick View 的文件关联。当前内置
`inf-dir.7z-archive` 使用官方 7-Zip Extra 包中的 `7za.exe`，协议为 `7zip-cli-v1`：

```json
{
  "manifestVersion": 1,
  "id": "inf-dir.7z-archive",
  "name": "7-Zip archive operations",
  "version": "26.02",
  "entrypoint": "7za.exe",
  "capabilities": {
    "archive": {
      "type": "7zip",
      "protocol": "7zip-cli-v1",
      "operations": ["create"],
      "formats": ["7z", "zip"]
    }
  }
}
```

主程序使用参数数组启动插件，不经过 shell 拼接命令行。创建操作遵循 7-Zip CLI 的
`a -t<format> -y <archive-path> <input-path>...` 形式；`INF_DIR_7Z_PATH` 可用于开发或
测试时显式覆盖入口。插件包由 `plugins/archive/build.bat` 构建并安装到
`plugins/dist/inf-dir.7z-archive/`，主 `plugins/build.bat` 会自动调用该脚本。
未找到插件时不回退到 PowerShell 或其他压缩实现，主程序会提示用户构建插件或配置入口。

### 3.7 目录打开器（openDirectory）

目录打开器面向**目录**而非文件：右键目录时，主程序为每个可用的目录打开器显示一条
「用 \<名称\> 打开」菜单项，点击后以分离进程启动解析到的可执行文件并传入目录绝对路径。
目录打开器不参与 Quick View 关联解析，也不携带 `entrypoint`；可执行程序来自系统安装，
插件包只含 `plugin.json`。

```json
{
  "manifestVersion": 1,
  "id": "inf-dir.vscode-open",
  "name": "Visual Studio Code",
  "version": "1.0.0",
  "capabilities": {
    "openDirectory": {
      "executables": ["code.cmd", "Code.exe"],
      "appPaths": ["Code.exe"],
      "installPaths": [
        "%LOCALAPPDATA%\\Programs\\Microsoft VS Code\\Code.exe",
        "%ProgramFiles%\\Microsoft VS Code\\Code.exe"
      ]
    }
  }
}
```

| 字段 | 说明 |
| --- | --- |
| `executables` | 裸可执行文件名，按序在 `PATH` 目录中扫描 |
| `appPaths` | 按序查询注册表 `SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\<名称>`（先 HKLM 后 HKCU） |
| `installPaths` | 常见安装位置模板，支持 `%VAR%` 环境变量展开；含未知变量的模板跳过 |
| `arguments` | 启动参数模板（可选）。每个条目按原样传入，其中 `{dir}` 替换为被打开目录的绝对路径；省略时默认只传目录绝对路径 |

解析顺序（首个存在的文件生效，结果在插件扫描时缓存）：

1. 环境变量覆盖：插件 ID 大写、非字母数字替换为 `_` 后加 `_PATH`
   （`inf-dir.vscode-open` → `INF_DIR_VSCODE_OPEN_PATH`）；
2. `appPaths` 注册表查询；
3. `PATH` 目录扫描 `executables`；
4. `installPaths` 模板展开。

解析失败的插件记录诊断问题且不进入右键菜单。启动协议为 `<executable> <参数模板展开结果>`，
工作目录为被打开的目录，进程与主程序生命周期无关。菜单仅对单个目录选择显示；Quick View（F3）
对目录的行为不变。

例如 Windows 终端需要 `-d` 开关指定起始目录：

```json
{
  "manifestVersion": 1,
  "id": "inf-dir.windows-terminal",
  "name": "Windows 终端",
  "version": "1.0.0",
  "capabilities": {
    "openDirectory": {
      "executables": ["wt.exe"],
      "appPaths": ["wt.exe"],
      "installPaths": ["%LOCALAPPDATA%\\Microsoft\\WindowsApps\\wt.exe"],
      "arguments": ["-d", "{dir}"]
    }
  }
}
```

## 4. 用户关联配置

Windows 下用户配置文件存储在：

```text
%LOCALAPPDATA%\Inf-Dir\viewer_associations.json
```

schema 当前为 **3**。默认规则不再由 Manifest 运行时生成，而是来自
`plugins/quick-view.default.json`（随插件目录分发、手工维护的静态预置分组）。
用户配置只保存**用户自己的规则组与组间顺序**；预置 default 分组只记录一条引用
（`{"id": "default", "preset": true}`），不存储其规则内容，因为内容以
plugins 静态配置为准。因此用户拖动分组把自定义组放到 default 之前时，
`groups` 数组顺序即可表达优先级并持久化：

```json
{
  "schemaVersion": 3,
  "groups": [
    {"id": "default", "preset": true},
    {
      "id": "group-1737362571000000",
      "name": "我的规则",
      "preset": false,
      "enabled": true,
      "rules": []
    }
  ]
}
```

加载时按 `groups` 顺序把 `preset: true` 条目替换为 plugins 静态配置中的
default 分组（含 `rules` 递归树），其余条目按完整组解析。应用升级 3 版本以下
的旧配置时执行迁移（见 §4.3）。

## 4.1 规则组

默认只有一个预置组 `default`（名称"默认"），所有默认规则混合在它的递归树中。
预置组**完全只读**：不能启用/禁用、不能改名、不能删除、不能拖拽排序、不能往
里面添加规则或 Viewer；用户组可以任意操作。用户自定义规则放在自己的组里，
通过把组拖到 default 之前获得更高优先级。

`groups` 数组顺序决定组优先级；`default` 的位置由用户配置记录（可被用户组
排到前面或后面）。每个组内顶层 `rules` 的顺序决定同级规则优先级。

## 4.2 规则与 Viewer

规则字段：

| 字段 | 说明 |
| --- | --- |
| `id` | 全局稳定 ID |
| `enabled` | 是否参与解析 |
| `type` | `path`、`fileName`、`extension` 或 `mimeType` |
| `value` | 规范化后的匹配值 |
| `mode` | 仅路径规则使用：`exact` 或 `glob` |
| `rules` | 有序子规则 |
| `viewers` | 当前规则命中后贡献的有序 Viewer |

Viewer 条目只包含稳定插件 `id` 与 `enabled`。旧版 `managed` 字段被退役：
读取旧配置时兼容解析，新配置不再写出，规则/Viewer 的只读性由所属预置组决定。

路径规则必须使用 Windows 绝对路径，匹配不区分大小写，`/` 会规范化为 `\`。
`exact` 不允许 `*` 或 `?`；`glob` 中 `*` 匹配单个路径段，`**` 可跨目录，
`?` 匹配一个非分隔符字符。

## 4.3 预置组权限与版本迁移

| 对象 | 允许操作 | 不允许操作 |
| --- | --- | --- |
| 预置 default 分组 | 只读展示（选择、查看） | 启用/禁用、改名、删除、拖拽排序、增删规则/Viewer |
| 预置组内规则 | 只读展示（选择、折叠、过滤） | 启用/禁用、拖拽、编辑、删除、添加子规则/Viewer |
| 预置规则上的 Viewer | 只读展示 | 启用/禁用、排序、增删 |
| 用户分组 | 启用/禁用、拖拽排序、改名、删除 | 无额外限制 |
| 用户规则/Viewer | 全部 | — |

plugins 静态配置结构（与默认规则同树）：`fileName`、`extension`、`mimeType`
四种类型可混合嵌套。后缀冲突的项（如 `.md` 同时被代码与 Markdown 查看器声明、
`.cbz` 同时被压缩包与漫画查看器声明）以 **MIME 子规则覆盖**：扩展名规则保留回退
Viewer，子 `mimeType` 规则提供专用 Viewer，MIME 命中时子规则优先（解析语义见 §5）。

旧版本（< 3）配置按以下规则迁移为新 model：

1. 旧内置四组（路径/文件名/扩展名/MIME）整体丢弃，默认规则一律以 plugins
   静态配置为准。
2. 旧内置组中的**用户规则**（非 managed 规则，以及用户添加到默认规则上的
   自定义 Viewer / 子规则）转入新建用户组"我的规则"（id `migrated-rules`），
   排在所有用户组之前、default 之前，保持原有覆盖优先级。
3. 用户自定义组保留原样，相对顺序不变。
4. 迁移后写回 `schemaVersion: 3`；高于当前版本的配置不会被覆盖。

## 5. 候选解析

Resolver 从前到后遍历已启用的 `groups`，每个组按树中顺序遍历顶层规则。规则只有在自身匹配
且启用时才进入其分支；进入分支后先递归解析子规则，再追加当前规则的 Viewer。因此子规则天然
比父规则更具体、优先级更高，语义等价于嵌套 `if`：

```text
if extension == ".bar":
    if mime == "application/x-bar-v1":
        candidates += [bar-v1-view]
    candidates += [bar-view, hex-view]
```

对 `sample.bar` 和 `application/x-bar-v1`，候选顺序是
`[bar-v1-view, bar-view, hex-view]`；MIME 不匹配时则是 `[bar-view, hex-view]`。
兄弟规则、规则组和 Viewer 列表都按用户可见顺序执行。最后按插件 ID 去重，第一次出现的位置生效。

四种规则使用同一套匹配事实：

- `path`：匹配规范化绝对路径；
- `fileName`：不区分大小写的完整文件名；
- `extension`：匹配全部复合后缀，例如同一文件可依次命中 `.tar.gz` 和 `.gz`；
- `mimeType`：匹配精确 MIME 或 `type/*` 通配符。

没有用户配置或配置里只有 default 引用时，Resolver 使用 plugins 静态配置的默认规则树。
单候选直接使用；多候选使用 plugins 静态配置树中的顺序（后缀冲突项由 MIME 子规则
优先，见 §4.3）。前一个 Viewer 启动失败时继续尝试后续候选。Resolver 同时保留候选
首次命中的规则组 ID、规则类型、匹配值和规则 ID，供后续诊断界面展示。

例如，代码文件可以同时由 `inf-dir.code-view`（CodeMirror 只读代码查看器）和
`inf-dir.markdown-view`（Markdown 渲染查看器）声明支持。两者会作为独立候选出现，不会互相
覆盖；需要固定首选查看器时，在关联配置中调整对应扩展名或文件名的候选顺序。

F3 使用当前焦点面板中最近操作的项目。文件夹、无候选、插件缺失和进程启动失败必须给用户可见反馈。

## 6. 配置界面

插件关联界面使用三列：

1. 规则组列：选择、启用/禁用、拖拽排序、新建用户组和删除用户组。预置 default
   分组整行只读（无勾选、无拖拽手柄、无重命名/删除），但可被用户组拖到前后。
2. 规则树列：显示当前组的递归规则，支持折叠、按名称过滤（关键字框），用户组
   内规则支持启用/禁用、新建、编辑和删除；预置组规则整列只读（无勾选、无拖拽）。
3. Viewer 列：显示所选规则的有序 Viewer，支持启用/禁用、添加、拖拽排序和删除
   用户 Viewer；预置规则只读展示。

规则拖拽有三个明确落点：

- 拖到规则上方插入线：移动到该规则之前，保持同一层级；
- 拖到规则行：成为该规则最后一个子规则；
- 拖到用户组：移动为目标组最后一个顶层规则（预置组不接受拖入）。

父规则不能拖入自己的后代。规则树与 Viewer 列都使用拖拽手柄，不再提供上移/下移按钮。
预置组及其中所有内容以锁图标标识只读；用户组内的规则与 Viewer 顺序、启用状态
就是用户配置，不需要额外记录“是否修改过”。
