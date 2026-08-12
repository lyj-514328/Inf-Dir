import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/text_search_service.dart';
import '../utils/perf_log.dart';
import 'app_theme.dart';

enum _TextSearchRowKind { fileName, relativePath, match }

class TextSearchDialog extends StatefulWidget {
  final String rootPath;
  final TextSearchService searchService;
  final Widget? modeSelector;
  final ValueChanged<TextSearchMatch>? onResult;

  TextSearchDialog({
    super.key,
    required this.rootPath,
    TextSearchService? searchService,
    this.modeSelector,
    this.onResult,
  }) : searchService = searchService ?? TextSearchService();

  @override
  State<TextSearchDialog> createState() => _TextSearchDialogState();
}

class _TextSearchDialogState extends State<TextSearchDialog> {
  static const double _resultRowExtent = 26;

  late final TextEditingController _queryController;
  late final FocusNode _queryFocusNode;
  TextSearchPatternMode _patternMode = TextSearchPatternMode.keyword;
  bool _includeHidden = false;
  bool _caseSensitive = false;
  bool _followLinks = false;
  int _maxFiles = 200;
  int _maxMatchesPerFile = 500;
  List<TextSearchMatch> _results = <TextSearchMatch>[];
  final Map<String, List<TextSearchMatch>> _groupedResultsByPath =
      <String, List<TextSearchMatch>>{};
  String? _error;
  bool _searching = false;
  bool _hasSearched = false;
  int _searchRevision = 0;
  bool _resultUpdateScheduled = false;
  final Set<String> _collapsedPaths = <String>{};
  final Stopwatch _searchSw = Stopwatch();
  int _lastPerfResultCount = 0;
  int _lastSlowFrameLogAtMs = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _queryFocusNode = FocusNode();
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
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
    _resultUpdateScheduled = false;
    setState(() {
      _results = <TextSearchMatch>[];
      _groupedResultsByPath.clear();
      _collapsedPaths.clear();
      _error = null;
      _hasSearched = false;
      _searching = false;
    });
  }

  Future<void> _runSearch() async {
    final revision = ++_searchRevision;
    _searchSw
      ..reset()
      ..start();
    _lastPerfResultCount = 0;
    _resultUpdateScheduled = false;
    setState(() {
      _searching = true;
      _error = null;
      _results = <TextSearchMatch>[];
      _groupedResultsByPath.clear();
      _collapsedPaths.clear();
      _hasSearched = false;
    });
    try {
      final results = await widget.searchService.search(
        widget.rootPath,
        _queryController.text,
        options: _options,
        onMatch: (match) {
          if (!mounted || revision != _searchRevision) return;
          // ripgrep may produce a very dense stream. Keep the model current,
          // but repaint at most once per frame to preserve scroll smoothness.
          _results.add(match);
          _groupedResultsByPath
              .putIfAbsent(match.path, () => <TextSearchMatch>[])
              .add(match);
          if (_results.length - _lastPerfResultCount >= 500) {
            _lastPerfResultCount = _results.length;
            PerfLog.write(
              '[TextSearchDialog] streaming results=${_results.length} '
              'files=${_groupedResultsByPath.length} elapsedMs=${_searchSw.elapsedMilliseconds}',
            );
          }
          _scheduleResultUpdate(revision);
        },
      );
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _searching = false;
        _results = results;
        _rebuildGroupedResults();
        _hasSearched = true;
      });
      _searchSw.stop();
      PerfLog.write(
        '[TextSearchDialog] completed results=${_results.length} '
        'files=${_groupedResultsByPath.length} totalMs=${_searchSw.elapsedMilliseconds}',
      );
    } catch (error) {
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _searching = false;
        _error = error is TextSearchException ? error.message : '搜索失败：$error';
      });
    }
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted || (!_searching && _results.isEmpty)) return;
    for (final timing in timings) {
      final totalMicros = timing.totalSpan.inMicroseconds;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (totalMicros < 16000 || nowMs - _lastSlowFrameLogAtMs < 1000) {
        continue;
      }
      _lastSlowFrameLogAtMs = nowMs;
      PerfLog.write(
        '[TextSearchDialog] slowFrame totalMs=${(totalMicros / 1000).toStringAsFixed(1)} '
        'buildMs=${(timing.buildDuration.inMicroseconds / 1000).toStringAsFixed(1)} '
        'rasterMs=${(timing.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)} '
        'results=${_results.length} files=${_groupedResultsByPath.length} searching=$_searching',
      );
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

  void _rebuildGroupedResults() {
    _groupedResultsByPath.clear();
    for (final result in _results) {
      _groupedResultsByPath
          .putIfAbsent(result.path, () => <TextSearchMatch>[])
          .add(result);
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
              if (widget.modeSelector != null) ...[
                const SizedBox(height: 10),
                widget.modeSelector!,
              ],
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
              _modeAndLimitControls(c),
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
                    : ListView.builder(
                        itemExtent: _resultRowExtent,
                        itemCount: _visibleRowCount(groupedResults),
                        itemBuilder: (context, index) {
                          final row = _rowAt(groupedResults, index);
                          if (row.kind == _TextSearchRowKind.fileName) {
                            final group = row.group!;
                            final collapsed = _collapsedPaths.contains(
                              group.key,
                            );
                            return InkWell(
                              key: ValueKey('file:${group.key}'),
                              onTap: () {
                                setState(() {
                                  if (collapsed) {
                                    _collapsedPaths.remove(group.key);
                                  } else {
                                    _collapsedPaths.add(group.key);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.description_outlined,
                                      size: AppMetrics.iconSm,
                                      color: c.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${p.basename(group.key)} (${group.value.length})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: AppMetrics.fontBody,
                                          fontWeight: FontWeight.w600,
                                          color: c.accent,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      collapsed
                                          ? Icons.chevron_right
                                          : Icons.expand_more,
                                      size: AppMetrics.iconSm,
                                      color: c.textTertiary,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          if (row.kind == _TextSearchRowKind.relativePath) {
                            final relativePath = p.relative(
                              row.group!.key,
                              from: widget.rootPath,
                            );
                            return Padding(
                              key: ValueKey('path:${row.group!.key}'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.folder_open_outlined,
                                    size: AppMetrics.iconSm,
                                    color: c.textTertiary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      relativePath,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: AppMetrics.fontBody,
                                        color: c.textTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final result = row.match!;
                          return InkWell(
                            key: ValueKey('${result.path}:${result.line}'),
                            onTap: () {
                              final onResult = widget.onResult;
                              if (onResult != null) {
                                onResult(result);
                              } else {
                                Navigator.of(context).pop(result);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8, right: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      '${result.line}:',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: AppMetrics.fontBody,
                                        color: c.success,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text.rich(
                                      _highlightedText(result, c),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
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

  Widget _modeAndLimitControls(AppColors c) {
    Widget patternModeControl() => SegmentedButton<TextSearchPatternMode>(
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
    );

    Widget maxFilesControl() => _limitDropdown(
      c,
      label: '最大匹配文件数',
      value: _maxFiles,
      values: const [20, 50, 100, 200, 500, 1000, 2000],
      onChanged: (value) => _maxFiles = value,
    );

    Widget maxMatchesControl() => _limitDropdown(
      c,
      label: '文件内最大匹配行数',
      value: _maxMatchesPerFile,
      values: const [20, 50, 100, 200, 500, 1000, 2000],
      onChanged: (value) => _maxMatchesPerFile = value,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              patternModeControl(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: maxFilesControl()),
                  const SizedBox(width: 8),
                  Expanded(child: maxMatchesControl()),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 5, child: patternModeControl()),
            const SizedBox(width: 8),
            Expanded(flex: 4, child: maxFilesControl()),
            const SizedBox(width: 8),
            Expanded(flex: 4, child: maxMatchesControl()),
          ],
        );
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

  List<MapEntry<String, List<TextSearchMatch>>> get _groupedResults {
    return _groupedResultsByPath.entries.toList(growable: false);
  }

  int _visibleRowCount(List<MapEntry<String, List<TextSearchMatch>>> groups) {
    var count = 0;
    for (final group in groups) {
      count++;
      if (!_collapsedPaths.contains(group.key)) {
        count += 1 + group.value.length;
      }
    }
    return count;
  }

  ({
    _TextSearchRowKind kind,
    MapEntry<String, List<TextSearchMatch>>? group,
    TextSearchMatch? match,
  })
  _rowAt(List<MapEntry<String, List<TextSearchMatch>>> groups, int index) {
    var remaining = index;
    for (final group in groups) {
      if (remaining == 0) {
        return (kind: _TextSearchRowKind.fileName, group: group, match: null);
      }
      remaining--;
      if (_collapsedPaths.contains(group.key)) continue;
      if (remaining == 0) {
        return (
          kind: _TextSearchRowKind.relativePath,
          group: group,
          match: null,
        );
      }
      remaining--;
      if (remaining < group.value.length) {
        return (
          kind: _TextSearchRowKind.match,
          group: null,
          match: group.value[remaining],
        );
      }
      remaining -= group.value.length;
    }
    throw RangeError.index(index, groups, 'index');
  }

  TextSpan _highlightedText(TextSearchMatch result, AppColors c) {
    if (result.ranges.isEmpty) {
      return TextSpan(
        text: result.text,
        style: TextStyle(fontSize: AppMetrics.fontBody, color: c.textSecondary),
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
              fontSize: AppMetrics.fontBody,
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
              fontSize: AppMetrics.fontBody,
              color: c.danger,
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
            fontSize: AppMetrics.fontBody,
            color: c.textSecondary,
          ),
        ),
      );
    }
    return TextSpan(children: spans);
  }
}
