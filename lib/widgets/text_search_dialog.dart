import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/text_search_service.dart';
import 'app_theme.dart';

class TextSearchDialog extends StatefulWidget {
  final String rootPath;
  final TextSearchService searchService;

  TextSearchDialog({
    super.key,
    required this.rootPath,
    TextSearchService? searchService,
  }) : searchService = searchService ?? TextSearchService();

  @override
  State<TextSearchDialog> createState() => _TextSearchDialogState();
}

class _TextSearchDialogState extends State<TextSearchDialog> {
  late final TextEditingController _queryController;
  late final FocusNode _queryFocusNode;
  TextSearchPatternMode _patternMode = TextSearchPatternMode.keyword;
  bool _includeHidden = false;
  bool _caseSensitive = false;
  bool _followLinks = false;
  int _maxFiles = 200;
  int _maxMatchesPerFile = 500;
  List<TextSearchMatch> _results = <TextSearchMatch>[];
  String? _error;
  bool _searching = false;
  bool _hasSearched = false;
  int _searchRevision = 0;

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

  TextSearchOptions get _options => TextSearchOptions(
    patternMode: _patternMode,
    includeHidden: _includeHidden,
    caseSensitive: _caseSensitive,
    followLinks: _followLinks,
    maxFiles: _maxFiles,
    maxMatchesPerFile: _maxMatchesPerFile,
  );

  void _invalidateSearch() {
    _searchRevision++;
    setState(() {
      _results = <TextSearchMatch>[];
      _error = null;
      _hasSearched = false;
      _searching = false;
    });
  }

  Future<void> _runSearch() async {
    final revision = ++_searchRevision;
    setState(() {
      _searching = true;
      _error = null;
      _results = <TextSearchMatch>[];
      _hasSearched = false;
    });
    try {
      final results = await widget.searchService.search(
        widget.rootPath,
        _queryController.text,
        options: _options,
        onMatch: (match) {
          if (!mounted || revision != _searchRevision) return;
          setState(() => _results.add(match));
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
        _error = error is TextSearchException ? error.message : '搜索失败：$error';
      });
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
    final dialogWidth = (size.width - 32).clamp(380.0, 760.0).toDouble();
    final dialogHeight = (size.height - 32).clamp(440.0, 680.0).toDouble();
    final groupedResults = _groupedResults;

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
                  Icon(Icons.find_in_page_outlined, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '搜索文本',
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
                      color: c.textSecondary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
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
                  hintText: '输入要匹配的文本',
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
              SegmentedButton<TextSearchPatternMode>(
                segments: const [
                  ButtonSegment(
                    value: TextSearchPatternMode.keyword,
                    icon: Icon(Icons.text_fields),
                    label: Text('关键词'),
                  ),
                  ButtonSegment(
                    value: TextSearchPatternMode.regex,
                    icon: Icon(Icons.code),
                    label: Text('正则'),
                  ),
                ],
                selected: {_patternMode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _patternMode = selection.first);
                  _invalidateSearch();
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _limitDropdown(
                      c,
                      label: '最大匹配文件数',
                      value: _maxFiles,
                      values: const [20, 50, 100, 200, 500, 1000, 2000],
                      onChanged: (value) => _maxFiles = value,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _limitDropdown(
                      c,
                      label: '文件内最大匹配行数',
                      value: _maxMatchesPerFile,
                      values: const [20, 50, 100, 200, 500, 1000, 2000],
                      onChanged: (value) => _maxMatchesPerFile = value,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _optionChip(
                    label: '包含隐藏文件',
                    icon: Icons.visibility_outlined,
                    selected: _includeHidden,
                    onSelected: (value) {
                      setState(() => _includeHidden = value);
                      _invalidateSearch();
                    },
                  ),
                  _optionChip(
                    label: '区分大小写',
                    icon: Icons.text_format,
                    selected: _caseSensitive,
                    onSelected: (value) {
                      setState(() => _caseSensitive = value);
                      _invalidateSearch();
                    },
                  ),
                  _optionChip(
                    label: '跟随链接',
                    icon: Icons.link,
                    selected: _followLinks,
                    onSelected: (value) {
                      setState(() => _followLinks = value);
                      _invalidateSearch();
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
                    '没有找到匹配内容',
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
                    '找到 ${groupedResults.length} 个文件，${_results.length} 个匹配行',
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              Expanded(
                child: _results.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.separated(
                        itemCount: groupedResults.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: c.border),
                        itemBuilder: (context, index) {
                          final group = groupedResults[index];
                          return ExpansionTile(
                            key: PageStorageKey(group.key),
                            initiallyExpanded: true,
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            leading: Icon(
                              Icons.description_outlined,
                              size: AppMetrics.iconMd,
                              color: c.iconFile,
                            ),
                            title: Text(
                              '${p.basename(group.key)} (${group.value.length})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppMetrics.fontBody,
                                color: c.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              group.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppMetrics.fontCaption,
                                color: c.textTertiary,
                              ),
                            ),
                            children: [
                              for (final result in group.value)
                                ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  contentPadding: const EdgeInsets.only(
                                    left: 44,
                                    right: 4,
                                  ),
                                  leading: SizedBox(
                                    width: 52,
                                    child: Text(
                                      '${result.line}:${result.column}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: AppMetrics.fontCaption,
                                        color: c.textTertiary,
                                      ),
                                    ),
                                  ),
                                  title: Text.rich(
                                    _highlightedText(result, c),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () =>
                                      Navigator.of(context).pop(result),
                                ),
                            ],
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

  Widget _limitDropdown(
    AppColors c, {
    required String label,
    required int value,
    required List<int> values,
    required ValueChanged<int> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          borderSide: BorderSide(color: c.border),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            for (final item in values)
              DropdownMenuItem(value: item, child: Text(item.toString())),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => onChanged(value));
            _invalidateSearch();
          },
        ),
      ),
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

  List<MapEntry<String, List<TextSearchMatch>>> get _groupedResults {
    final grouped = <String, List<TextSearchMatch>>{};
    for (final result in _results) {
      grouped.putIfAbsent(result.path, () => <TextSearchMatch>[]).add(result);
    }
    return grouped.entries.toList();
  }

  TextSpan _highlightedText(TextSearchMatch result, AppColors c) {
    if (result.ranges.isEmpty) {
      return TextSpan(
        text: result.text,
        style: TextStyle(
          fontSize: AppMetrics.fontCaption,
          color: c.textSecondary,
        ),
      );
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    final ranges = [...result.ranges]
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final range in ranges) {
      final start = range.start.clamp(0, result.text.length).toInt();
      final end = range.end.clamp(start, result.text.length).toInt();
      if (start > cursor) {
        spans.add(
          TextSpan(
            text: result.text.substring(cursor, start),
            style: TextStyle(
              fontSize: AppMetrics.fontCaption,
              color: c.textSecondary,
            ),
          ),
        );
      }
      if (end > start) {
        spans.add(
          TextSpan(
            text: result.text.substring(start, end),
            style: TextStyle(
              fontSize: AppMetrics.fontCaption,
              color: c.textPrimary,
              backgroundColor: c.accentSubtle,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        cursor = end;
      }
    }
    if (cursor < result.text.length) {
      spans.add(
        TextSpan(
          text: result.text.substring(cursor),
          style: TextStyle(
            fontSize: AppMetrics.fontCaption,
            color: c.textSecondary,
          ),
        ),
      );
    }
    return TextSpan(children: spans);
  }
}
