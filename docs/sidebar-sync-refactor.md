# Sidebar 分页加载与自绘虚拟列表设计文档（已实施）

## 1. 背景

当前链路是：

    FilePane PointerDown
      -> LayoutState.activePaneLocation
      -> SidebarSyncController.syncTo(path)
      -> DirectoryRepository 分页加载 + per-path cache
      -> DirectoryCursor (begin / nextPage / close)
      -> DirectoryService (FFI 分页枚举)
      -> SidebarTree 自绘虚拟列表渲染

设计目标是把请求生命周期、目录数据、树视图状态三层分开，并保证快速
切换路径时无资源泄漏、无过期回写、无残留状态。

## 2. 必须满足

1. 新的路径同步请求采用 latest-wins 语义。
2. 取消旧请求后，不再请求新的分页。
3. native page 调用无法中途打断时，允许该页返回，但结果不能提交到当前 UI。
4. 旧请求已经挂载的 partial children 必须从活动树节点卸载。
5. 旧请求只能释放自己拥有的 cursor、partial state 和 loading state。
6. 已经完整加载的 cache 不因为取消而删除。
7. Sidebar 和 FilePane 使用统一的 cursor 生命周期和 request ownership。
8. dispose 后不能发生 session 泄漏或 setState。
9. 渲染层不依赖 sliver：滚动 extent 必须是纯算术，不允许出现
   "行数变了但 maxScrollExtent 没变"的窗口。
10. scroll-to-selected 必须精确：目标行之前的行数还在增长时，滚动请求
    不消费，持续重试，直到落点稳定。

非目标：

- 不改变 Windows Shell 枚举结果格式；
- 不引入文件系统监听或持久化缓存；
- 不为了取消而修改文件系统内容；
- 不为了滚动而修改行高（虚拟化要求固定行高）。

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

Dart 调用同步 FFI 时，点击事件无法在 native 调用中途执行。因此取消的
最小粒度是"一页"。当前页返回后，必须立即检查 token 并丢弃结果。

## 4. 目标架构

    LayoutState
        |
        | activePaneLocation
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

FilePane 的列表加载也使用 DirectoryRepository 和 DirectoryCursor，但拥有
独立的 listing request。

渲染层：SidebarTree 是纯视图——只读 controller 状态、转发点击、虚拟化
物化可见行。不碰 FFI、不存 session id、不在 build 里做同步 probe、
不在异步函数里改 cache。

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

## 6. RequestToken 与 latest-wins

请求拥有独立 token：

    class RequestToken {
      final int id;
      bool cancelled = false;
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

## 7. DirectoryRepository

Repository 负责目录数据，不负责 Widget 展开逻辑。

### 7.1 完整 cache

只有目录枚举完成后才进入 complete cache。取消时 complete cache 保留；
未完成的 partial page 不进入 complete cache。

### 7.2 in-flight 请求

    class DirectoryLoadTask {
      final int requestId;
      final PathKey path;
      final DirectoryCursor cursor;
      final List<ChildDir> partialChildren;
      bool complete = false;
    }

清理前必须确认 activeTasks[path] 的 requestId 仍等于当前 task.requestId。
旧 task 可以关闭自己的 cursor，但不能删除新 task 的 cache、loading 标志
或 partial children。

### 7.3 分页

page size 100。每页处理顺序：

    await frame boundary
    check token
    cursor.nextPage()
    check token
    append to task.partialChildren
    check owner
    publish partial snapshot

partial children 使用不可变 List 替换，不直接修改 Widget 正在读取的共享
List。每次 partial 发布都通知 SidebarSyncController（这也是滚动重试的
驱动源，见 §15.4）。

## 8. SidebarSyncController

接收目标路径，计算路径链并按顺序确保每个 ancestor 的 children 已加载：

    C:\
    C:\Users
    C:\Users\Alice
    C:\Users\Alice\Documents

状态：

    selectedPath
    userExpandedPaths / syncExpandedPaths     （§10）
    partialNodes: Map<PathKey, PartialNode>    （§9）
    needsScrollToSelected + scrollFollowDismissed（§15.4）

任何 partial 状态变化（loading 或 complete）都会重新武装滚动请求。

## 9. Partial children 的卸载规则

partial children 带 owner request id：

    class PartialNode {
      final int ownerRequestId;
      final List<ChildDir> children;
      final bool loading;
    }

取消时：

    if (partialNodes[path]?.ownerRequestId == request.id) {
      partialNodes.remove(path);
    }

如果该 path 已被新 request 接管，旧 request 不得删除任何内容。典型时序：

    request A: load X, page 1 attached
    request B: cancel A, load Y
    request C: quickly load X again
    request A: old Future resumes

A 只能清理自己的 partial state，不能碰 C 的 X 节点。

## 10. 自动展开与手动展开

展开状态拆成 userExpandedPaths 与 syncExpandedPaths，渲染时取并集。
取消同步时只清除旧 request 的 syncExpandedPaths，保留 userExpandedPaths。

## 11. PaneController

每次导航拥有自己的 listing request（revision + path + cursor），只允许
满足 request.revision == currentRevision 且 request.path == currentPath
的提交。旧请求晚返回时只关闭自己的 cursor，不修改当前 entries、loading
或排序状态。

## 12. 焦点到侧栏的同步

LayoutState 暴露稳定的 active pane path notifier：焦点/导航变化 ->
syncTo(path)。焦点和导航可能在一个点击事件中连续发生，用 microtask
合并同一轮事件中的重复路径，只提交最后一个 latest-wins request。

## 13. hasChildren

不在 build 阶段对每一行调用同步 native probe。优先级：

1. 枚举结果中的 children metadata；
2. Repository 缓存 hasChildren；
3. 只有未知节点才执行一次 probe；
4. 文件变更、refresh、创建、删除、重命名后定点失效。

## 14. 原生边界

native API 保持 BeginShellEnum / GetNextEnumPage / EndShellEnum，Dart 层
统一包装为 cursor。取消是 cooperative cancellation：cursor close 阻止
后续 page；已进入 native 的同步 page 不能被 Dart 中断；通过小 page size
降低取消延迟。后续如需更优可考虑 native worker thread / isolate。

## 15. 渲染层：自绘虚拟列表（SidebarTree）

### 15.1 为什么不用 sliver

历史实现是 CustomScrollView + SliverFixedExtentList。SliverMultiBoxAdaptor-
Element.performRebuild（flutter/src/widgets/sliver.dart）在 childCount
增长发生在视口/cacheExtent 之外、已构建子元素配置未变、且视口未触达
列表末端时，会跳过 layout 阶段，maxScrollExtent 停留在旧值（框架源码
注释原文："Otherwise, the layout phase may be skipped, and the scroll
view may be stuck at the previous max scroll offset."）。分页加载的大目录
恰好命中：数据层行数持续增长，渲染层 extent 冻结，scroll-to-selected
把 offset clamp 到过期的 maxScrollExtent 后落点偏浅。

这是框架行为，无可靠 workaround（key: ValueKey(childCount) 强制重建
已验证有效但每页重建可见行，代价大）。结论：**滚动 extent 不能依赖
sliver 的 layout 过程**，改为纯算术。

### 15.2 布局模型

整个侧栏内容是一个固定行高的扁平 index 空间：

    [0] 快速访问头           20px
    [1, qaCount) 快速访问行   22px × qaCount
    divider                 1px
    gap                     4px
    之后是树行                22px × treeCount

两个纯函数：

    treeStartOffset(qaCount) = 20 + 22×qaCount + 1 + 4
    totalHeight(qaCount, treeCount) = treeStartOffset + 22×treeCount

总高度是纯算术，不依赖任何 layout 结果，因此 maxScrollExtent 永远准确，
不存在过期窗口。

结构：

    Container
    └── Scrollbar(controller)
        └── SingleChildScrollView(controller)
            └── SizedBox(height: totalHeight)
                └── Stack(clipBehavior: hardEdge)
                    ├── Positioned(头部 / QA 行 / divider / gap)
                    └── Positioned(可见窗口内的树行)

### 15.3 窗口物化

树行只物化可见窗口 ±8 行缓存带：

    first = floor((offset - treeStartOffset) / 22) - 8  clamp [0, treeCount]
    last  = ceil((offset + viewport - treeStartOffset) / 22) + 8

滚动监听（ScrollController.addListener）里窗口范围变化才 setState 重建；
范围不变时零重建。5000 行的树物化约 50 个行 widget。行 widget 复用
原有实现（Shell 图标、InkWell hover、loading 指示器行）。

### 15.4 scroll-to-selected：落点稳定才消费

滚动请求（needsScrollToSelected）采用重试语义：

- **武装**：syncTo 时；以及任何 partial 更新（§7.3 的每次发布）时。
  树行数一变，滚动需求就恢复激活。
- **跳转**（build 的 postFrame 回调）：
  - 目标行未挂上树（祖先仍在加载）→ 保留请求，返回；
  - 目标行已挂上 → offset = treeStartOffset + index×22，
    jumpTo(clamp(offset - viewport/2 + 11))；
  - 跳转后检查目标行之前是否有 loadingIndicator 行：
    - 有 → 行号还会变，保留请求，等下一次 partial 更新重跳；
    - 无 → 行号稳定，消费请求，结束。

原理：目标行之前的 partial 节点仍在翻页时，它的 loading 行必然出现在
目标行之前（loading 行加在子树末尾，整棵子树树序在目标行前）。所以
"目标行前有 loading" ⇔ "目标行行号会变"，是该检测的完备条件。

等价且更本质的检测是直接比较目标行的 treeIndex 与上次跳转时的值：
index 变化则重跳，不变则消费。不依赖 loading 行的存在性。

### 15.5 用户滚动与自动跟随

用户手动滚动（position.pixels 与最近一次程序 jumpTo 的目标不同）时调用
controller.dismissScrollFollow()：消费滚动请求并置 scrollFollowDismissed，
本次同步不再自动跟随；下一次 syncTo 重置。避免"树边加载边把用户
滚动的视图拉回去"。

### 15.6 与数据层的关系

- flatten 每次 build 全量重建（O(行数) 的轻量数据行，非 widget）；
- 行号查找（indexWhere）基于 flatten 数据，不依赖 widget 物化状态；
- 跳转先算 offset 再物化：目标行未物化不影响定位（与 sliver 的
  "必须 layout 才有 extent" 形成对比）。

## 16. 已落地迁移

- 阶段一：DirectoryCursor 封装（done）；
- 阶段二：PaneController listing revision（done）；
- 阶段三：Sidebar 加载状态重构（RequestToken / partial owner / 回滚）
  （done）；
- 阶段四：DirectoryRepository（done）；
- 阶段五：视图职责清理 + 渲染层改为自绘虚拟列表 + 滚动重试语义（done）。

## 17. 测试矩阵（已覆盖，fake cursor + ManualPump）

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

## 18. 验收标准

- 任意快速点击序列最终只显示最后一次目标路径；
- 旧请求不会修改当前 selected path、expanded paths、children 或 entries；
- native session 没有泄漏，close 可重复调用；
- 取消后不会继续请求新的 page；
- partial children 不会跨 request 残留；
- complete cache 可被后续 request 安全复用；
- build 阶段不执行重复的同步文件系统查询；
- 侧栏和文件列表使用同一套 request ownership 原则；
- 大目录分页期间/之后 scroll-to-selected 落点精确（行号稳定前持续重试）；
- 用户手动滚动后不被自动跟随拉回。

## 19. 已知缺陷与限制

### 19.1 固定行高是虚拟化的前提

窗口切片按 22px 定高计算。将来若出现可变高度行（多行文本、缩略图
行），需要行高表 + offset 前缀和，复杂度上升。当前侧栏全部是定高行。

### 19.2 分页期间滚动跟随逐页重跳

大目录翻页时若目标行在其后，每页跳转一次。offset 相同则无感；不同
则视图逐页下移。这是"跟随加载"的预期行为，但快速翻页时可能有轻微
跳动感。可选优化：行号变化 < 阈值（如 5 行）时不重跳，等积累到阈值
或加载结束再跳。

### 19.3 同步 FFI 仍阻塞 UI

分页是同步 native 调用，单页调用期间 UI 冻结（页内不可取消）。当前
通过小 page size（100）控制粒度。后续可引入 native worker thread /
isolate / 异步 page callback。

### 19.4 自动跟随被手动滚动 dismiss 后不再恢复

用户手动滚动后本次同步不再自动跟随（§15.5）。若此时树继续展开且
用户希望重新跟随，需再次导航触发 syncTo。可接受，符合"用户干预优先"
的交互约定。

## 20. Current implementation on `refactor/sidebar-navigation-sync`

This section supersedes the earlier `RequestToken` sketch above. The branch uses
the following ownership and data-flow contract:

- `LayoutState.activePaneLocation` is the single observable active-pane value.
  It contains the pane id and canonical path and is updated from the focused
  `PaneController` path notifier.
- `SidebarSyncController` subscribes to that value. `selectedPath` is derived
  from it, while `syncTo` remains the internal latest-wins reveal entry point.
  `AppShell` no longer mirrors pane paths into the sidebar imperatively.
- `DirectoryRepository` owns one `_DirectoryLoad` per canonical path. Each
  caller receives a `DirectoryLoadLease`; releasing one lease only removes that
  subscriber. The cursor is closed and future pages stop only after the final
  lease is released.
- A synchronous native page cannot be interrupted in the middle of the FFI call.
  After it returns, the loader checks ownership and discards the page when the
  load has no subscribers or has been superseded. Completed results remain in
  the repository cache.
- Sidebar reveal and manual expansion can share the same path load. Cancelling
  a reveal session releases only its leases, so an active manual expansion keeps
  receiving later pages.
- FilePane listing still owns an independent cursor and listing revision. This
  keeps the UI list refresh lifecycle separate from sidebar reveal pagination;
  the shared repository contract is used for directory data and cancellation.
