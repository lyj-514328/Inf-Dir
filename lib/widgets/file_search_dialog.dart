import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../services/file_search_service.dart';
import 'app_theme.dart';

class FileSearchDialog extends StatefulWidget {
  final String rootPath;
  final FileSearchService searchService;
  final Widget? modeSelector;
  final ValueChanged<FileSearchResult>? onResult;

  FileSearchDialog({
    super.key,
    required this.rootPath,
    FileSearchService? searchService,
    this.modeSelector,
    this.onResult,
  }) : searchService = searchService ?? FileSearchService();

  @override
  State<FileSearchDialog> createState() => _FileSearchDialogState();
}

class _FileSearchDialogState extends State<FileSearchDialog> {
  static const double _resultRowExtent = 44;

  late final TextEditingController _queryController;
  late final FocusNode _queryFocusNode;
  FileSearchPatternMode _patternMode = FileSearchPatternMode.keyword;
  FileSearchEntryKind _entryKind = FileSearchEntryKind.all;
  bool _includeHidden = false;
  bool _caseSensitive = false;
  bool _followLinks = false;
  int _maxResults = 500;
  List<FileSearchResult> _results = <FileSearchResult>[];
  String? _error;
  bool _searching = false;
  bool _hasSearched = false;
  int _searchRevision = 0;
  bool _resultUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _queryFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  FileSearchOptions get _options => FileSearchOptions(
    patternMode: _patternMode,
    entryKind: _entryKind,
    includeHidden: _includeHidden,
    caseSensitive: _caseSensitive,
    followLinks: _followLinks,
    maxResults: _maxResults,
  );

  void _markOptionsChanged() {
    _invalidateSearch();
  }

  void _invalidateSearch() {
    _searchRevision++;
    _resultUpdateScheduled = false;
    setState(() {
      _results = <FileSearchResult>[];
      _error = null;
      _hasSearched = false;
      _searching = false;
    });
  }

  Future<void> _runSearch() async {
    final revision = ++_searchRevision;
    _resultUpdateScheduled = false;
    setState(() {
      _searching = true;
      _error = null;
      _results = <FileSearchResult>[];
      _hasSearched = false;
    });
    try {
      final results = await widget.searchService.search(
        widget.rootPath,
        _queryController.text,
        options: _options,
        onResult: (result) {
          if (!mounted || revision != _searchRevision) return;
          // fd can emit hundreds of results per frame. Coalesce notifications
          // so a burst only rebuilds the dialog once per Flutter frame.
          _results.add(result);
          _scheduleResultUpdate(revision);
        },
      );
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _searching = false;
        _results = results;
        _hasSearched = true;
      });
    } catch (error) {
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _searching = false;
        _error = error is FileSearchException ? error.message : '搜索失败：$error';
      });
    }
  }

  void _scheduleResultUpdate(int revision) {
    if (_resultUpdateScheduled) return;
    _resultUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resultUpdateScheduled = false;
      if (!mounted || revision != _searchRevision) return;
      setState(() {});
    });
  }

  void _openResult(FileSearchResult result) {
    final onResult = widget.onResult;
    if (onResult != null) {
      onResult(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  String get _rootLabel {
    final label = p.basename(widget.rootPath);
    return label.isEmpty ? widget.rootPath : label;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final merged = widget.modeSelector != null;
    final dialogWidth = (size.width - 32)
        .clamp(merged ? 380.0 : 360.0, merged ? 760.0 : 680.0)
        .toDouble();
    final dialogHeight = (size.height - 32)
        .clamp(merged ? 440.0 : 420.0, merged ? 680.0 : 640.0)
        .toDouble();

    return Dialog(
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.search, size: AppMetrics.iconMd, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '搜索文件',
                          style: TextStyle(
                            fontSize: AppMetrics.fontTitle,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          _rootLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppMetrics.fontCaption,
                            color: c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: '关闭',
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      iconSize: AppMetrics.iconMd,
                      color: c.textSecondary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              if (widget.modeSelector != null) ...[
                const SizedBox(height: 10),
                widget.modeSelector!,
              ],
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('file-search-query'),
                controller: _queryController,
                focusNode: _queryFocusNode,
                autofocus: true,
                onSubmitted: (_) => _runSearch(),
                style: TextStyle(
                  fontSize: AppMetrics.fontBody,
                  color: c.textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: '搜索内容',
                  hintText: '输入文件名',
                  prefixIcon: Icon(Icons.search, color: c.textTertiary),
                  suffixIcon: _queryController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _queryController.clear();
                            _invalidateSearch();
                            _queryFocusNode.requestFocus();
                          },
                          icon: const Icon(Icons.close),
                          tooltip: '清除',
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
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
                onChanged: (_) => _invalidateSearch(),
              ),
              const SizedBox(height: 12),
              SegmentedButton<FileSearchPatternMode>(
                segments: const [
                  ButtonSegment(
                    value: FileSearchPatternMode.keyword,
                    icon: Icon(Icons.text_fields),
                    label: Text('关键字'),
                  ),
                  ButtonSegment(
                    value: FileSearchPatternMode.glob,
                    icon: Icon(Icons.auto_awesome_mosaic_outlined),
                    label: Text('Glob'),
                  ),
                  ButtonSegment(
                    value: FileSearchPatternMode.regex,
                    icon: Icon(Icons.code),
                    label: Text('正则'),
                  ),
                ],
                selected: {_patternMode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _patternMode = selection.first);
                  _markOptionsChanged();
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _entryKindDropdown()),
                  const SizedBox(width: 10),
                  Expanded(child: _maxResultsDropdown()),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _optionChip(
                    label: '隐藏项目',
                    icon: Icons.visibility_outlined,
                    selected: _includeHidden,
                    onSelected: (value) {
                      setState(() => _includeHidden = value);
                      _markOptionsChanged();
                    },
                  ),
                  _optionChip(
                    label: '区分大小写',
                    icon: Symbols.match_case,
                    selected: _caseSensitive,
                    onSelected: (value) {
                      setState(() => _caseSensitive = value);
                      _markOptionsChanged();
                    },
                  ),
                  _optionChip(
                    label: '跟随链接',
                    icon: Icons.link,
                    selected: _followLinks,
                    onSelected: (value) {
                      setState(() => _followLinks = value);
                      _markOptionsChanged();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_searching) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.danger,
                    ),
                  ),
                ),
              if (!_searching && _error == null && !_hasSearched)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '输入条件后开始搜索',
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              if (!_searching &&
                  _error == null &&
                  _hasSearched &&
                  _results.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '没有找到结果',
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              if (_results.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    '找到 ${_results.length} 个结果',
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              Expanded(
                child: _results.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        itemExtent: _resultRowExtent,
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: c.border),
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              minTileHeight: _resultRowExtent,
                              minVerticalPadding: 0,
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              leading: Icon(
                                result.isDirectory
                                    ? Icons.folder_outlined
                                    : Icons.insert_drive_file_outlined,
                                size: AppMetrics.iconMd,
                                color: result.isDirectory
                                    ? c.iconFolder
                                    : c.iconFile,
                              ),
                              title: Text(
                                p.basename(result.path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppMetrics.fontBody,
                                  color: c.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                result.path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppMetrics.fontCaption,
                                  color: c.textTertiary,
                                ),
                              ),
                              onTap: () => _openResult(result),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _searching ? null : _runSearch,
                    icon: const Icon(Icons.search, size: AppMetrics.iconSm),
                    label: const Text('搜索'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryKindDropdown() {
    return DropdownMenu<FileSearchEntryKind>(
      initialSelection: _entryKind,
      label: const Text('范围'),
      selectOnly: true,
      enableSearch: false,
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: const [
        DropdownMenuEntry(value: FileSearchEntryKind.all, label: '文件和文件夹'),
        DropdownMenuEntry(value: FileSearchEntryKind.files, label: '仅文件'),
        DropdownMenuEntry(
          value: FileSearchEntryKind.directories,
          label: '仅文件夹',
        ),
      ],
      onSelected: (value) {
        if (value == null) return;
        setState(() => _entryKind = value);
        _markOptionsChanged();
      },
    );
  }

  Widget _maxResultsDropdown() {
    return DropdownMenu<int>(
      initialSelection: _maxResults,
      label: const Text('最多结果'),
      selectOnly: true,
      enableSearch: false,
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: const [
        DropdownMenuEntry(value: 200, label: '200'),
        DropdownMenuEntry(value: 500, label: '500'),
        DropdownMenuEntry(value: 1000, label: '1000'),
        DropdownMenuEntry(value: 2000, label: '2000'),
      ],
      onSelected: (value) {
        if (value == null) return;
        setState(() => _maxResults = value);
        _markOptionsChanged();
      },
    );
  }

  Widget _optionChip({
    required String label,
    required IconData icon,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      avatar: Icon(icon, size: AppMetrics.iconSm),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }
}
