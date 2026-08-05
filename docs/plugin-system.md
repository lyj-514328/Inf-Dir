# Inf-Dir Viewer 插件规范

本文定义 Inf-Dir Quick View 插件包、Manifest、用户关联配置和 F3 解析规则。

## 1. 设计原则

- 插件使用独立进程运行，不把第三方 DLL 加载到 Flutter 主进程。
- Manifest 只声明插件能力，不声明插件优先级。
- 用户关联配置中的插件 ID 数组顺序就是候选顺序。
- `extensions`、`fileNames`、`mimeTypes` 是三种独立的匹配方式，彼此为 OR。
- 用户只能把插件关联到其 Manifest 已声明支持的类型。
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
    └── inf-dir.pdf-view/
        ├── plugin.json
        ├── pdf-view.exe
        └── pdfium.dll
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
| `capabilities.quickView` | Quick View 能力声明 |

`quickView` 至少要包含一个非空匹配组。绝大多数插件只需要 `extensions`。

### 3.2 规范化

- `extensions`：小写、以点开头，例如 `.pdf`。
- `fileNames`：Windows 下不区分大小写，必须是文件名而不是路径。
- `mimeTypes`：小写、不带参数，允许 `type/*` 通配符。
- 同一数组内的重复项在加载时去重。

插件启动协议第一版为：

```text
<entrypoint> <absolute-file-path>
```

插件工作目录设为插件包目录。后续协议升级通过新增 Manifest 字段完成，不改变版本 1 的行为。

## 4. 用户关联配置

Windows 下配置文件存储在：

```text
%LOCALAPPDATA%\Inf-Dir\viewer_associations.json
```

格式如下：

```json
{
  "schemaVersion": 1,
  "associations": {
    "extensions": {
      ".pdf": ["inf-dir.pdf-view", "third-party.pdf-view"]
    },
    "fileNames": {
      "dockerfile": ["inf-dir.text-view"]
    },
    "mimeTypes": {
      "application/pdf": ["inf-dir.pdf-view"]
    }
  }
}
```

配置保存插件 ID，不保存 EXE 路径。空数组表示用户显式禁用了该关联的自动候选。

配置加载与保存时必须验证：

- 插件已安装且 Manifest 有效；
- 插件具备 `quickView` 能力；
- 对应匹配组确实声明了该关联；
- MIME 精确类型可由 Manifest 中相同类型或对应的 `type/*` 覆盖。

失效配置可以保留在磁盘中供插件重新安装后恢复，但 Resolver 必须跳过。

版本 1 通过 Win32 `AssocQueryStringW(ASSOCSTR_CONTENTTYPE)` 获取扩展名在 Windows
文件关联中注册的 MIME。它不读取文件内容；没有注册 MIME 时只使用文件名和扩展名。

## 5. 候选解析

给定一个文件，按以下具体程度查找关联：

1. 精确文件名；
2. 扩展名；
3. 精确 MIME；
4. MIME 通配符。

各组候选按配置数组顺序合并并按插件 ID 去重。例如：

```text
fileNames["readme.md"] = [A, B]
extensions[".md"]      = [B, C]
最终候选                 = [A, B, C]
```

没有用户配置时，从 Manifest 自动生成候选。单候选直接使用；多候选使用稳定的名称、ID 顺序，用户可在配置界面调整。

F3 使用当前焦点面板中最近操作的项目。文件夹、无候选、插件缺失和进程启动失败必须给用户可见反馈。

## 6. 配置界面

插件关联界面包含三个标签页：扩展名、文件名、MIME。每页包括：

- 关联项列表；
- 当前候选插件列表；
- 添加、删除关联；
- 添加、移除候选；
- 上移、下移候选；
- 恢复 Manifest 自动候选。

候选选择器只展示 Manifest 与当前关联项匹配的已安装插件。
