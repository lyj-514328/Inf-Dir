import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../services/icon_service.dart';
import '../services/file_service.dart';
import 'app_theme.dart';
import 'home_icon.dart';

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
  final ScrollController _scrollController = ScrollController();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPath);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    _scrollBreadcrumbToEnd();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _editing) {
      // Lost focus without submitting → revert to breadcrumb
      _editing = false;
      _controller.text = widget.currentPath;
      _scrollBreadcrumbToEnd();
    }
    // 聚焦态变化 → 仅更新边框样式
    setState(() {});
  }

  /// 面包屑布局完成后滚动到最右（当前目录）。
  void _scrollBreadcrumbToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editing || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) _scrollController.jumpTo(max);
    });
  }

  @override
  void didUpdateWidget(AddressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && widget.currentPath != oldWidget.currentPath) {
      _controller.text = widget.currentPath;
      _scrollBreadcrumbToEnd();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSubmit(text);
    }
    setState(() => _editing = false);
    _focusNode.unfocus();
    _scrollBreadcrumbToEnd();
  }

  void _startEditing() {
    // TextField 带 autofocus，挂载后自动聚焦
    setState(() => _editing = true);
  }

  void _cancelEditing() {
    _controller.text = widget.currentPath;
    setState(() => _editing = false);
    _focusNode.unfocus();
    _scrollBreadcrumbToEnd();
  }

  Widget _buildIcon() {
    final c = context.colors;
    if (FileService.isHomePath(widget.iconPath)) {
      return const HomeIcon(size: AppMetrics.iconSm);
    }
    final sourceSize = (AppMetrics.iconSm * View.of(context).devicePixelRatio)
        .ceil();
    final bytes = IconService.getFileIconPng(widget.iconPath, true, sourceSize);
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

  /// 将真实路径解析为面包屑段（驱动器根 + 各级目录）。
  /// 虚拟路径（主页 / shell CLSID）不可解析，返回 null。
  List<({String label, String path})>? _buildSegments() {
    final path = widget.iconPath;
    if (FileService.isHomePath(path) || FileService.isSpecialPath(path)) {
      return null;
    }
    final segments = <({String label, String path})>[];
    final String root;
    final List<String> parts;
    if (path.startsWith(r'\\')) {
      // UNC：\\server\share\dir\...
      parts = path
          .substring(2)
          .split(RegExp(r'[\\/]+'))
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length < 2) return null;
      root = '\\\\${parts[0]}\\${parts[1]}';
      parts.removeRange(0, 2);
    } else {
      if (path.length < 2 || path[1] != ':') return null;
      root = '${path.substring(0, 2)}\\';
      parts = path
          .substring(2)
          .split(RegExp(r'[\\/]+'))
          .where((s) => s.isNotEmpty)
          .toList();
    }
    segments.add((label: root, path: root));
    var current = root;
    for (final part in parts) {
      current = current.endsWith('\\') ? '$current$part' : '$current\\$part';
      segments.add((label: part, path: current));
    }
    return segments;
  }

  Widget _buildBreadcrumb() {
    final c = context.colors;
    final segments = _buildSegments();
    if (segments == null) {
      // 虚拟路径：单段展示友好名称
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.currentPath,
                  style: TextStyle(
                    fontSize: AppMetrics.fontBody,
                    color: c.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right, size: 12, color: c.textTertiary),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _startEditing,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
            final pos = _scrollController.position;
            _scrollController.jumpTo(
              (pos.pixels + event.scrollDelta.dy).clamp(
                0.0,
                pos.maxScrollExtent,
              ),
            );
          }
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0)
                  Icon(Icons.chevron_right, size: 12, color: c.textTertiary),
                _BreadcrumbSegment(
                  label: segments[i].label,
                  isCurrent: i == segments.length - 1,
                  onTap: () => widget.onSubmit(segments[i].path),
                ),
              ],
              Icon(Icons.chevron_right, size: 12, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField() {
    final c = context.colors;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEditing();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        style: TextStyle(fontSize: AppMetrics.fontBody, color: c.textPrimary),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final focused = _focusNode.hasFocus;
    return Container(
      height: AppMetrics.addressBarHeight,
      decoration: BoxDecoration(
        border: Border.all(color: focused ? c.accent : c.border),
        borderRadius: BorderRadius.circular(AppMetrics.tabRadius),
        color: c.surface,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _editing ? null : _startEditing,
        child: Row(
          children: [
            const SizedBox(width: 6),
            _buildIcon(),
            const SizedBox(width: 4),
            Expanded(child: _editing ? _buildTextField() : _buildBreadcrumb()),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _BreadcrumbSegment extends StatefulWidget {
  final String label;
  final bool isCurrent;
  final VoidCallback onTap;

  const _BreadcrumbSegment({
    required this.label,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  State<_BreadcrumbSegment> createState() => _BreadcrumbSegmentState();
}

class _BreadcrumbSegmentState extends State<_BreadcrumbSegment> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            color: _hovering ? c.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: AppMetrics.fontBody,
              color: _hovering || widget.isCurrent
                  ? c.textPrimary
                  : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
