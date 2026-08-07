import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/home_service.dart';
import '../services/icon_service.dart';
import '../services/sidebar_service.dart';
import '../state/pane_controller.dart';
import '../state/sidebar_controller.dart';
import 'app_theme.dart';

enum _HomeSection { quickAccess, recent, favorites }

enum _RowAction { openLocation, copyPath, addFavorite, removeFavorite }

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

    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(context, _HomeSection.quickAccess, quickAccess),
            const SizedBox(height: 18),
            _buildActivitySection(context, recent, favorites),
          ],
        ),
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
        _HomeSectionHeader(
          label: label,
          count: items.length,
          expanded: section != _HomeSection.quickAccess || _quickAccessExpanded,
          onToggle: section == _HomeSection.quickAccess
              ? () =>
                    setState(() => _quickAccessExpanded = !_quickAccessExpanded)
              : null,
        ),
        if (section != _HomeSection.quickAccess || _quickAccessExpanded) ...[
          const SizedBox(height: 7),
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
                  color: context.colors.textSecondary,
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
          const SizedBox(height: 7),
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
                onTap: () => _openItem(section, item),
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
              isFavorite:
                  section == _HomeSection.favorites ||
                  HomeService.isFavorite(item.path),
              showFileExtensions: widget.showFileExtensions,
              onTap: () => _openItem(section, item),
              onOpenLocation: section == _HomeSection.quickAccess
                  ? null
                  : () => FileService.openContainingFolder(item.path),
              onCopyPath: () =>
                  Clipboard.setData(ClipboardData(text: item.path)),
              onFavoriteChanged: section == _HomeSection.quickAccess
                  ? null
                  : () => _toggleFavorite(item.path),
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
    return _HomeSurface(
      child: Column(
        children: [
          for (final item in items)
            _HomeContentRow(
              item: item,
              section: section,
              content: content,
              showFileExtensions: widget.showFileExtensions,
              onTap: () => _openItem(section, item),
            ),
        ],
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
    return _HomeSurface(
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
                  onTap: () => _openItem(section, item),
                ),
              ),
          ],
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

  void _toggleFavorite(String path) {
    if (HomeService.isFavorite(path)) {
      HomeService.removeFavorite(path);
    } else {
      HomeService.addFavorite(path);
    }
    _loadHomeData();
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
    return Material(
      color: active ? c.accent : c.surfaceSubtle,
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
              Icon(
                icon,
                size: AppMetrics.iconSm,
                color: active ? c.surface : c.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppMetrics.fontSmall,
                  color: active ? c.surface : c.textSecondary,
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
                color: c.textSecondary,
              ),
            ),
          )
        else
          Icon(
            Icons.keyboard_arrow_down,
            size: AppMetrics.iconMd,
            color: c.textSecondary,
          ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: AppMetrics.fontBody,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
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
      height: AppMetrics.rowHeight + 4,
      color: c.surfaceSubtle,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children:
            [
              const Expanded(flex: 4, child: Text('名称')),
              Expanded(flex: 2, child: Text(dateLabel)),
              Expanded(flex: 5, child: Text(pathLabel)),
              const SizedBox(width: 72),
            ].map((child) {
              return DefaultTextStyle(
                style: TextStyle(
                  fontSize: AppMetrics.fontSmall,
                  color: c.textSecondary,
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
  final bool isFavorite;
  final bool showFileExtensions;
  final VoidCallback onTap;
  final VoidCallback? onOpenLocation;
  final VoidCallback onCopyPath;
  final VoidCallback? onFavoriteChanged;

  const _HomeDetailsRow({
    required this.item,
    required this.section,
    required this.isFavorite,
    required this.showFileExtensions,
    required this.onTap,
    required this.onOpenLocation,
    required this.onCopyPath,
    required this.onFavoriteChanged,
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: _hovering ? c.surfaceHover : c.surface,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: c.surfaceHover,
          child: SizedBox(
            height: AppMetrics.rowHeight + 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        _HomeIcon(
                          path: widget.item.path,
                          isDirectory: widget.item.isDirectory,
                          fallback: widget.item.isDirectory
                              ? Icons.folder_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _displayHomeName(
                              widget.item.name,
                              widget.showFileExtensions,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppMetrics.fontBody,
                              color: c.textPrimary,
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
                        color: c.textSecondary,
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
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child:
                        _hovering && widget.section != _HomeSection.quickAccess
                        ? PopupMenuButton<_RowAction>(
                            tooltip: '更多操作',
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.more_horiz,
                              size: AppMetrics.iconMd,
                              color: c.textSecondary,
                            ),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: _RowAction.openLocation,
                                child: const Text('打开文件位置'),
                              ),
                              PopupMenuItem(
                                value: _RowAction.copyPath,
                                child: const Text('复制路径'),
                              ),
                              PopupMenuItem(
                                value: widget.isFavorite
                                    ? _RowAction.removeFavorite
                                    : _RowAction.addFavorite,
                                child: Text(
                                  widget.isFavorite ? '取消收藏' : '添加到收藏夹',
                                ),
                              ),
                            ],
                            onSelected: (action) {
                              switch (action) {
                                case _RowAction.openLocation:
                                  widget.onOpenLocation?.call();
                                case _RowAction.copyPath:
                                  widget.onCopyPath();
                                case _RowAction.addFavorite:
                                case _RowAction.removeFavorite:
                                  widget.onFavoriteChanged?.call();
                              }
                            },
                          )
                        : const SizedBox.shrink(),
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

class _HomeListRow extends StatelessWidget {
  final _HomeItem item;
  final bool showFileExtensions;
  final VoidCallback onTap;

  const _HomeListRow({
    required this.item,
    required this.showFileExtensions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      child: InkWell(
        onTap: onTap,
        hoverColor: c.surfaceHover,
        child: SizedBox(
          height: AppMetrics.rowHeight + 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _HomeIcon(
                  path: item.path,
                  isDirectory: item.isDirectory,
                  fallback: item.isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _displayHomeName(item.name, showFileExtensions),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontBody,
                      color: c.textPrimary,
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

class _HomeContentRow extends StatelessWidget {
  final _HomeItem item;
  final _HomeSection section;
  final bool content;
  final bool showFileExtensions;
  final VoidCallback onTap;

  const _HomeContentRow({
    required this.item,
    required this.section,
    required this.content,
    required this.showFileExtensions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final secondary = section == _HomeSection.recent && item.date != null
        ? '最近访问 ${_formatDate(item.date!)}'
        : item.isDirectory
        ? '文件夹'
        : '文件';
    return Material(
      color: c.surface,
      child: InkWell(
        onTap: onTap,
        hoverColor: c.surfaceHover,
        child: Container(
          constraints: BoxConstraints(minHeight: content ? 68 : 58),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              _HomeIcon(
                path: item.path,
                isDirectory: item.isDirectory,
                fallback: item.isDirectory
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined,
                size: content ? 40 : 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayHomeName(item.name, showFileExtensions),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppMetrics.fontBody,
                        fontWeight: FontWeight.w500,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppMetrics.fontSmall,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (content) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Text(
                    item.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
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
  final VoidCallback onTap;

  const _HomeIconTile({
    required this.item,
    required this.iconSize,
    required this.horizontal,
    required this.showFileExtensions,
    required this.onTap,
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
        color: _hovering ? c.surfaceHover : c.surface,
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
        border: Border.all(color: c.border),
      ),
      child: widget.horizontal
          ? Row(
              children: [
                _HomeIcon(
                  path: widget.item.path,
                  isDirectory: widget.item.isDirectory,
                  fallback: widget.item.isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: widget.iconSize,
                ),
                const SizedBox(width: 7),
                Expanded(child: _tileName(context)),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: _HomeIcon(
                      path: widget.item.path,
                      isDirectory: widget.item.isDirectory,
                      fallback: widget.item.isDirectory
                          ? Icons.folder_outlined
                          : Icons.insert_drive_file_outlined,
                      size: widget.iconSize,
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
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
          child: tile,
        ),
      ),
    );
  }

  Widget _tileName(BuildContext context) => Text(
    _displayHomeName(widget.item.name, widget.showFileExtensions),
    maxLines: widget.horizontal ? 1 : 2,
    textAlign: widget.horizontal ? TextAlign.start : TextAlign.center,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: AppMetrics.fontBody,
      color: context.colors.textPrimary,
    ),
  );
}

class _HomeIcon extends StatelessWidget {
  final String path;
  final bool isDirectory;
  final IconData fallback;
  final double size;

  const _HomeIcon({
    required this.path,
    required this.isDirectory,
    required this.fallback,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ext = p.extension(path).toLowerCase();
    if (!isDirectory &&
        const {
          '.png',
          '.jpg',
          '.jpeg',
          '.gif',
          '.bmp',
          '.webp',
        }.contains(ext) &&
        File(path).existsSync()) {
      return Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Icon(fallback, size: size, color: c.iconFile),
      );
    }

    Uint8List? png;
    try {
      png = IconService.getFileIconPng(path, isDirectory, (size * 1.5).round());
    } on Object {
      png = null;
    }
    if (png != null) {
      return Image.memory(png, width: size, height: size, fit: BoxFit.contain);
    }
    return Icon(
      fallback,
      size: size,
      color: isDirectory ? c.iconFolder : c.iconFile,
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.year}/${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _displayHomeName(String name, bool showFileExtensions) {
  if (showFileExtensions) return name;
  final extension = p.extension(name);
  return extension.isEmpty ? name : p.basenameWithoutExtension(name);
}
