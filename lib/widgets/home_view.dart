import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/home_service.dart';
import '../services/icon_service.dart';
import '../services/sidebar_service.dart';
import '../state/app_state.dart';
import '../state/pane_controller.dart';
import '../state/sidebar_controller.dart';
import 'app_theme.dart';
import 'cloud_status_icon.dart';

enum _HomeSection { quickAccess, recent, favorites }

class _HomeItem {
  final String name;
  final String path;
  final bool isDirectory;
  final DateTime? date;

  const _HomeItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.date,
  });
}

class HomeView extends StatefulWidget {
  final PaneController controller;
  final ValueChanged<String> onNavigate;
  final bool showFileExtensions;

  const HomeView({
    super.key,
    required this.controller,
    required this.onNavigate,
    this.showFileExtensions = true,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  List<RecentFile> _recentFiles = const [];
  List<RecentFile> _favorites = const [];
  bool _quickAccessExpanded = true;
  bool _activityExpanded = true;
  _HomeSection _activeActivity = _HomeSection.recent;
  String? _selectedPath;
  int _loadId = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _loadHomeData();
  }

  @override
  void didUpdateWidget(HomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _loadHomeData();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted || !widget.controller.isHome) return;
    setState(() {});
    _loadHomeData();
  }

  void _loadHomeData() {
    final loadId = ++_loadId;
    Future<void>.delayed(Duration.zero, () {
      final recent = HomeService.getRecentFiles();
      final favorites = HomeService.getFavorites(limit: 50);
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _recentFiles = recent;
        _favorites = favorites;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final sidebar = context.watch<SidebarSyncController>();
    final quickAccess = sidebar.quickAccessItems
        .map(_quickAccessItem)
        .toList(growable: false);
    final recent = _recentFiles.map(_recentItem).toList(growable: false);
    final favorites = _favorites.map(_recentItem).toList(growable: false);

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(context, _HomeSection.quickAccess, quickAccess),
          _buildActivitySection(context, recent, favorites),
        ],
      ),
    );
  }

  _HomeItem _quickAccessItem(QuickAccessItem item) =>
      _HomeItem(name: item.name, path: item.path, isDirectory: true);

  _HomeItem _recentItem(RecentFile item) {
    final type = FileSystemEntity.typeSync(item.path);
    return _HomeItem(
      name: item.name,
      path: item.path,
      isDirectory: type == FileSystemEntityType.directory,
      date: item.modified,
    );
  }

  Widget _buildSection(
    BuildContext context,
    _HomeSection section,
    List<_HomeItem> items,
  ) {
    final label = switch (section) {
      _HomeSection.quickAccess => '快速访问',
      _HomeSection.recent => '最近使用的文件',
      _HomeSection.favorites => '收藏夹',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 32,
          child: _HomeSectionHeader(
            label: label,
            count: items.length,
            expanded:
                section != _HomeSection.quickAccess || _quickAccessExpanded,
            onToggle: section == _HomeSection.quickAccess
                ? () => setState(
                    () => _quickAccessExpanded = !_quickAccessExpanded,
                  )
                : null,
          ),
        ),
        if (section != _HomeSection.quickAccess || _quickAccessExpanded) ...[
          if (items.isEmpty)
            _emptyLine(context, switch (section) {
              _HomeSection.quickAccess => '暂无快速访问项目',
              _HomeSection.recent => '暂无最近使用的文件',
              _HomeSection.favorites => '暂无收藏文件',
            })
          else
            _buildModeView(context, section, items),
        ],
      ],
    );
  }

  Widget _buildActivitySection(
    BuildContext context,
    List<_HomeItem> recent,
    List<_HomeItem> favorites,
  ) {
    final items = _activeActivity == _HomeSection.recent ? recent : favorites;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 28,
              height: 32,
              child: IconButton(
                onPressed: () =>
                    setState(() => _activityExpanded = !_activityExpanded),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                tooltip: _activityExpanded ? '折叠活动文件' : '展开活动文件',
                icon: Icon(
                  _activityExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: AppMetrics.iconMd,
                  color: context.colors.textTertiary,
                ),
              ),
            ),
            _HomeTab(
              icon: Icons.history,
              label: '最近使用的文件',
              active: _activeActivity == _HomeSection.recent,
              onTap: () =>
                  setState(() => _activeActivity = _HomeSection.recent),
            ),
            const SizedBox(width: 8),
            _HomeTab(
              icon: Icons.star_border,
              label: '收藏夹',
              active: _activeActivity == _HomeSection.favorites,
              onTap: () =>
                  setState(() => _activeActivity = _HomeSection.favorites),
            ),
          ],
        ),
        if (_activityExpanded) ...[
          if (items.isEmpty)
            _emptyLine(
              context,
              _activeActivity == _HomeSection.recent ? '暂无最近使用的文件' : '暂无收藏文件',
            )
          else
            _buildModeView(context, _activeActivity, items),
        ],
      ],
    );
  }

  Widget _buildModeView(
    BuildContext context,
    _HomeSection section,
    List<_HomeItem> items,
  ) {
    final mode = widget.controller.viewMode;
    if (mode == PaneViewMode.details || mode == PaneViewMode.list) {
      return _buildRows(
        context,
        section,
        items,
        details: mode == PaneViewMode.details,
      );
    }
    if (mode == PaneViewMode.tiles || mode == PaneViewMode.content) {
      return _buildContentRows(
        context,
        section,
        items,
        content: mode == PaneViewMode.content,
      );
    }
    return _buildIconGrid(context, section, items, mode);
  }

  Widget _buildRows(
    BuildContext context,
    _HomeSection section,
    List<_HomeItem> items, {
    required bool details,
  }) {
    if (!details) {
      return _HomeSurface(
        child: Column(
          children: [
            for (final item in items)
              _HomeListRow(
                item: item,
                showFileExtensions: widget.showFileExtensions,
                isSelected: item.path == _selectedPath,
                onSingleTap: () => _selectItem(item),
                onDoubleTap: () => _openItem(section, item),
              ),
          ],
        ),
      );
    }

    return _HomeSurface(
      child: Column(
        children: [
          _HomeDetailsHeader(section: section),
          for (final item in items)
            _HomeDetailsRow(
              item: item,
              section: section,
              showFileExtensions: widget.showFileExtensions,
              isSelected: item.path == _selectedPath,
              onSingleTap: () => _selectItem(item),
              onDoubleTap: () => _openItem(section, item),
            ),
        ],
      ),
    );
  }

  Widget _buildContentRows(
    BuildContext context,
    _HomeSection section,
    List<_HomeItem> items, {
    required bool content,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      child: _HomeSurface(
        child: Column(
          children: [
            for (final item in items)
              _HomeContentRow(
                item: item,
                section: section,
                content: content,
                showFileExtensions: widget.showFileExtensions,
                isSelected: item.path == _selectedPath,
                onSingleTap: () => _selectItem(item),
                onDoubleTap: () => _openItem(section, item),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconGrid(
    BuildContext context,
    _HomeSection section,
    List<_HomeItem> items,
    PaneViewMode mode,
  ) {
    final spec = switch (mode) {
      PaneViewMode.extraLargeIcons => (icon: 96.0, width: 158.0, height: 142.0),
      PaneViewMode.largeIcons => (icon: 64.0, width: 132.0, height: 108.0),
      PaneViewMode.mediumIcons => (icon: 44.0, width: 112.0, height: 84.0),
      _ => (icon: 20.0, width: 190.0, height: 38.0),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: _HomeSurface(
        child: LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final item in items)
                SizedBox(
                  width: spec.width,
                  height: spec.height,
                  child: _HomeIconTile(
                    item: item,
                    iconSize: spec.icon,
                    horizontal:
                        mode == PaneViewMode.smallIcons ||
                        mode == PaneViewMode.compact,
                    showFileExtensions: widget.showFileExtensions,
                    isSelected: item.path == _selectedPath,
                    onSingleTap: () => _selectItem(item),
                    onDoubleTap: () => _openItem(section, item),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openItem(_HomeSection section, _HomeItem item) {
    if (section == _HomeSection.quickAccess && item.isDirectory) {
      widget.onNavigate(item.path);
      return;
    }
    FileService.openFile(item.path);
  }

  void _selectItem(_HomeItem item) {
    widget.controller.setHomeSelection(item.path);
    if (item.path != _selectedPath) {
      setState(() => _selectedPath = item.path);
    }
  }

  Widget _emptyLine(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: AppMetrics.fontBody,
        color: context.colors.textSecondary,
      ),
    ),
  );
}

class _HomeTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _HomeTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 胶囊样式：激活 = surface 药丸 + textPrimary；未激活 = 透明底 textSecondary
    final fg = active ? c.textPrimary : c.textSecondary;
    return Material(
      color: active ? c.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: c.surfaceHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppMetrics.iconSm, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppMetrics.fontSmall,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSurface extends StatelessWidget {
  final Widget child;

  const _HomeSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.colors.surface, child: child);
  }
}

class _HomeSectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final bool expanded;
  final VoidCallback? onToggle;

  const _HomeSectionHeader({
    required this.label,
    required this.count,
    required this.expanded,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        if (onToggle != null)
          SizedBox(
            width: 22,
            height: 22,
            child: IconButton(
              onPressed: onToggle,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              tooltip: expanded ? '折叠快速访问' : '展开快速访问',
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: AppMetrics.iconMd,
                color: c.textTertiary,
              ),
            ),
          )
        else
          Icon(
            Icons.keyboard_arrow_down,
            size: AppMetrics.iconMd,
            color: c.textTertiary,
          ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: AppMetrics.fontSmall,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: TextStyle(
            fontSize: AppMetrics.fontCaption,
            color: c.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _HomeDetailsHeader extends StatelessWidget {
  final _HomeSection section;

  const _HomeDetailsHeader({required this.section});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dateLabel = switch (section) {
      _HomeSection.quickAccess => '类型',
      _HomeSection.recent => '最近访问',
      _HomeSection.favorites => '修改日期',
    };
    final pathLabel = section == _HomeSection.quickAccess ? '位置' : '路径';
    return Container(
      height: AppMetrics.rowHeight,
      decoration: BoxDecoration(
        color: c.surfaceSubtle,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children:
            [
              const Expanded(flex: 4, child: Text('名称')),
              Expanded(flex: 2, child: Text(dateLabel)),
              Expanded(flex: 5, child: Text(pathLabel)),
            ].map((child) {
              return DefaultTextStyle(
                style: TextStyle(
                  fontSize: AppMetrics.fontSmall,
                  fontWeight: FontWeight.w500,
                  color: c.textTertiary,
                ),
                child: child,
              );
            }).toList(),
      ),
    );
  }
}

class _HomeDetailsRow extends StatefulWidget {
  final _HomeItem item;
  final _HomeSection section;
  final bool showFileExtensions;
  final bool isSelected;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;

  const _HomeDetailsRow({
    required this.item,
    required this.section,
    required this.showFileExtensions,
    required this.isSelected,
    required this.onSingleTap,
    required this.onDoubleTap,
  });

  @override
  State<_HomeDetailsRow> createState() => _HomeDetailsRowState();
}

class _HomeDetailsRowState extends State<_HomeDetailsRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final date = widget.item.date == null ? '' : _formatDate(widget.item.date!);
    final selectedBg = widget.isSelected ? c.accent : c.surfaceHover;
    final nameColor = widget.isSelected ? c.onAccent : c.textPrimary;
    final secondaryColor = widget.isSelected
        ? c.onAccent.withValues(alpha: 0.75)
        : c.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        onPointerDown: (event) {
          // 鼠标按下即选中：避免 onTap 等待双击判定（kDoubleTapTimeout）的延迟
          if (event.buttons & kPrimaryMouseButton != 0) widget.onSingleTap();
        },
        child: GestureDetector(
          onDoubleTap: widget.onDoubleTap,
          child: Container(
            height: AppMetrics.rowHeight,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? selectedBg
                  : _hovering
                  ? c.surfaceHover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      // 云盘条目的状态图标（仅云盘显示，位于文件图标前，
                      // 与资源管理器主文件夹一致）
                      CloudStatusIcon(path: widget.item.path, size: 12, reserveSpace: true),
                      // 状态图标与文件图标之间留出间距（资源管理器主文件夹样式）
                      const SizedBox(width: 6),
                      _HomeIcon(
                        path: widget.item.path,
                        isDirectory: widget.item.isDirectory,
                        fallback: widget.item.isDirectory
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                        size: AppMetrics.iconMd,
                        modified: widget.item.date,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _displayHomeName(
                            widget.item.name,
                            widget.item.isDirectory,
                            widget.showFileExtensions,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            color: nameColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    widget.section == _HomeSection.quickAccess
                        ? (widget.item.isDirectory ? '文件夹' : '文件')
                        : date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: secondaryColor,
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Text(
                    widget.item.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: secondaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeListRow extends StatefulWidget {
  final _HomeItem item;
  final bool showFileExtensions;
  final bool isSelected;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;

  const _HomeListRow({
    required this.item,
    required this.showFileExtensions,
    required this.isSelected,
    required this.onSingleTap,
    required this.onDoubleTap,
  });

  @override
  State<_HomeListRow> createState() => _HomeListRowState();
}

class _HomeListRowState extends State<_HomeListRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Listener(
          onPointerDown: (event) {
            // 鼠标按下即选中：避免 onTap 等待双击判定（kDoubleTapTimeout）的延迟
            if (event.buttons & kPrimaryMouseButton != 0) widget.onSingleTap();
          },
          child: GestureDetector(
            onDoubleTap: widget.onDoubleTap,
            child: Container(
              height: AppMetrics.rowHeight,
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? c.accent
                    : _hovering
                    ? c.surfaceHover
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  // 云盘条目的状态图标（仅云盘显示，位于文件图标前，
                  // 与资源管理器主文件夹一致）
                  CloudStatusIcon(path: widget.item.path, size: 12, reserveSpace: true),
                  const SizedBox(width: 6),
                  _HomeIcon(
                    path: widget.item.path,
                    isDirectory: widget.item.isDirectory,
                    fallback: widget.item.isDirectory
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                    size: 20,
                    modified: widget.item.date,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _displayHomeName(
                        widget.item.name,
                        widget.item.isDirectory,
                        widget.showFileExtensions,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppMetrics.fontBody,
                        color: widget.isSelected ? c.onAccent : c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeContentRow extends StatefulWidget {
  final _HomeItem item;
  final _HomeSection section;
  final bool content;
  final bool showFileExtensions;
  final bool isSelected;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;

  const _HomeContentRow({
    required this.item,
    required this.section,
    required this.content,
    required this.showFileExtensions,
    required this.isSelected,
    required this.onSingleTap,
    required this.onDoubleTap,
  });

  @override
  State<_HomeContentRow> createState() => _HomeContentRowState();
}

class _HomeContentRowState extends State<_HomeContentRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final secondary =
        widget.section == _HomeSection.recent && widget.item.date != null
        ? '最近访问 ${_formatDate(widget.item.date!)}'
        : widget.item.isDirectory
        ? '文件夹'
        : '文件';
    return SizedBox(
      height: widget.content ? 68 : 64,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Listener(
          onPointerDown: (event) {
            // 鼠标按下即选中：避免 onTap 等待双击判定（kDoubleTapTimeout）的延迟
            if (event.buttons & kPrimaryMouseButton != 0) widget.onSingleTap();
          },
          child: GestureDetector(
            onDoubleTap: widget.onDoubleTap,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? c.accent
                    : _hovering
                    ? c.surfaceHover
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
              ),
              child: Row(
                children: [
                  // 云盘条目的状态图标（仅云盘显示，位于文件图标前，
                  // 与资源管理器主文件夹一致）
                  CloudStatusIcon(path: widget.item.path, size: 12, reserveSpace: true),
                  const SizedBox(width: 6),
                  _HomeIcon(
                    path: widget.item.path,
                    isDirectory: widget.item.isDirectory,
                    fallback: widget.item.isDirectory
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                    size: widget.content ? 40 : 34,
                    modified: widget.item.date,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayHomeName(
                            widget.item.name,
                            widget.item.isDirectory,
                            widget.showFileExtensions,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            fontWeight: FontWeight.w500,
                            color: widget.isSelected
                                ? c.onAccent
                                : c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          secondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppMetrics.fontSmall,
                            color: widget.isSelected
                                ? c.onAccent.withValues(alpha: 0.75)
                                : c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.content) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: Text(
                        widget.item.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppMetrics.fontSmall,
                          color: widget.isSelected
                              ? c.onAccent.withValues(alpha: 0.75)
                              : c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeIconTile extends StatefulWidget {
  final _HomeItem item;
  final double iconSize;
  final bool horizontal;
  final bool showFileExtensions;
  final bool isSelected;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;

  const _HomeIconTile({
    required this.item,
    required this.iconSize,
    required this.horizontal,
    required this.showFileExtensions,
    required this.isSelected,
    required this.onSingleTap,
    required this.onDoubleTap,
  });

  @override
  State<_HomeIconTile> createState() => _HomeIconTileState();
}

class _HomeIconTileState extends State<_HomeIconTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tile = Container(
      margin: const EdgeInsets.all(1),
      padding: widget.horizontal
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
          : const EdgeInsets.fromLTRB(6, 6, 6, 5),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? c.accentSubtle
            : _hovering
            ? c.surfaceHover
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
        border: Border.all(
          color: widget.isSelected ? c.accent : Colors.transparent,
        ),
      ),
      child: widget.horizontal
          ? Row(
              children: [
                // 云盘条目的状态图标（仅云盘显示，位于文件图标前，
                // 与资源管理器主文件夹一致）
                CloudStatusIcon(path: widget.item.path, size: 12, reserveSpace: true),
                const SizedBox(width: 6),
                _HomeIcon(
                  path: widget.item.path,
                  isDirectory: widget.item.isDirectory,
                  fallback: widget.item.isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: widget.iconSize,
                  modified: widget.item.date,
                ),
                const SizedBox(width: 7),
                Expanded(child: _tileName(context)),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: Center(
                    // 竖向网格：状态图标以角标形式叠在文件图标左下角
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _HomeIcon(
                          path: widget.item.path,
                          isDirectory: widget.item.isDirectory,
                          fallback: widget.item.isDirectory
                              ? Icons.folder_outlined
                              : Icons.insert_drive_file_outlined,
                          size: widget.iconSize,
                          modified: widget.item.date,
                        ),
                        Positioned(
                          left: -2,
                          bottom: -2,
                          child: CloudStatusIcon(
                            path: widget.item.path,
                            size: 12,
                            reserveSpace: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _tileName(context),
              ],
            ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        onPointerDown: (event) {
          // 鼠标按下即选中：避免 onTap 等待双击判定（kDoubleTapTimeout）的延迟
          if (event.buttons & kPrimaryMouseButton != 0) widget.onSingleTap();
        },
        child: GestureDetector(onDoubleTap: widget.onDoubleTap, child: tile),
      ),
    );
  }

  Widget _tileName(BuildContext context) {
    return Text(
      _displayHomeName(
        widget.item.name,
        widget.item.isDirectory,
        widget.showFileExtensions,
      ),
      maxLines: widget.horizontal ? 1 : 2,
      textAlign: widget.horizontal ? TextAlign.start : TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: AppMetrics.fontBody,
        color: context.colors.textPrimary,
      ),
    );
  }
}

class _HomeIcon extends StatefulWidget {
  final String path;
  final bool isDirectory;
  final IconData fallback;
  final double size;
  final DateTime? modified;

  const _HomeIcon({
    required this.path,
    required this.isDirectory,
    required this.fallback,
    required this.size,
    this.modified,
  });

  @override
  State<_HomeIcon> createState() => _HomeIconState();
}

class _HomeIconState extends State<_HomeIcon> {
  Uint8List? _thumbnail;
  int _requestId = 0;
  bool? _lastShowThumbnails;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _requestThumbnail();
  }

  @override
  void didUpdateWidget(_HomeIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.size != widget.size ||
        oldWidget.modified != widget.modified) {
      _thumbnail = null;
      _requestThumbnail();
    }
  }

  void _requestThumbnail() {
    final showThumbnails = context.read<AppState>().showThumbnails;
    _lastShowThumbnails = showThumbnails;
    if (!showThumbnails || !IconService.wantsThumbnail(widget.size)) {
      _thumbnail = null;
      return;
    }
    final sourceSize = (widget.size * View.of(context).devicePixelRatio).ceil();
    final key = IconService.thumbnailCacheKey(
      path: widget.path,
      size: sourceSize,
      modified: widget.modified,
    );
    final cached = IconService.peekThumbnail(key);
    if (cached != null) {
      _thumbnail = cached;
      return;
    }
    final requestId = ++_requestId;
    unawaited(
      IconService.getThumbnailPng(
        path: widget.path,
        size: sourceSize,
        modified: widget.modified,
      ).then((bytes) {
        if (!mounted || requestId != _requestId || bytes == null) return;
        setState(() => _thumbnail = bytes);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showThumbnails = context.select<AppState, bool>(
      (state) => state.showThumbnails,
    );
    if (_lastShowThumbnails != showThumbnails) {
      _requestThumbnail();
    }
    final c = context.colors;
    final sourceSize = (widget.size * View.of(context).devicePixelRatio).ceil();
    if (!showThumbnails || !IconService.wantsThumbnail(widget.size)) {
      _thumbnail = null;
    }

    Uint8List? png = _thumbnail;
    if (png == null) {
      try {
        png = IconService.getFileIconPng(
          widget.path,
          widget.isDirectory,
          sourceSize,
        );
      } on Object {
        png = null;
      }
    }
    if (png != null) {
      return Image.memory(
        png,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }
    return Icon(
      widget.fallback,
      size: widget.size,
      color: widget.isDirectory ? c.iconFolder : c.iconFile,
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.year}/${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

/// 目录名始终完整显示（与资源管理器一致），隐藏后缀只作用于文件。
String _displayHomeName(
  String name,
  bool isDirectory,
  bool showFileExtensions,
) {
  if (showFileExtensions || isDirectory) return name;
  final extension = p.extension(name);
  return extension.isEmpty ? name : p.basenameWithoutExtension(name);
}
