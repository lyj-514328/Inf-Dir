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

    return ColoredBox(
      key: const ValueKey('settings-view'),
      color: c.windowBg,
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surfaceSubtle,
                border: Border(right: BorderSide(color: c.border)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                    child: TextField(
                      key: const ValueKey('settings-search'),
                      controller: _searchController,
                      onChanged: (value) => setState(() {
                        _query = value.trim().toLowerCase();
                      }),
                      decoration: InputDecoration(
                        hintText: '搜索设置',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除搜索',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      primary: false,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
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
          ),
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
            ..._categoryRows(context, category, _query),
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
      children: _categoryRows(context, _selected, ''),
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
            control: _ControlSurface(
              child: DropdownButton<NewTabLocation>(
                value: settings.newTabLocation,
                underline: const SizedBox.shrink(),
                isDense: true,
                onChanged: (value) {
                  if (value != null) settings.setNewTabLocation(value);
                },
                items: const [
                  DropdownMenuItem(
                    value: NewTabLocation.current,
                    child: Text('当前目录'),
                  ),
                  DropdownMenuItem(
                    value: NewTabLocation.home,
                    child: Text('主文件夹'),
                  ),
                  DropdownMenuItem(
                    value: NewTabLocation.custom,
                    child: Text('自定义目录'),
                  ),
                ],
              ),
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
            control: _ControlSurface(
              child: DropdownButton<PaneViewMode>(
                value: settings.defaultViewMode,
                underline: const SizedBox.shrink(),
                isDense: true,
                onChanged: (value) {
                  if (value != null) settings.setDefaultViewMode(value);
                },
                items: [
                  for (final mode in _selectableViewModes)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(_viewModeLabel(mode)),
                    ),
                ],
              ),
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
    return Scrollbar(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 22),
          ...widget.children,
        ],
      ),
    );
  }
}

class _ViewerSettingsPage extends StatelessWidget {
  const _ViewerSettingsPage();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('查看器', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('管理快速查看使用的候选查看器及顺序', style: TextStyle(color: c.textSecondary)),
          const SizedBox(height: 16),
          const Expanded(child: ViewerAssociationsView()),
        ],
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        key: ValueKey('settings-category-${category.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? c.accentSubtle : Colors.transparent,
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          ),
          child: Row(
            children: [
              Icon(
                _categoryIcon(category),
                size: AppMetrics.iconMd,
                color: selected ? c.accent : c.textSecondary,
              ),
              const SizedBox(width: 9),
              Text(
                _categoryLabel(category),
                style: TextStyle(
                  color: selected ? c.textPrimary : c.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
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
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: AppMetrics.fontBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: AppMetrics.fontSmall,
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 10), control],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 20),
              Flexible(child: control),
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

class _ControlSurface extends StatelessWidget {
  const _ControlSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 34, minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: AppMetrics.fontSmall,
          fontWeight: FontWeight.w600,
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
