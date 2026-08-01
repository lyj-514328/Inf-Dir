# Sidebar 与分页加载设计文档（已实施，已知缺陷见 §18）

## 1. 背景

当前链路是：

    FilePane PointerDown
      -> LayoutState.focusNode
      -> AppShell 读取 focused pane.currentPath
      -> SidebarTree.didUpdateWidget
      -> SidebarTree._syncToPath
      -> DirectoryService 分页枚举

现有 generation 检查能阻止部分过期 UI 回写，但请求状态、native session、partial children 和 Widget 状态混在一起，仍有以下风险：

- 旧请求清理时可能按 path 删除新请求的 cache/session；
- active session、in-flight、loading 状态没有统一 ownership；
- 取消请求后，partial children 和自动展开状态没有明确回滚边界；
- PaneController 和 SidebarTree 各自维护一套分页生命周期；
- GetNextEnumPage 是同步 FFI，取消只能发生在分页边界；
- build 阶段可能重复执行同步的 directoryHasChildren 查询。

目标是把请求生命周期、目录数据和树视图状态分开。

## 2. 目标

必须满足：

1. 新的路径同步请求采用 latest-wins 语义。
2. 取消旧请求后，不再请求新的分页。
3. 当前 native page 调用无法中途打断时，允许该页返回，但结果不能提交到当前 UI。
4. 旧请求已经挂载的 partial children 必须从活动树节点卸载。
5. 旧请求只能释放自己拥有的 cursor、partial state 和 loading state。
6. 已经完整加载的 cache 不因为取消而删除。
7. Sidebar 和 FilePane 使用统一的 cursor 生命周期和 request ownership。
8. dispose 后不能发生 session 泄漏或 setState。

非目标：

- 本阶段不改变 Windows Shell 枚举结果格式；
- 不引入文件系统监听或持久化缓存；
- 不为了取消而修改文件系统内容。

## 3. 取消语义

取消一个 request 是取消一次加载工作，不是撤销文件系统操作。

取消时必须：

1. 标记 request cancelled；
2. 停止调度新的 page 请求；
3. 幂等关闭该 request 拥有的 DirectoryCursor；
4. 从活动树状态删除该 request 产生的 partial children；
5. 删除该 request 产生的 loading indicator；
6. 回滚该 request 自动添加的 expanded paths；
7. 保留此前已经 complete 的目录 cache；
8. 忽略之后恢复的旧 Future 结果。

Dart 调用同步 FFI 时，点击事件无法在 native 调用中途执行。因此取消的最小粒度是“一页”。当前页返回后，必须立即检查 token 并丢弃结果。

## 4. 目标架构

    LayoutState
        |
        | activePanePath
        v
    SidebarSyncController
        |
        | latest-wins request
        v
    DirectoryRepository
        |
        | per-path cache / in-flight ownership
        v
    DirectoryCursor
        |
        | begin / nextPage / close
        v
    DirectoryService (FFI)

FilePane 的列表加载也使用 DirectoryRepository 和 DirectoryCursor，但拥有独立的 listing request。

## 5. DirectoryCursor

原生 session 由一个小型、幂等的 Dart 对象封装。

    abstract interface class DirectoryCursor {
      List<FileEntry>? nextPage({int count = 100});
      void close();
      bool get isOpen;
    }

约束：

- close 可以被调用多次；
- close 后 nextPage 直接返回 null；
- session id 只存在于 cursor 内部；
- 上层 controller 不保存全局 session id；
- 每个 task 在 finally 中关闭自己的 cursor；
- 不允许一个 task 关闭另一个 task 的 cursor。

建议在 lib/services/directory_service.dart 增加 DirectoryCursor.open 工厂，保留现有 FFI 函数作为底层实现。

## 6. RequestToken 与 latest-wins

请求需要拥有独立 token。

    class RequestToken {
      final int id;
      bool cancelled = false;

      RequestToken(this.id);

      void cancel() => cancelled = true;
      bool get isActive => !cancelled;
    }

提交新请求时：

    cancel current request
      -> close its cursors
      -> remove its partial state
    start new request
      -> load target path chain
      -> commit only while token is active

所有异步边界之后都必须检查：

    if (!token.isActive || !identical(token, currentToken)) {
      return;
    }

generation 数字可以保留用于日志和调试，但不再单独承担资源 ownership。

## 7. DirectoryRepository

Repository 负责目录数据，不负责 Widget 展开逻辑。

### 7.1 完整 cache

    Map<PathKey, DirectorySnapshot> completeCache;

只有目录枚举完成后才进入 complete cache。

取消时：

- complete cache 保留；
- 未完成的 partial page 不进入 complete cache；
- 如果活动树正在显示 partial page，则由对应 request 回滚。

### 7.2 in-flight 请求

同一路径的加载需要有明确 owner。

    class DirectoryLoadTask {
      final int requestId;
      final PathKey path;
      final DirectoryCursor cursor;
      final List<ChildDir> partialChildren;
      bool complete = false;
    }

清理前必须确认 activeTasks[path] 的 requestId 仍等于当前 task.requestId。旧 task 可以关闭自己的 cursor，但不能删除新 task 的 cache、loading 标志或 partial children。

### 7.3 分页

推荐侧栏使用 64 或 100 的 page size。每页处理顺序：

    await frame boundary
    check token
    cursor.nextPage()
    check token
    append to task.partialChildren
    check owner
    publish partial snapshot

partial children 使用不可变 List 替换，不直接修改 Widget 正在读取的共享 List。

## 8. SidebarSyncController

SidebarSyncController 接收目标路径，计算路径链：

    C:\
    C:\Users
    C:\Users\Alice
    C:\Users\Alice\Documents

然后按顺序确保每个 ancestor 的 children 已经加载。

建议状态：

    class SidebarState {
      final String? selectedPath;
      final Set<PathKey> expandedPaths;
      final Map<PathKey, DirectoryNode> nodes;
      final Map<PathKey, PartialNode> partialNodes;
    }

SidebarTree 只负责展示状态、转发点击事件和调用 controller，不直接调用 FFI、不保存 session id、不在异步函数里直接修改 cache。

## 9. Partial children 的卸载规则

partial children 必须带 owner request id。

    class PartialNode {
      final int ownerRequestId;
      final List<ChildDir> children;
      final bool loading;
    }

取消时：

    if (partialNodes[path]?.ownerRequestId == request.id) {
      partialNodes.remove(path);
    }

如果该 path 已被新 request 接管，旧 request 不得删除任何内容。

典型时序：

    request A: load X, page 1 attached
    request B: cancel A, load Y
    request C: quickly load X again
    request A: old Future resumes

A 只能清理自己的 partial state，不能碰 C 的 X 节点。

## 10. 自动展开与手动展开

展开状态拆成：

    userExpandedPaths
    syncExpandedPaths

渲染时使用二者的并集。

取消同步时只清除旧 request 的 syncExpandedPaths，保留 userExpandedPaths。用户手动展开的节点不能因为旧请求回收而折叠。

## 11. PaneController 重构

当前 PaneController 的分页任务共享 session id 和 loadingMore。重构后每次导航拥有自己的 listing request。

    class ListingRequest {
      final int revision;
      final String path;
      final DirectoryCursor cursor;
    }

PaneController 只允许满足以下条件的 request 提交：

    request.revision == currentRevision
    request.path == currentPath

分页循环使用 request 自己的 cursor，不读取全局 session id。

导航流程：

    navigateTo(path)
      -> revision++
      -> cancel old listing request
      -> clear selection
      -> publish loading(path)
      -> load first page
      -> publish first page
      -> load remaining pages
      -> publish complete

旧请求晚返回时，只关闭自己的 cursor，不修改当前 entries、loading 或排序状态。

## 12. 焦点到侧栏的同步

建议 LayoutState 暴露稳定的 active pane path notifier：

    focus pane / navigate pane
      -> activePanePath changes
      -> SidebarSyncController.syncTo(path)

Sidebar 不必依赖 didUpdateWidget 比较字符串来启动业务逻辑。

焦点和导航可能在一个点击事件中连续发生，可以用 microtask 合并同一轮事件中的重复路径，只提交最后一个 latest-wins request。

## 13. hasChildren

不要在 SidebarTree build 阶段对每一行调用同步 native probe。

优先级：

1. 使用枚举结果中的 children metadata；
2. Repository 缓存 hasChildren；
3. 只有未知节点才执行一次 probe；
4. 文件变更、refresh、创建、删除、重命名后定点失效。

build 函数应该只读取内存状态。

## 14. 原生边界

当前 native API 保持：

    BeginShellEnum
    GetNextEnumPage
    EndShellEnum

Dart 层统一包装为 cursor。

本阶段取消是 cooperative cancellation：

- cursor close 阻止后续 page；
- 已经进入 native 的同步 page 不能被 Dart 中断；
- 通过小 page size 降低取消延迟。

如果后续仍有明显卡顿，再考虑 native worker thread、独立 isolate 或异步 page callback。

## 15. 分阶段迁移

### 阶段一：封装 cursor

- 增加 DirectoryCursor；
- close 幂等；
- 删除 controller 中直接操作 session id 的代码；
- 保持现有行为不变。

### 阶段二：重构 PaneController

- 增加 listing revision；
- 每次 request 持有独立 cursor；
- 旧 request 不能提交 entries；
- 增加分页取消测试。

### 阶段三：重构 Sidebar 加载状态

- 引入 RequestToken；
- active task 带 requestId；
- partial children 带 owner；
- 取消时回滚 partial、loading 和自动展开；
- 删除 active session、in-flight 等散落状态。

### 阶段四：抽出 DirectoryRepository

- complete cache 与 partial task 分离；
- Sidebar 和 PaneController 共用 Repository；
- 统一路径规范化和 cache invalidation。

### 阶段五：清理视图职责

- SidebarTree 变成纯渲染层；
- active pane path 使用 notifier；
- 移除 build 阶段同步 probe；
- 增加性能日志和请求生命周期日志。

## 16. 测试矩阵

使用可控延迟的 fake DirectoryRepository/Cursor，覆盖：

1. A 请求开始后切换到 B；
2. A -> B -> A；
3. 同路径重复请求；
4. 旧请求在新请求之后恢复；
5. 旧 request 只能删除自己的 partial children；
6. 新 request 的 cursor 不被旧 request 关闭；
7. 取消后不再请求下一页；
8. partial 内容在取消后从活动树卸载；
9. complete cache 在取消后保留；
10. 用户手动展开状态不被取消回滚；
11. PaneController 快速 A -> B -> C；
12. Widget dispose 时仍有 cursor/page task；
13. native begin 失败；
14. native page 返回 null；
15. refresh、rename、delete 后 cache 失效。

## 17. 验收标准

- 任意快速点击序列最终只显示最后一次目标路径；
- 旧请求不会修改当前 selected path、expanded paths、children 或 entries；
- native session 没有泄漏，close 可重复调用；
- 取消后不会继续请求新的 page；
- partial children 不会跨 request 残留；
- complete cache 可被后续 request 安全复用；
- build 阶段不执行重复的同步文件系统查询；
- 侧栏和文件列表使用同一套 request ownership 原则。

## 18. 已知缺陷与限制

### 18.1 大目录加载后滚动定位不准（未修复）

现象：侧栏分页加载一个巨大目录（数千子节点）期间或之后切换目标路径，若新目标在树中位于该目录子树之后，scroll-to-selected 的落点会偏浅，停在大目录子树中间；加载期间用户也无法滚动到列表底部。

真正根因是 Flutter 框架行为，不是本设计的取消/同步逻辑：

- SidebarTree 使用 SliverFixedExtentList + SliverChildBuilderDelegate。
- SliverMultiBoxAdaptorElement.performRebuild（flutter/src/widgets/sliver.dart）在 delegate 变化时只更新已构建的子元素。当 childCount 的增长发生在视口/cacheExtent 之外、已构建子元素配置未变（childrenUpdated == false）、且视口未触达列表末端（_didUnderflow == false）时，layout 阶段被跳过，maxScrollExtent 停留在旧值。源码注释原文："Otherwise, the layout phase may be skipped, and the scroll view may be stuck at the previous max scroll offset."
- 大目录的新行全部追加在视口之外，恰好命中该路径：数据层行数（flatten）持续增长，渲染层 extent 却冻结（实测冻结点随机，两次运行为 944 / 2344 行）。extent 只在滚动活动（jumpTo / 手动滚动）强制 viewport 重排时才重新计算。
- 滚动定位逻辑把目标行偏移 clamp 到过期的 maxScrollExtent，于是落点偏浅；滚动请求随后被消费，不再重试。

诊断过程已验证的事实：

- 取消链路、partial children 回滚、complete cache 保留均按 §3 / §7 正常工作，与本缺陷无关；切走时不折叠的大目录节点属于 userExpandedPaths（§10），complete cache 按 §3.7 保留，均为设计行为；
- 用不含项目代码的最小复现（setState 递增 SliverFixedExtentList 的 childCount）可重现 extent 冻结；
- 给 SliverFixedExtentList 加 key: ValueKey(childCount) 可强制 sliver 重建、extent 全程跟随（已在最小复现和端到端 harness 中验证有效），但加载期间每页都要重建可见行，有渲染开销且体验改善不彻底，故未采纳，代码已回退。

后续可选方向：

- key: ValueKey(childCount) 强制 sliver 重建（已验证有效，代价是加载期间每页重建可见行）；
- 滚动请求改为"落到目标才消费"的重试语义，并在 partial 增长时重新武装滚动请求（曾实现并验证，随回退一并移除）；
- 改用 Scrollable.ensureVisible 按元素定位，而不是按偏移 clamp 到 maxScrollExtent；
- 等待或推动 Flutter 框架修复该 layout 跳过行为。
