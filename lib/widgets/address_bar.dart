import 'package:flutter/material.dart';
import '../services/icon_service.dart';
import '../services/file_service.dart';
import 'app_theme.dart';

class AddressBar extends StatefulWidget {
  final String currentPath;
  final String iconPath;
  final ValueChanged<String> onSubmit;

  const AddressBar({
    super.key,
    required this.currentPath,
    required this.iconPath,
    required this.onSubmit,
  });

  @override
  State<AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<AddressBar> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPath);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _editing) {
      // Lost focus without submitting → revert to current path
      _editing = false;
      _controller.text = widget.currentPath;
    }
    // 聚焦态变化 → 仅更新边框样式
    setState(() {});
  }

  @override
  void didUpdateWidget(AddressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && widget.currentPath != oldWidget.currentPath) {
      _controller.text = widget.currentPath;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSubmit(text);
    }
    setState(() => _editing = false);
  }

  Widget _buildIcon() {
    final c = context.colors;
    if (FileService.isHomePath(widget.iconPath)) {
      return Icon(Icons.home, size: AppMetrics.iconSm, color: c.textSecondary);
    }
    final bytes = IconService.getFileIconPng(widget.iconPath, true, 16);
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: AppMetrics.iconSm,
        height: AppMetrics.iconSm,
        gaplessPlayback: true,
      );
    }
    return Icon(
      Icons.folder_open,
      size: AppMetrics.iconSm,
      color: c.iconFolder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final focused = _focusNode.hasFocus;
    return Container(
      height: AppMetrics.addressBarHeight,
      decoration: BoxDecoration(
        border: Border.all(
          color: focused ? c.accent : c.borderStrong,
          width: focused ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        color: c.surface,
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          _buildIcon(),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: TextStyle(
                fontSize: AppMetrics.fontBody,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                hintStyle: TextStyle(
                  fontSize: AppMetrics.fontBody,
                  color: c.textTertiary,
                ),
              ),
              onSubmitted: (_) => _submit(),
              onTap: () => setState(() => _editing = true),
            ),
          ),
        ],
      ),
    );
  }
}
