# Inf-Dir 插件规范

本文定义 Inf-Dir Quick View 与搜索提供器插件包、Manifest、构建方式、用户关联配置和 F3 解析规则。

## 1. 设计原则

- 插件使用独立进程运行，不把第三方 DLL 加载到 Flutter 主进程。
- `quickView` 与 `search` 是独立能力；搜索插件不参与 Viewer 关联解析。
- Manifest 只声明插件能力，不声明插件优先级。
- 用户关联配置只保存候选顺序和排除项；未配置的 Manifest 候选仍可增量加入。
- `extensions`、`fileNames`、`mimeTypes` 是三种独立的匹配方式，彼此为 OR。
- 文件名、后缀和 MIME 关联只能选择 Manifest 已声明支持的插件。
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
  "id": "inf-dir.text-view",
  "name": "文本查看器",
  "version": "1.0.0",
  "entrypoint": "text-view.exe",
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
| `entrypoint` | 插件目录内的 EXE 相对路径 |
| `capabilities` | 至少声明一个受支持能力：`quickView`、`search` 或 `archive` |

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

## 4. 用户关联配置

Windows 下配置文件存储在：

```text
%LOCALAPPDATA%\Inf-Dir\viewer_associations.json
```

格式如下：

```json
{
  "schemaVersion": 2,
  "rules": [
    {
      "id": "path-work-pdf",
      "enabled": true,
      "type": "path",
      "mode": "glob",
      "pattern": "C:\\Work\\**\\*.pdf",
      "viewerIds": [
        "inf-dir.pdf-view"
      ]
    }
  ],
  "associations": {
    "extensions": {
      ".pdf": {
        "enabled": true,
        "viewerOrder": ["inf-dir.pdf-view"],
        "excludedViewerIds": ["third-party.browser-view"]
      }
    },
    "fileNames": {
      "dockerfile": {
        "enabled": true,
        "viewerOrder": ["inf-dir.text-view"],
        "excludedViewerIds": []
      }
    },
    "mimeTypes": {}
  }
}
```

配置保存插件 ID，不保存 EXE 路径。关联覆盖采用增量语义：

- `enabled` 控制整条关联是否参与解析；
- `viewerOrder` 中的 Viewer 优先于 Manifest 自动候选，数组顺序就是候选顺序；
- `excludedViewerIds` 是用户明确排除的 Viewer；
- 新安装且没有被明确排除的 Viewer 会自动加入 Manifest 候选；
- 插件暂时缺失时保留其 ID，重新安装后可以恢复。

版本 1 的完整候选数组会在首次加载时迁移：当前已安装但不在旧数组中的 Viewer
会转换为明确排除项，配置随后只按版本 2 写回。

普通文件名、后缀和 MIME 关联加载与保存时必须验证：

- 插件已安装且 Manifest 有效；
- 插件具备 `quickView` 能力；
- 对应匹配组确实声明了该关联；
- MIME 精确类型可由 Manifest 中相同类型或对应的 `type/*` 覆盖。

失效配置可以保留在磁盘中供插件重新安装后恢复，但 Resolver 必须跳过。

当前版本通过 Win32 `AssocQueryStringW(ASSOCSTR_CONTENTTYPE)` 获取扩展名在 Windows
文件关联中注册的 MIME。它不读取文件内容；没有注册 MIME 时只使用文件名和扩展名。

### 4.1 路径规则

路径规则按 `rules` 数组顺序执行，每条规则只有启用和禁用两种状态。`viewerIds`
是该规则命中时贡献的有序候选，可关联任意已安装且可用的 Quick View 插件。

- 路径必须是 Windows 绝对路径；
- 匹配不区分大小写，`/` 会规范化为 `\`；
- `exact` 为精确路径，不允许 `*` 或 `?`；
- `glob` 中 `*` 匹配单个路径段内的字符，`**` 可跨目录，`?` 匹配一个非分隔符字符。

## 5. 候选解析

给定一个文件，按以下具体程度查找关联：

1. 已启用的路径规则，按配置顺序；
2. 精确文件名；
3. 后缀，复合后缀优先，例如 `.tar.gz` 先于 `.gz`；
4. 精确 MIME；
5. MIME 通配符。

所有命中规则都会贡献候选。各组按上述顺序合并并按插件 ID 去重，第一次出现的位置
决定最终优先级。例如：

```text
fileNames["readme.md"] = [A, B]
extensions[".md"]      = [B, C]
最终候选                 = [A, B, C]
```

没有用户配置时，从 Manifest 自动生成候选。单候选直接使用；多候选使用稳定的名称、ID
顺序，用户可在配置界面调整。前一个 Viewer 启动失败时继续尝试后续候选。

Resolver 同时保留每个候选首次命中的规则类型、匹配值和路径规则 ID，供后续诊断界面展示。

例如，代码文件可以同时由 `inf-dir.code-view`（CodeMirror 只读代码查看器）和
`inf-dir.text-view`（轻量文本查看器）声明支持。两者会作为独立候选出现，不会互相覆盖；
需要固定首选查看器时，在关联配置中调整对应扩展名或文件名的候选顺序。

F3 使用当前焦点面板中最近操作的项目。文件夹、无候选、插件缺失和进程启动失败必须给用户可见反馈。

## 6. 配置界面

插件关联界面包含四个标签页：路径、扩展名、文件名、MIME。

路径页支持：

- 新建和编辑精确路径或 Glob 规则；
- 启用、禁用和删除规则；
- 调整路径规则之间的优先级；
- 添加、移除和排序该规则的候选 Viewer。

扩展名、文件名和 MIME 页包括：

- 关联项列表；
- 当前候选插件列表；
- 添加、禁用关联；
- 添加、移除候选；
- 上移、下移候选；
- 恢复 Manifest 自动候选。

普通关联的候选选择器只展示 Manifest 与当前关联项匹配的已安装插件；路径规则候选
展示全部已安装且可用的 Quick View 插件。
