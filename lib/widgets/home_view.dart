import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/file_service.dart';
import '../services/home_service.dart';
import '../services/icon_service.dart';
import '../state/pane_controller.dart';
import 'app_theme.dart';

enum _HomeListTab { recent, favorites, shared }

enum _RowAction { openLocation, copyPath, addFavorite, removeFavorite }

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
  List<RecentFile> _recommended = const [];
  List<RecentFile> _recentFiles = const [];
  List<RecentFile> _favorites = const [];
  _HomeListTab _activeTab = _HomeListTab.recent;
  int _loadId = 0;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _recommendedScrollController = ScrollController();

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
    _recommendedScrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.isHome) _loadHomeData();
  }

  void _loadHomeData() {
    final loadId = ++_loadId;
    Future<void>.delayed(Duration.zero, () {
      final recommended = HomeService.getRecommendedFiles(limit: 8);
      final recent = HomeService.getRecentFiles();
      final favorites = HomeService.getFavorites(limit: 50);
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _recommended = recommended;
        _recentFiles = recent;
        _favorites = favorites;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth > 40
            ? constraints.maxWidth - 40
            : constraints.maxWidth;
        return Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HomeSectionHeader(label: '推荐'),
                const SizedBox(height: 10),
                _buildRecommendations(context, availableWidth),
                const SizedBox(height: 22),
                _HomeTabBar(
                  activeTab: _activeTab,
                  onChanged: (tab) => setState(() => _activeTab = tab),
                ),
                const SizedBox(height: 10),
                _buildActivityList(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecommendations(BuildContext context, double availableWidth) {
    if (_recommended.isEmpty) {
      return _emptyLine(context, '暂无推荐文件');
    }

    const gap = 12.0;
    final fitWidth = (availableWidth - gap * 7) / 8;
    final cardWidth = fitWidth >= 180 ? fitWidth : 228.0;
    return Scrollbar(
      controller: _recommendedScrollController,
      child: SingleChildScrollView(
        controller: _recommendedScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            for (var i = 0; i < _recommended.length && i < 8; i++) ...[
              SizedBox(
                width: cardWidth,
                child: _RecommendedCard(
                  item: _recommended[i],
                  showFileExtensions: widget.showFileExtensions,
                  onTap: () => FileService.openFile(_recommended[i].path),
                ),
              ),
              if (i < _recommended.length - 1 && i < 7)
                const SizedBox(width: gap),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActivityList(BuildContext context) {
    final items = switch (_activeTab) {
      _HomeListTab.recent => _recentFiles,
      _HomeListTab.favorites => _favorites,
      _HomeListTab.shared => const <RecentFile>[],
    };

    if (_activeTab == _HomeListTab.shared) {
      return _emptyLine(context, '暂无已共享文件');
    }
    if (items.isEmpty) {
      return _emptyLine(
        context,
        _activeTab == _HomeListTab.recent ? '暂无最近使用的文件' : '暂无收藏文件',
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ActivityHeader(),
          for (var i = 0; i < items.length; i++) ...[
            _ActivityRow(
              item: items[i],
              isFavorite:
                  _activeTab == _HomeListTab.favorites ||
                  HomeService.isFavorite(items[i].path),
              showFileExtensions: widget.showFileExtensions,
              onTap: () => FileService.openFile(items[i].path),
              onOpenLocation: () =>
                  FileService.openContainingFolder(items[i].path),
              onCopyPath: () =>
                  Clipboard.setData(ClipboardData(text: items[i].path)),
              onFavoriteChanged: () {
                if (HomeService.isFavorite(items[i].path)) {
                  HomeService.removeFavorite(items[i].path);
                } else {
                  HomeService.addFavorite(items[i].path);
                }
                _loadHomeData();
              },
            ),
            if (i < items.length - 1)
              Divider(height: 1, color: context.colors.border),
          ],
        ],
      ),
    );
  }

  Widget _emptyLine(BuildContext context, String text) {
    return Padding(
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
}

class _HomeSectionHeader extends StatelessWidget {
  final String label;

  const _HomeSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(
          Icons.keyboard_arrow_down,
          size: AppMetrics.iconMd,
          color: c.textSecondary,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _HomeTabBar extends StatelessWidget {
  final _HomeListTab activeTab;
  final ValueChanged<_HomeListTab> onChanged;

  const _HomeTabBar({required this.activeTab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HomeTab(
          icon: Icons.history,
          label: '最近使用的文件',
          active: activeTab == _HomeListTab.recent,
          onTap: () => onChanged(_HomeListTab.recent),
        ),
        const SizedBox(width: 8),
        _HomeTab(
          icon: Icons.star_border,
          label: '收藏夹',
          active: activeTab == _HomeListTab.favorites,
          onTap: () => onChanged(_HomeListTab.favorites),
        ),
        const SizedBox(width: 8),
        _HomeTab(
          icon: Icons.people_outline,
          label: '已共享',
          active: activeTab == _HomeListTab.shared,
          onTap: () => onChanged(_HomeListTab.shared),
        ),
      ],
    );
  }
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

class _RecommendedCard extends StatelessWidget {
  final RecentFile item;
  final bool showFileExtensions;
  final VoidCallback onTap;

  const _RecommendedCard({
    required this.item,
    this.showFileExtensions = true,
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
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
        child: Container(
          height: 178,
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: AppMetrics.iconSm,
                      color: c.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '你经常打开此',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppMetrics.fontSmall,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            _formatDate(item.modified),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppMetrics.fontCaption,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: c.surfaceSubtle,
                  alignment: Alignment.center,
                  child: _HomeIcon(
                    path: item.path,
                    isDirectory: false,
                    fallback: Icons.insert_drive_file_outlined,
                    size: 64,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                child: Row(
                  children: [
                    _HomeIcon(
                      path: item.path,
                      isDirectory: false,
                      fallback: Icons.insert_drive_file_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayHomeName(item.name, showFileExtensions),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppMetrics.fontSmall,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            _shortPath(item.path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppMetrics.fontCaption,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 34,
      color: c.surfaceSubtle,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children:
            [
              const Expanded(flex: 4, child: Text('名称')),
              const Expanded(flex: 2, child: Text('访问日期')),
              const Expanded(flex: 5, child: Text('路径')),
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

class _ActivityRow extends StatefulWidget {
  final RecentFile item;
  final bool isFavorite;
  final bool showFileExtensions;
  final VoidCallback onTap;
  final VoidCallback onOpenLocation;
  final VoidCallback onCopyPath;
  final VoidCallback onFavoriteChanged;

  const _ActivityRow({
    required this.item,
    required this.isFavorite,
    this.showFileExtensions = true,
    required this.onTap,
    required this.onOpenLocation,
    required this.onCopyPath,
    required this.onFavoriteChanged,
  });

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: _hovering ? c.surfaceHover : c.surface,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: c.surfaceHover,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  return Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Row(
                          children: [
                            _HomeIcon(
                              path: widget.item.path,
                              isDirectory: false,
                              fallback: Icons.insert_drive_file_outlined,
                              size: 27,
                            ),
                            const SizedBox(width: 10),
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
                      if (!compact) ...[
                        Expanded(
                          flex: 2,
                          child: Text(
                            _formatDate(widget.item.modified),
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
                      ],
                      SizedBox(
                        width: 72,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_hovering)
                              PopupMenuButton<_RowAction>(
                                tooltip: '更多操作',
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  Icons.more_horiz,
                                  size: AppMetrics.iconMd,
                                  color: c.textSecondary,
                                ),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: _RowAction.openLocation,
                                    child: Text('打开文件位置'),
                                  ),
                                  const PopupMenuItem(
                                    value: _RowAction.copyPath,
                                    child: Text('复制路径'),
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
                                      widget.onOpenLocation();
                                    case _RowAction.copyPath:
                                      widget.onCopyPath();
                                    case _RowAction.addFavorite:
                                    case _RowAction.removeFavorite:
                                      widget.onFavoriteChanged();
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
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

String _shortPath(String path) {
  if (path.toLowerCase().endsWith('.lnk')) return '最近使用';
  final parent = p.dirname(path);
  return parent == path ? path : parent;
}

String _displayHomeName(String name, bool showFileExtensions) {
  if (showFileExtensions) return name;
  final extension = p.extension(name);
  return extension.isEmpty ? name : p.basenameWithoutExtension(name);
}
