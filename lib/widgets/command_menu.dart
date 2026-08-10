import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/pane_controller.dart';
import 'app_theme.dart';

class CommandMenuItem {
  final IconData? icon;
  final String? label;
  final String? shortcut;
  final bool enabled;
  final bool checked;
  final bool isDivider;
  final List<CommandMenuItem>? children;
  final VoidCallback? onAction;

  const CommandMenuItem({
    this.icon,
    this.label,
    this.shortcut,
    this.enabled = true,
    this.checked = false,
    this.children,
    this.onAction,
  }) : isDivider = false;

  const CommandMenuItem.divider()
    : icon = null,
      label = null,
      shortcut = null,
      enabled = true,
      checked = false,
      isDivider = true,
      children = null,
      onAction = null;
}

class CommandMenuConfig {
  final bool canSearch;
  final bool canCreate;
  final bool canCut;
  final bool canCopy;
  final bool canPaste;
  final bool canRename;
  final bool canDelete;
  final bool canSelectAll;
  final bool canShowProperties;
  final bool showHiddenFiles;
  final bool showFileExtensions;
  final SortColumn sortColumn;
  final bool sortAscending;
  final PaneViewMode viewMode;
  final EntryFilter entryFilter;
  final VoidCallback? onCreateFolder;
  final VoidCallback? onCreateTextFile;
  final VoidCallback? onCut;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final ValueChanged<SortColumn>? onSortColumn;
  final ValueChanged<bool>? onSortAscending;
  final ValueChanged<PaneViewMode>? onViewMode;
  final ValueChanged<EntryFilter>? onFilter;
  final VoidCallback? onSearch;
  final VoidCallback? onSelectAll;
  final VoidCallback? onRefresh;
  final VoidCallback? onToggleHiddenFiles;
  final VoidCallback? onToggleFileExtensions;
  final VoidCallback? onProperties;

  const CommandMenuConfig({
    this.canSearch = true,
    this.canCreate = true,
    this.canCut = false,
    this.canCopy = false,
    this.canPaste = false,
    this.canRename = false,
    this.canDelete = false,
    this.canSelectAll = false,
    this.canShowProperties = false,
    this.showHiddenFiles = false,
    this.showFileExtensions = true,
    this.sortColumn = SortColumn.name,
    this.sortAscending = true,
    this.viewMode = PaneViewMode.details,
    this.entryFilter = EntryFilter.all,
    this.onCreateFolder,
    this.onCreateTextFile,
    this.onCut,
    this.onCopy,
    this.onPaste,
    this.onRename,
    this.onDelete,
    this.onSortColumn,
    this.onSortAscending,
    this.onViewMode,
    this.onFilter,
    this.onSearch,
    this.onSelectAll,
    this.onRefresh,
    this.onToggleHiddenFiles,
    this.onToggleFileExtensions,
    this.onProperties,
  });
}

CommandMenuItem _checked({
  required String label,
  required bool checked,
  IconData? icon,
  bool enabled = true,
  VoidCallback? onAction,
}) {
  return CommandMenuItem(
    label: label,
    icon: icon,
    checked: checked,
    enabled: enabled,
    onAction: onAction,
  );
}

List<CommandMenuItem> buildCommandMenuItems(CommandMenuConfig m) {
  return [
    CommandMenuItem(
      icon: Icons.search,
      label: '搜索',
      enabled: m.canSearch,
      onAction: m.onSearch,
    ),
    CommandMenuItem(
      icon: Icons.add,
      label: '新建',
      enabled: m.canCreate,
      children: [
        CommandMenuItem(
          icon: Icons.create_new_folder_outlined,
          label: '文件夹',
          onAction: m.onCreateFolder,
        ),
        CommandMenuItem(
          icon: Icons.note_add_outlined,
          label: '文本文档',
          onAction: m.onCreateTextFile,
        ),
      ],
    ),
    CommandMenuItem(
      icon: Icons.content_cut,
      label: '剪切',
      shortcut: 'Ctrl+X',
      enabled: m.canCut,
      onAction: m.onCut,
    ),
    CommandMenuItem(
      icon: Icons.content_copy,
      label: '复制',
      shortcut: 'Ctrl+C',
      enabled: m.canCopy,
      onAction: m.onCopy,
    ),
    CommandMenuItem(
      icon: Icons.content_paste,
      label: '粘贴',
      shortcut: 'Ctrl+V',
      enabled: m.canPaste,
      onAction: m.onPaste,
    ),
    CommandMenuItem(
      icon: Icons.drive_file_rename_outline,
      label: '重命名',
      shortcut: 'F2',
      enabled: m.canRename,
      onAction: m.onRename,
    ),
    CommandMenuItem(
      icon: Icons.delete_outline,
      label: '删除',
      shortcut: 'Delete',
      enabled: m.canDelete,
      onAction: m.onDelete,
    ),
    const CommandMenuItem.divider(),
    CommandMenuItem(
      icon: Icons.sort,
      label: '排序',
      children: [
        _checked(
          label: '名称',
          checked: m.sortColumn == SortColumn.name,
          onAction: () => m.onSortColumn?.call(SortColumn.name),
        ),
        _checked(
          label: '修改日期',
          checked: m.sortColumn == SortColumn.dateModified,
          onAction: () => m.onSortColumn?.call(SortColumn.dateModified),
        ),
        _checked(
          label: '类型',
          checked: m.sortColumn == SortColumn.type,
          onAction: () => m.onSortColumn?.call(SortColumn.type),
        ),
        _checked(
          label: '大小',
          checked: m.sortColumn == SortColumn.size,
          onAction: () => m.onSortColumn?.call(SortColumn.size),
        ),
        const CommandMenuItem.divider(),
        _checked(
          label: '升序',
          checked: m.sortAscending,
          onAction: () => m.onSortAscending?.call(true),
        ),
        _checked(
          label: '降序',
          checked: !m.sortAscending,
          onAction: () => m.onSortAscending?.call(false),
        ),
      ],
    ),
    CommandMenuItem(
      icon: FileCommandMenuIcons.viewIcon(m.viewMode),
      label: '查看',
      children: [
        _checked(
          label: '超大图标',
          checked: m.viewMode == PaneViewMode.extraLargeIcons,
          icon: Icons.grid_on,
          onAction: () => m.onViewMode?.call(PaneViewMode.extraLargeIcons),
        ),
        _checked(
          label: '大图标',
          checked: m.viewMode == PaneViewMode.largeIcons,
          icon: Icons.view_module,
          onAction: () => m.onViewMode?.call(PaneViewMode.largeIcons),
        ),
        _checked(
          label: '中图标',
          checked: m.viewMode == PaneViewMode.mediumIcons,
          icon: Icons.grid_view,
          onAction: () => m.onViewMode?.call(PaneViewMode.mediumIcons),
        ),
        _checked(
          label: '小图标',
          checked: m.viewMode == PaneViewMode.smallIcons,
          icon: Icons.grid_view,
          onAction: () => m.onViewMode?.call(PaneViewMode.smallIcons),
        ),
        const CommandMenuItem.divider(),
        _checked(
          label: '详细信息',
          checked: m.viewMode == PaneViewMode.details,
          icon: Icons.view_headline,
          onAction: () => m.onViewMode?.call(PaneViewMode.details),
        ),
        _checked(
          label: '列表',
          checked: m.viewMode == PaneViewMode.list,
          icon: Icons.view_list,
          onAction: () => m.onViewMode?.call(PaneViewMode.list),
        ),
        _checked(
          label: '平铺',
          checked: m.viewMode == PaneViewMode.tiles,
          icon: Icons.view_quilt,
          onAction: () => m.onViewMode?.call(PaneViewMode.tiles),
        ),
        _checked(
          label: '内容',
          checked: m.viewMode == PaneViewMode.content,
          icon: Icons.view_agenda,
          onAction: () => m.onViewMode?.call(PaneViewMode.content),
        ),
      ],
    ),
    CommandMenuItem(
      icon: Icons.filter_alt_outlined,
      label: '筛选器',
      children: [
        _checked(
          label: '全部',
          checked: m.entryFilter == EntryFilter.all,
          onAction: () => m.onFilter?.call(EntryFilter.all),
        ),
        _checked(
          label: '文件夹',
          checked: m.entryFilter == EntryFilter.folders,
          onAction: () => m.onFilter?.call(EntryFilter.folders),
        ),
        _checked(
          label: '文件',
          checked: m.entryFilter == EntryFilter.files,
          onAction: () => m.onFilter?.call(EntryFilter.files),
        ),
        _checked(
          label: '图片',
          checked: m.entryFilter == EntryFilter.images,
          onAction: () => m.onFilter?.call(EntryFilter.images),
        ),
        _checked(
          label: '文档',
          checked: m.entryFilter == EntryFilter.documents,
          onAction: () => m.onFilter?.call(EntryFilter.documents),
        ),
      ],
    ),
    const CommandMenuItem.divider(),
    CommandMenuItem(
      icon: Icons.more_horiz,
      label: '更多',
      children: [
        CommandMenuItem(
          icon: Icons.select_all,
          label: '全选',
          shortcut: 'Ctrl+A',
          enabled: m.canSelectAll,
          onAction: m.onSelectAll,
        ),
        CommandMenuItem(
          icon: Icons.refresh,
          label: '刷新',
          shortcut: 'F5',
          onAction: m.onRefresh,
        ),
        const CommandMenuItem.divider(),
        _checked(
          label: '显示隐藏项目',
          checked: m.showHiddenFiles,
          onAction: m.onToggleHiddenFiles,
        ),
        _checked(
          label: '显示文件后缀名',
          checked: m.showFileExtensions,
          onAction: m.onToggleFileExtensions,
        ),
        CommandMenuItem(
          icon: Icons.info_outline,
          label: '属性',
          enabled: m.canShowProperties,
          onAction: m.onProperties,
        ),
      ],
    ),
  ];
}

abstract final class FileCommandMenuIcons {
  static IconData viewIcon(PaneViewMode mode) {
    return switch (mode) {
      PaneViewMode.details => Icons.view_headline,
      PaneViewMode.list => Icons.view_list,
      PaneViewMode.compact || PaneViewMode.smallIcons => Icons.grid_view,
      PaneViewMode.extraLargeIcons => Icons.grid_on,
      PaneViewMode.largeIcons => Icons.view_module,
      PaneViewMode.mediumIcons => Icons.grid_view,
      PaneViewMode.tiles => Icons.view_quilt,
      PaneViewMode.content => Icons.view_agenda,
    };
  }
}

void showCommandMenu(
  BuildContext context, {
  required Offset position,
  CommandMenuConfig? config,
  List<CommandMenuItem>? items,
  VoidCallback? onClosed,
}) {
  final resolvedItems = items ?? buildCommandMenuItems(config!);
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CommandMenuOverlay(
      position: position,
      items: resolvedItems,
      onClosed: onClosed,
      close: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _Flyout {
  final CommandMenuItem item;
  final Offset position;

  const _Flyout(this.item, this.position);
}

class _CommandMenuOverlay extends StatefulWidget {
  final Offset position;
  final List<CommandMenuItem> items;
  final VoidCallback? onClosed;
  final VoidCallback close;

  const _CommandMenuOverlay({
    required this.position,
    required this.items,
    this.onClosed,
    required this.close,
  });

  @override
  State<_CommandMenuOverlay> createState() => _CommandMenuOverlayState();
}

class _CommandMenuOverlayState extends State<_CommandMenuOverlay>
    with SingleTickerProviderStateMixin {
  static const double menuWidth = 260;
  static const double itemHeight = 32;
  static const double dividerHeight = 9;
  static const double _screenMargin = 8;
  // 对齐 contextmenu（animations 包 FadeScaleTransition）：出现 150ms
  // （fade 前 30% 完成 + scale 0.8→1）、消失 75ms 纯 fade、
  // 避障修正滑动 75ms。
  static const Duration _openDuration = Duration(milliseconds: 150);
  static const Duration _closeDuration = Duration(milliseconds: 75);
  static const Duration _moveDuration = Duration(milliseconds: 75);

  _Flyout? _flyout;
  late Offset _menuPos;
  bool _repositioned = false;
  bool _closing = false;
  VoidCallback? _afterClose;
  late final AnimationController _anim;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;

  @override
  void initState() {
    super.initState();
    _menuPos = widget.position;
    _anim = AnimationController(vsync: this, duration: _openDuration)
      ..forward();
    _fadeIn = CurvedAnimation(
      parent: _anim,
      curve: const Interval(0.0, 0.3),
    );
    _scaleIn = Tween<double>(begin: 0.80, end: 1.00).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// 避障：请求位置越界时平移回屏幕内（保留 8px 边距）。
  static Offset _avoidBounds(Offset requested, Size size, Size screen) {
    var x = requested.dx;
    if (x + size.width > screen.width - _screenMargin) {
      x = screen.width - _screenMargin - size.width;
    }
    if (x < _screenMargin) x = _screenMargin;
    var y = requested.dy;
    if (y + size.height > screen.height - _screenMargin) {
      y = screen.height - _screenMargin - size.height;
    }
    if (y < _screenMargin) y = _screenMargin;
    return Offset(x, y);
  }

  /// 播放消失动画（75ms 纯 fade），结束后移除菜单并执行回调。
  void _startClose([VoidCallback? onClosed]) {
    if (_closing) return;
    setState(() => _closing = true);
    _afterClose = onClosed;
    _anim.duration = _closeDuration;
    _anim.reverse().whenComplete(() {
      widget.close();
      widget.onClosed?.call();
      _afterClose?.call();
    });
  }

  double _listHeight(List<CommandMenuItem> items) {
    double h = 0;
    for (final i in items) {
      h += i.isDivider ? dividerHeight : itemHeight;
    }
    return h;
  }

  void _run(CommandMenuItem item) {
    _startClose(item.onAction);
  }

  void _openFlyout(CommandMenuItem item, BuildContext itemContext) {
    if (_flyout?.item == item) return;
    final box = itemContext.findRenderObject()! as RenderBox;
    final topRight = box.localToGlobal(Offset(box.size.width, 0));
    final screen = MediaQuery.sizeOf(context);
    final fh = 8 + _listHeight(item.children ?? const []);
    // flyout 优先挂在主菜单右侧，放不下时翻到左侧。
    var x = topRight.dx - 6;
    if (x + menuWidth > screen.width - _screenMargin) {
      x = _menuPos.dx - menuWidth + 6;
    }
    var y = topRight.dy - 6;
    if (y + fh > screen.height - _screenMargin) {
      y = screen.height - _screenMargin - fh;
    }
    if (y < _screenMargin) y = _screenMargin;
    setState(() => _flyout = _Flyout(item, Offset(x, y)));
  }

  void _hover(
    CommandMenuItem item,
    BuildContext itemContext, {
    bool fromFlyout = false,
  }) {
    if (item.children != null) {
      _openFlyout(item, itemContext);
    } else if (!fromFlyout && _flyout != null) {
      setState(() => _flyout = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final items = widget.items;
    final mh = 8 + _listHeight(items);
    // 避障修正：第一帧按请求位置渲染，post-frame 后滑向屏幕内目标位置。
    final target = _avoidBounds(widget.position, Size(menuWidth, mh), screen);
    if (!_repositioned && target != widget.position) {
      _repositioned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _menuPos = target);
      });
    }

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _startClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _startClose,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          AnimatedPositioned(
            duration: _moveDuration,
            curve: Curves.easeOut,
            left: _menuPos.dx,
            top: _menuPos.dy,
            child: _closing
                ? FadeTransition(opacity: _anim, child: _panel(
                    context,
                    items: items,
                    maxHeight: screen.height - _menuPos.dy - _screenMargin,
                  ))
                : FadeTransition(
                    opacity: _fadeIn,
                    child: ScaleTransition(
                      scale: _scaleIn,
                      child: _panel(
                        context,
                        items: items,
                        maxHeight:
                            screen.height - _menuPos.dy - _screenMargin,
                      ),
                    ),
                  ),
          ),
          if (_flyout != null)
            AnimatedPositioned(
              duration: _moveDuration,
              curve: Curves.easeOut,
              left: _flyout!.position.dx,
              top: _flyout!.position.dy,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: _openDuration,
                curve: Curves.easeOut,
                builder: (_, t, child) => Opacity(
                  opacity: Interval(0.0, 0.3).transform(t),
                  child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
                ),
                child: _panel(
                  context,
                  isFlyout: true,
                  items: _flyout!.item.children ?? const [],
                  maxHeight: screen.height - _flyout!.position.dy - _screenMargin,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panel(
    BuildContext context, {
    bool isFlyout = false,
    required List<CommandMenuItem> items,
    required double maxHeight,
  }) {
    final c = context.colors;
    // Win11 flyout 结构（圆角 8）+ active pane 同款描边 + macOS 略暗中性灰底。
    return Material(
      color: c.menuSurface,
      elevation: 6,
      shadowColor: c.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.menuRadius),
        side: BorderSide(color: c.accent.withValues(alpha: 0.6)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: menuWidth,
          minWidth: menuWidth,
          maxHeight: maxHeight,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              for (final item in items)
                _MenuItemRow(
                  item: item,
                  onAction: () => _run(item),
                  onOpenFlyout: _openFlyout,
                  onHover: (i, ctx) => _hover(i, ctx, fromFlyout: isFlyout),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItemRow extends StatelessWidget {
  final CommandMenuItem item;
  final VoidCallback onAction;
  final void Function(CommandMenuItem, BuildContext) onOpenFlyout;
  final void Function(CommandMenuItem, BuildContext) onHover;

  const _MenuItemRow({
    required this.item,
    required this.onAction,
    required this.onOpenFlyout,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (item.isDivider) {
      return SizedBox(
        height: 9,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Divider(height: 1, thickness: 1, color: c.menuBorder),
        ),
      );
    }
    final iconColor = item.enabled ? c.textSecondary : c.textTertiary;
    final labelColor = item.enabled ? c.textPrimary : c.textTertiary;
    // Win11 菜单项：hover 是四周留边的 4px 圆角高亮块。
    return MouseRegion(
      onEnter: (_) => onHover(item, context),
      child: SizedBox(
        height: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: InkWell(
            onTap: !item.enabled
                ? null
                : () {
                    if (item.children != null) {
                      onOpenFlyout(item, context);
                    } else {
                      onAction();
                    }
                  },
            hoverColor: c.surfaceHover,
            borderRadius: BorderRadius.circular(AppMetrics.menuItemRadius),
            child: SizedBox(
              height: 26,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child: item.checked
                          ? Icon(
                              Icons.check,
                              size: AppMetrics.iconSm,
                              color: c.accent,
                            )
                          : item.icon != null
                          ? Icon(
                              item.icon,
                              size: AppMetrics.iconSm,
                              color: iconColor,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.label ?? '',
                        style: TextStyle(
                          fontSize: AppMetrics.fontBody,
                          color: labelColor,
                        ),
                      ),
                    ),
                    if (item.shortcut != null)
                      Text(
                        item.shortcut!,
                        style: TextStyle(
                          fontSize: AppMetrics.fontSmall,
                          color: c.textTertiary,
                        ),
                      ),
                    if (item.children != null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right,
                        size: AppMetrics.iconSm,
                        color: c.textTertiary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
