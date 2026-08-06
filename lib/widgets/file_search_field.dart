import 'package:flutter/material.dart';

import 'app_theme.dart';

void _ignoreSearchChange(String _) {}

/// Search slot in the pane location row. The query is applied to the current
/// directory by the owning [PaneController].
class FileSearchField extends StatefulWidget {
  final String query;
  final ValueChanged<String> onChanged;

  const FileSearchField({
    super.key,
    this.query = '',
    this.onChanged = _ignoreSearchChange,
  });

  @override
  State<FileSearchField> createState() => _FileSearchFieldState();
}

class _FileSearchFieldState extends State<FileSearchField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.query);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant FileSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query &&
        _textController.text != widget.query) {
      _textController.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: '搜索当前文件夹',
      child: Container(
        height: AppMetrics.addressBarHeight,
        padding: const EdgeInsets.only(left: 7, right: 3),
        decoration: BoxDecoration(
          border: Border.all(
            color: _focusNode.hasFocus ? c.accent : c.borderStrong,
          ),
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          color: c.surface,
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: AppMetrics.iconSm, color: c.textSecondary),
            const SizedBox(width: 5),
            Expanded(
              child: Focus(
                onFocusChange: (_) => setState(() {}),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onChanged,
                  style: TextStyle(
                    fontSize: AppMetrics.fontBody,
                    color: c.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '搜索当前文件夹',
                    hintStyle: TextStyle(
                      fontSize: AppMetrics.fontBody,
                      color: c.textTertiary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            if (_textController.text.isNotEmpty)
              Tooltip(
                message: '清除搜索',
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
                  onTap: () {
                    _textController.clear();
                    widget.onChanged('');
                    _focusNode.requestFocus();
                    setState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.close,
                      size: AppMetrics.iconSm,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
