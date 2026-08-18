import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../services/shell_file_operation.dart';
import '../../state/pane_controller.dart';
import '../../state/settings_controller.dart';
import '../../widgets/app_theme.dart';
import '../quick_view/viewer_associations_dialog.dart';

typedef SettingsFolderPicker = String? Function(String? initialPath);

enum SettingsCategory { general, appearance, fileOperations, viewers }

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.onShowHiddenFilesChanged,
    required this.onShowFileExtensionsChanged,
    required this.onShowThumbnailsChanged,
    required this.onClearThumbnailCache,
    this.folderPicker,
  });

  final ValueChanged<bool> onShowHiddenFilesChanged;
  final ValueChanged<bool> onShowFileExtensionsChanged;
  final ValueChanged<bool> onShowThumbnailsChanged;
  final VoidCallback onClearThumbnailCache;
  final SettingsFolderPicker? folderPicker;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final TextEditingController _searchController = TextEditingController();
  SettingsCategory _selected = SettingsCategory.general;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final categories = SettingsCategory.values
        .where((category) => _categoryMatches(category, _query))
        .toList();

    // 与工作区一致的页面骨架：windowBg 底 + 圆角白卡片双栏。
    return Padding(
      key: const ValueKey('settings-view'),
      padding: const EdgeInsets.all(AppMetrics.pagePadding),
      child: Row(
        children: [
          Container(
            width: 232,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
            ),
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 12),
                        child: Text(
                          '设置',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextField(
                        key: const ValueKey('settings-search'),
                        controller: _searchController,
                        onChanged: (value) => setState(() {
                          _query = value.trim().toLowerCase();
                        }),
                        style: TextStyle(
                          fontSize: AppMetrics.fontBody,
                          color: c.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: '查找设置',
                          hintStyle: TextStyle(color: c.textTertiary),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            size: AppMetrics.iconMd,
                            color: c.textTertiary,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 30,
                            minHeight: 0,
                          ),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除搜索',
                                  iconSize: AppMetrics.iconSm,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: Icon(
                                    Icons.close,
                                    color: c.textTertiary,
                                  ),
                                ),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppMetrics.controlRadius,
                            ),
                            borderSide: BorderSide(color: c.borderStrong),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppMetrics.controlRadius,
                            ),
                            borderSide: BorderSide(color: c.borderStrong),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppMetrics.controlRadius,
                            ),
                            borderSide: BorderSide(color: c.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                    children: [
                      for (final category in categories)
                        _CategoryButton(
                          category: category,
                          selected: _query.isEmpty && _selected == category,
                          onTap: () => setState(() {
                            _selected = category;
                            _searchController.clear();
                            _query = '';
                          }),
                        ),
                      if (categories.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '没有匹配的设置',
                            style: TextStyle(color: c.textTertiary),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppMetrics.paneGap),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_query.isNotEmpty) {
      final matches = SettingsCategory.values
          .where((category) => _categoryMatches(category, _query))
          .toList();
      return _SettingsScrollPage(
        title: '搜索结果',
        children: [
          for (final category in matches) ...[
            _SectionTitle(label: _categoryLabel(category)),
            _SettingsGroup(children: _categoryRows(context, category, _query)),
          ],
          if (matches.isEmpty) const _EmptySearchResult(),
        ],
      );
    }

    if (_selected == SettingsCategory.viewers) {
      return const _ViewerSettingsPage();
    }
    return _SettingsScrollPage(
      title: _categoryLabel(_selected),
      children: [
        _SettingsGroup(
          children: _categoryRows(context, _selected, ''),
        ),
      ],
    );
  }

  List<Widget> _categoryRows(
    BuildContext context,
    SettingsCategory category,
    String query,
  ) {
    final settings = context.watch<SettingsController>();
    final rows = <Widget>[];

    void add(String terms, Widget row) {
      if (_matches(query, terms)) rows.add(row);
    }

    switch (category) {
      case SettingsCategory.general:
        add(
          '新标签页 位置 当前目录 主文件夹 自定义 文件夹 navigation tab',
          _SettingsRow(
            key: const ValueKey('setting-new-tab-location'),
            title: '新标签页位置',
            description: '使用快捷键或菜单新建标签页时打开的位置',
            control: DropdownMenu<NewTabLocation>(
              key: const ValueKey('setting-new-tab-location-menu'),
              initialSelection: settings.newTabLocation,
              selectOnly: true,
              enableSearch: false,
              onSelected: (value) {
                if (value != null) settings.setNewTabLocation(value);
              },
              dropdownMenuEntries: const [
                DropdownMenuEntry(value: NewTabLocation.current, label: '当前目录'),
                DropdownMenuEntry(value: NewTabLocation.home, label: '主文件夹'),
                DropdownMenuEntry(value: NewTabLocation.custom, label: '自定义目录'),
              ],
            ),
          ),
        );
        if (settings.newTabLocation == NewTabLocation.custom) {
          add(
            '自定义目录 新标签页 选择文件夹 path folder',
            _SettingsRow(
              key: const ValueKey('setting-custom-new-tab-path'),
              title: '自定义目录',
              description: settings.customNewTabPath ?? '尚未选择文件夹',
              control: OutlinedButton.icon(
                onPressed: () => _pickCustomFolder(settings),
                icon: const Icon(Icons.folder_open),
                label: const Text('选择'),
              ),
            ),
          );
        }
        break;
      case SettingsCategory.appearance:
        add(
          '主题 跟随系统 亮色 暗色 appearance theme',
          _SettingsRow(
            key: const ValueKey('setting-theme'),
            title: '主题',
            description: '设置应用的明暗外观',
            control: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('系统'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('亮色'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('暗色'),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (values) {
                settings.setThemeMode(values.single);
              },
            ),
          ),
        );
        add(
          '默认视图 详细信息 列表 图标 平铺 内容 view mode',
          _SettingsRow(
            key: const ValueKey('setting-default-view-mode'),
            title: '默认视图',
            description: '用于新建面板；现有面板保持各自视图',
            control: DropdownMenu<PaneViewMode>(
              key: const ValueKey('setting-default-view-mode-menu'),
              initialSelection: settings.defaultViewMode,
              selectOnly: true,
              enableSearch: false,
              onSelected: (value) {
                if (value != null) settings.setDefaultViewMode(value);
              },
              dropdownMenuEntries: [
                for (final mode in _selectableViewModes)
                  DropdownMenuEntry(value: mode, label: _viewModeLabel(mode)),
              ],
            ),
          ),
        );
        add(
          '显示隐藏和系统文件 隐藏文件 system hidden',
          _SettingsSwitchRow(
            key: const ValueKey('setting-show-hidden-files'),
            title: '显示隐藏和系统文件',
            description: '切换后刷新所有面板和侧边栏',
            value: settings.showHiddenFiles,
            onChanged: widget.onShowHiddenFilesChanged,
          ),
        );
        add(
          '显示文件扩展名 后缀 extension',
          _SettingsSwitchRow(
            key: const ValueKey('setting-show-file-extensions'),
            title: '显示文件扩展名',
            description: '在文件名中显示 .txt、.pdf 等扩展名',
            value: settings.showFileExtensions,
            onChanged: widget.onShowFileExtensionsChanged,
          ),
        );
        add(
          '显示缩略图 图片 视频 PDF Office thumbnail',
          _SettingsSwitchRow(
            key: const ValueKey('setting-show-thumbnails'),
            title: '显示缩略图',
            description: '支持的文件优先显示内容缩略图',
            value: settings.showThumbnails,
            onChanged: widget.onShowThumbnailsChanged,
          ),
        );
        break;
      case SettingsCategory.fileOperations:
        add(
          '删除 回收站 确认 提示 delete recycle confirm',
          _SettingsSwitchRow(
            key: const ValueKey('setting-confirm-recycle-delete'),
            title: '移入回收站前确认',
            description: '永久删除和清空回收站始终需要确认',
            value: settings.confirmRecycleDelete,
            onChanged: settings.setConfirmRecycleDelete,
          ),
        );
        add(
          '清除缩略图缓存 cache thumbnail cleanup',
          _SettingsRow(
            key: const ValueKey('setting-clear-thumbnail-cache'),
            title: '缩略图缓存',
            description: '清除内存和磁盘中的缩略图数据',
            control: OutlinedButton.icon(
              onPressed: () {
                widget.onClearThumbnailCache();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('缩略图缓存已清除')));
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('清除'),
            ),
          ),
        );
        break;
      case SettingsCategory.viewers:
        add(
          '查看器 Viewer Quick View 扩展名 文件名 MIME 插件 关联',
          _SettingsRow(
            key: const ValueKey('setting-viewer-search-result'),
            title: '查看器关联',
            description: '管理扩展名、文件名和 MIME 的查看器候选顺序',
            control: OutlinedButton.icon(
              onPressed: () => setState(() {
                _selected = SettingsCategory.viewers;
                _searchController.clear();
                _query = '';
              }),
              icon: const Icon(Icons.extension),
              label: const Text('管理'),
            ),
          ),
        );
        break;
    }
    return rows;
  }

  void _pickCustomFolder(SettingsController settings) {
    try {
      final picker = widget.folderPicker;
      final path = picker != null
          ? picker(settings.customNewTabPath)
          : ShellFileOperation.pickFolder(
              initialPath: settings.customNewTabPath,
            );
      if (path != null) settings.setCustomNewTabPath(path);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法选择文件夹：$error')));
    }
  }

  bool _categoryMatches(SettingsCategory category, String query) {
    if (query.isEmpty) return true;
    return _matches(query, switch (category) {
      SettingsCategory.general =>
        '常规 新标签页 位置 当前目录 主文件夹 自定义 navigation tab folder',
      SettingsCategory.appearance =>
        '外观 浏览 主题 亮色 暗色 默认视图 隐藏文件 扩展名 缩略图 appearance view theme thumbnail',
      SettingsCategory.fileOperations =>
        '文件操作 删除 回收站 确认 缩略图缓存 file delete recycle cache',
      SettingsCategory.viewers => '查看器 viewer quick view 插件 关联 扩展名 文件名 MIME',
    });
  }

  bool _matches(String query, String terms) {
    if (query.isEmpty) return true;
    return terms.toLowerCase().contains(query);
  }
}

class _SettingsScrollPage extends StatefulWidget {
  const _SettingsScrollPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  State<_SettingsScrollPage> createState() => _SettingsScrollPageState();
}

class _SettingsScrollPageState extends State<_SettingsScrollPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
      ),
      child: Scrollbar(
        controller: _scrollController,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 32),
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...widget.children,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerSettingsPage extends StatelessWidget {
  const _ViewerSettingsPage();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '查看器',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '设置文件匹配规则和快速查看程序的优先顺序',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: AppMetrics.fontSmall,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                key: const ValueKey('viewer-settings-surface'),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
                ),
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
                ),
                child: const ViewerAssociationsView(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 左侧分类项：与侧边栏一致的 pill 选中态（accentSubtle 底、accent 文字）。
class _CategoryButton extends StatefulWidget {
  const _CategoryButton({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CategoryButton> createState() => _CategoryButtonState();
}

class _CategoryButtonState extends State<_CategoryButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.selected;
    final radius = BorderRadius.circular(AppMetrics.controlRadius);
    final color = selected
        ? c.accent
        : _hovering
        ? c.textPrimary
        : c.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          key: ValueKey('settings-category-${widget.category.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected
                  ? c.accentSubtle
                  : _hovering
                  ? c.surfaceHover
                  : Colors.transparent,
              borderRadius: radius,
            ),
            child: Row(
              children: [
                Icon(
                  _categoryIcon(widget.category),
                  size: AppMetrics.iconMd,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  _categoryLabel(widget.category),
                  style: TextStyle(
                    fontSize: AppMetrics.fontBody,
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
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

/// 一组设置行的外框：细描边圆角卡片，行间用分隔线。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
    required this.title,
    required this.description,
    required this.control,
  });

  final String title;
  final String description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: AppMetrics.fontBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: AppMetrics.fontSmall,
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 540) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 10), control],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 20),
              control,
            ],
          );
        },
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      title: title,
      description: description,
      control: Switch(value: value, onChanged: onChanged),
    );
  }
}

/// 搜索结果中的分组标题：与侧栏分区头同款小号加宽 tertiary 文字。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, left: 2, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.textTertiary,
          fontSize: AppMetrics.fontSmall,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          '没有匹配的设置',
          style: TextStyle(color: context.colors.textTertiary),
        ),
      ),
    );
  }
}

const _selectableViewModes = [
  PaneViewMode.details,
  PaneViewMode.list,
  PaneViewMode.extraLargeIcons,
  PaneViewMode.largeIcons,
  PaneViewMode.mediumIcons,
  PaneViewMode.smallIcons,
  PaneViewMode.tiles,
  PaneViewMode.content,
];

String _viewModeLabel(PaneViewMode mode) => switch (mode) {
  PaneViewMode.details => '详细信息',
  PaneViewMode.list => '列表',
  PaneViewMode.compact => '紧凑',
  PaneViewMode.extraLargeIcons => '超大图标',
  PaneViewMode.largeIcons => '大图标',
  PaneViewMode.mediumIcons => '中等图标',
  PaneViewMode.smallIcons => '小图标',
  PaneViewMode.tiles => '平铺',
  PaneViewMode.content => '内容',
};

String _categoryLabel(SettingsCategory category) => switch (category) {
  SettingsCategory.general => '常规',
  SettingsCategory.appearance => '外观与浏览',
  SettingsCategory.fileOperations => '文件操作',
  SettingsCategory.viewers => '查看器',
};

IconData _categoryIcon(SettingsCategory category) => switch (category) {
  SettingsCategory.general => Icons.tune,
  SettingsCategory.appearance => Icons.palette_outlined,
  SettingsCategory.fileOperations => Icons.folder_copy_outlined,
  SettingsCategory.viewers => Icons.extension_outlined,
};
