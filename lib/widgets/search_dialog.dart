import 'package:flutter/material.dart';

import '../services/file_search_service.dart';
import '../services/text_search_service.dart';
import 'file_search_dialog.dart';
import 'text_search_dialog.dart';

enum SearchMode { files, text }

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

  const SearchDialog({
    super.key,
    required this.rootPath,
    this.initialMode = SearchMode.files,
    this.fileSearchService,
    this.textSearchService,
  });

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  late SearchMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
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
        rootPath: widget.rootPath,
        searchService: widget.fileSearchService,
        modeSelector: selector,
        onResult: (result) => Navigator.of(context).pop(
          SearchDialogResult(
            path: result.path,
            isDirectory: result.isDirectory,
          ),
        ),
      ),
      SearchMode.text => TextSearchDialog(
        rootPath: widget.rootPath,
        searchService: widget.textSearchService,
        modeSelector: selector,
        onResult: (result) => Navigator.of(
          context,
        ).pop(SearchDialogResult(path: result.path, isDirectory: false)),
      ),
    };
  }
}
