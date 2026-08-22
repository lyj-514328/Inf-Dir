import 'package:flutter/material.dart';

import '../services/file_search_service.dart';
import '../services/text_search_service.dart';
import 'file_search_dialog.dart';
import 'text_search_dialog.dart';

enum SearchMode { files, text }

typedef SearchFolderPicker = String? Function(String? initialPath);

class SearchDialogResult {
  final String path;
  final bool isDirectory;

  const SearchDialogResult({required this.path, required this.isDirectory});
}

class SearchDialog extends StatefulWidget {
  final String rootPath;
  final SearchMode initialMode;
  final FileSearchService? fileSearchService;
  final TextSearchService? textSearchService;
  final String? initialQuery;
  final String? initialRootPath;
  final ValueChanged<String>? onQueryChanged;
  final ValueChanged<String>? onRootChanged;
  final SearchFolderPicker? folderPicker;

  const SearchDialog({
    super.key,
    required this.rootPath,
    this.initialMode = SearchMode.files,
    this.fileSearchService,
    this.textSearchService,
    this.initialQuery,
    this.initialRootPath,
    this.onQueryChanged,
    this.onRootChanged,
    this.folderPicker,
  });

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  late SearchMode _mode;
  late String _rootPath;
  late String _query;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _rootPath = widget.initialRootPath ?? widget.rootPath;
    _query = widget.initialQuery ?? '';
  }

  void _pickRoot() {
    final picked = widget.folderPicker?.call(_rootPath);
    if (picked == null || !mounted) return;
    setState(() => _rootPath = picked);
    widget.onRootChanged?.call(picked);
  }

  void _setRoot(String path) {
    final value = path.trim();
    if (value.isEmpty || !mounted) return;
    setState(() => _rootPath = value);
    widget.onRootChanged?.call(value);
  }

  void _setQuery(String query) {
    if (_query != query) setState(() => _query = query);
    widget.onQueryChanged?.call(query);
  }

  @override
  Widget build(BuildContext context) {
    final selector = SegmentedButton<SearchMode>(
      segments: const [
        ButtonSegment(
          value: SearchMode.files,
          icon: Icon(Icons.folder_open_outlined),
          label: Text('文件'),
        ),
        ButtonSegment(
          value: SearchMode.text,
          icon: Icon(Icons.find_in_page_outlined),
          label: Text('文本'),
        ),
      ],
      selected: {_mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        setState(() => _mode = selection.first);
      },
    );

    return switch (_mode) {
      SearchMode.files => FileSearchDialog(
        rootPath: _rootPath,
        searchService: widget.fileSearchService,
        modeSelector: selector,
        initialQuery: _query,
        onQueryChanged: _setQuery,
        onRootChanged: _setRoot,
        onPickRoot: _pickRoot,
        onResult: (result) => Navigator.of(context).pop(
          SearchDialogResult(
            path: result.path,
            isDirectory: result.isDirectory,
          ),
        ),
      ),
      SearchMode.text => TextSearchDialog(
        rootPath: _rootPath,
        searchService: widget.textSearchService,
        modeSelector: selector,
        initialQuery: _query,
        onQueryChanged: _setQuery,
        onRootChanged: _setRoot,
        onPickRoot: _pickRoot,
        onResult: (result) => Navigator.of(
          context,
        ).pop(SearchDialogResult(path: result.path, isDirectory: false)),
      ),
    };
  }
}
