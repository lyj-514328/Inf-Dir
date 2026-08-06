import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/home_service.dart';
import '../services/icon_service.dart';
import '../services/sidebar_service.dart';
import '../state/pane_controller.dart';
import '../state/sidebar_controller.dart';
import 'app_theme.dart';

class HomeView extends StatefulWidget {
  final PaneController controller;
  final ValueChanged<String> onNavigate;

  const HomeView({
    super.key,
    required this.controller,
    required this.onNavigate,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  List<RecentFile> _recentFiles = const [];
  int _loadId = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _loadRecentFiles();
  }

  @override
  void didUpdateWidget(HomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _loadRecentFiles();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.isHome) _loadRecentFiles();
  }

  void _loadRecentFiles() {
    final loadId = ++_loadId;
    Future<void>.delayed(Duration.zero, () {
      final items = HomeService.getRecentFiles();
      if (!mounted || loadId != _loadId) return;
      setState(() => _recentFiles = items);
    });
  }

  @override
  Widget build(BuildContext context) {
    final quickAccess = context.watch<SidebarSyncController>().quickAccessItems;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主文件夹',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 18),
                _HomeSectionTitle(icon: Icons.bolt, label: '快速访问'),
                const SizedBox(height: 10),
                _buildQuickAccess(
                  context,
                  quickAccess,
                  constraints.maxWidth > 40 ? constraints.maxWidth - 40 : 0,
                ),
                const SizedBox(height: 24),
                _HomeSectionTitle(icon: Icons.star_border, label: '收藏夹'),
                const SizedBox(height: 8),
                _buildFavoritesPlaceholder(context),
                const SizedBox(height: 24),
                _HomeSectionTitle(icon: Icons.history, label: '最近使用的文件'),
                const SizedBox(height: 8),
                _buildRecentFiles(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickAccess(
    BuildContext context,
    List<QuickAccessItem> items,
    double availableWidth,
  ) {
    if (items.isEmpty) {
      return _emptyLine(context, '暂无快速访问项');
    }

    final columnCount = (availableWidth / 220).floor().clamp(1, 4);
    final calculatedWidth =
        (availableWidth - (columnCount - 1) * 10) / columnCount;
    final cardWidth = availableWidth < 160
        ? availableWidth
        : calculatedWidth.clamp(160.0, 280.0);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items)
          SizedBox(
            width: cardWidth,
            child: _QuickAccessCard(
              item: item,
              onTap: () => widget.onNavigate(item.path),
            ),
          ),
      ],
    );
  }

  Widget _buildFavoritesPlaceholder(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: c.surfaceSubtle,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
      ),
      child: Text(
        '收藏一些文件后，它们将在此处显示。',
        style: TextStyle(fontSize: AppMetrics.fontBody, color: c.textSecondary),
      ),
    );
  }

  Widget _buildRecentFiles(BuildContext context) {
    if (_recentFiles.isEmpty) {
      return _emptyLine(context, '暂无最近使用的文件');
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _recentFiles.length; i++) ...[
            _RecentFileRow(
              item: _recentFiles[i],
              onTap: () => FileService.openFile(_recentFiles[i].path),
            ),
            if (i < _recentFiles.length - 1)
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

class _HomeSectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HomeSectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(icon, size: AppMetrics.iconMd, color: c.textSecondary),
        const SizedBox(width: 7),
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

class _QuickAccessCard extends StatelessWidget {
  final QuickAccessItem item;
  final VoidCallback onTap;

  const _QuickAccessCard({required this.item, required this.onTap});

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
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
          ),
          child: Row(
            children: [
              _HomeIcon(
                path: item.path,
                isDirectory: true,
                fallback: _quickAccessIcon(item.name),
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppMetrics.fontBody,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.path.startsWith('::') ||
                              item.path.startsWith('shell:')
                          ? '系统位置'
                          : '本地存储',
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
            ],
          ),
        ),
      ),
    );
  }

  static IconData _quickAccessIcon(String name) {
    if (name.contains('桌面')) return Icons.desktop_windows;
    if (name.contains('下载')) return Icons.download;
    if (name.contains('文档')) return Icons.description;
    if (name.contains('图片')) return Icons.image;
    if (name.contains('音乐')) return Icons.music_note;
    if (name.contains('视频')) return Icons.videocam;
    return Icons.folder;
  }
}

class _RecentFileRow extends StatelessWidget {
  final RecentFile item;
  final VoidCallback onTap;

  const _RecentFileRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: c.surfaceHover,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showDate = constraints.maxWidth >= 420;
            final showPath = constraints.maxWidth >= 680;
            return SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _HomeIcon(
                      path: item.path,
                      isDirectory: false,
                      fallback: Icons.insert_drive_file_outlined,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppMetrics.fontBody,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    if (showDate) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 130,
                        child: Text(
                          _formatDate(item.modified),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppMetrics.fontSmall,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    if (showPath) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: Text(
                          item.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppMetrics.fontSmall,
                            color: c.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}/${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
    final png = IconService.getFileIconPng(
      path,
      isDirectory,
      (size * 1.5).round(),
    );
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
