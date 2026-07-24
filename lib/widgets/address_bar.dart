import 'package:flutter/material.dart';
import '../services/icon_service.dart';

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
      setState(() {
        _editing = false;
        _controller.text = widget.currentPath;
      });
    }
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
    final bytes = IconService.getFileIconPng(widget.iconPath, true, 16);
    if (bytes != null) {
      return Image.memory(bytes, width: 14, height: 14, gaplessPlayback: true);
    }
    return Icon(Icons.folder_open, size: 14, color: Colors.amber.shade700);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFB0B0B0)),
        borderRadius: BorderRadius.circular(2),
        color: Colors.white,
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
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
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
