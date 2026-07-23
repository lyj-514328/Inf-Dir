import 'package:flutter/material.dart';

class AddressBar extends StatefulWidget {
  final String currentPath;
  final ValueChanged<String> onSubmit;

  const AddressBar({
    super.key,
    required this.currentPath,
    required this.onSubmit,
  });

  @override
  State<AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<AddressBar> {
  late TextEditingController _controller;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPath);
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
          Icon(Icons.folder_open, size: 14, color: Colors.amber.shade700),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _controller,
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
