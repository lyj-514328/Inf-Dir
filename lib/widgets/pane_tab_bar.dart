import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../state/pane_controller.dart';
import '../services/icon_service.dart';
import '../services/file_service.dart';
import 'app_theme.dart';
import 'home_icon.dart';

/// 标签拖动数据。只携带定位信息；真实标签状态在落点时经 LayoutState
/// 现取，避免拖动过程中源标签变化导致 payload 过期。
class TabDragPayload {
  final String sourcePaneId;
  final int index;
  final String label;

  const TabDragPayload({
    required this.sourcePaneId,
    required this.index,
    required this.label,
  });
}

class PaneTabBar extends StatefulWidget {
  final String paneId;
  final List<TabInfo> tabs;
  final int activeIndex;
  final ValueChanged<int> onSwitchTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onAddTab;

  /// 同 pane 拖动排序：insertIndex 为视觉插入位（原列表坐标系）。
  final void Function(int from, int insertIndex) onReorderTab;

  /// 标签右键菜单（由调用方构建菜单并弹出）。
  final void Function(int index, Offset globalPosition) onTabContextMenu;

  /// 跨 pane 投放可行性：copy 为 Ctrl 拖动复制。
  final bool Function(TabDragPayload payload, {required bool copy})
  canAcceptForeignTab;

  /// 跨 pane 投放落点。
  final void Function(TabDragPayload payload, int insertIndex, bool copy)
  onForeignTabDropped;

  const PaneTabBar({
    super.key,
    required this.paneId,
    required this.tabs,
    required this.activeIndex,
    required this.onSwitchTab,
    required this.onCloseTab,
    required this.onAddTab,
    required this.onReorderTab,
    required this.onTabContextMenu,
    required this.canAcceptForeignTab,
    required this.onForeignTabDropped,
  });

  @override
  State<PaneTabBar> createState() => _PaneTabBarState();
}

class _PaneTabBarState extends State<PaneTabBar> {
  /// 当前拖动悬停的插入位；null 表示无拖动。
  int? _insertIndex;

  /// 当前悬停的拖动是否会被拒绝（用于 danger 指示）。
  bool _hoverRejected = false;
  Timer? _rejectFlashTimer;
  bool _rejectFlashing = false;

  @override
  void dispose() {
    _rejectFlashTimer?.cancel();
    super.dispose();
  }

  bool _isOwnPayload(TabDragPayload payload) =>
      payload.sourcePaneId == widget.paneId;

  bool _willAccept(TabDragPayload payload) {
    if (_isOwnPayload(payload)) return true;
    return widget.canAcceptForeignTab(
      payload,
      copy: HardwareKeyboard.instance.isControlPressed,
    );
  }

  void _setInsert(int index, {required bool rejected}) {
    if (_insertIndex == index && _hoverRejected == rejected) return;
    setState(() {
      _insertIndex = index;
      _hoverRejected = rejected;
    });
  }

  void _clearDragState() {
    if (_insertIndex == null) return;
    setState(() {
      _insertIndex = null;
      _hoverRejected = false;
    });
  }

  void _acceptDrop(TabDragPayload payload, int fallbackIndex) {
    final insertIndex = _insertIndex ?? fallbackIndex;
    setState(() {
      _insertIndex = null;
      _hoverRejected = false;
    });
    if (_isOwnPayload(payload)) {
      widget.onReorderTab(payload.index, insertIndex);
      return;
    }
    final copy = HardwareKeyboard.instance.isControlPressed;
    if (!widget.canAcceptForeignTab(payload, copy: copy)) {
      _flashRejected();
      return;
    }
    widget.onForeignTabDropped(payload, insertIndex, copy);
  }

  void _flashRejected() {
    _rejectFlashTimer?.cancel();
    setState(() => _rejectFlashing = true);
    _rejectFlashTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _rejectFlashing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rejected = _hoverRejected || _rejectFlashing;
    return SizedBox(
      height: AppMetrics.paneTabBarHeight,
      child: Row(
        children: [
          Expanded(
            // 整条标签栏作为「追加到末尾」的投放目标；
            // 每个标签上的 DragTarget 优先处理精确插入位。
            child: DragTarget<TabDragPayload>(
              onWillAcceptWithDetails: (details) => _willAccept(details.data),
              onMove: (details) => _setInsert(
                widget.tabs.length,
                rejected: !_willAccept(details.data),
              ),
              onLeave: (_) => _clearDragState(),
              onAcceptWithDetails: (details) =>
                  _acceptDrop(details.data, widget.tabs.length),
              builder: (context, candidate, _) => DecoratedBox(
                decoration: BoxDecoration(
                  border: rejected
                      ? Border(
                          bottom: BorderSide(color: c.danger, width: 2),
                        )
                      : null,
                ),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(3, 0, 4, 0),
                  itemCount: widget.tabs.length + 1,
                  itemBuilder: (context, index) {
                    if (index == widget.tabs.length) {
                      // 追加到末尾的插入位显示在 + 按钮之前。
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_insertIndex == widget.tabs.length)
                            Center(child: _buildInsertIndicator()),
                          _AddTabButton(onTap: widget.onAddTab),
                        ],
                      );
                    }
                    return _buildTabSlot(context, index);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsertIndicator() => Container(
    width: 3,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(
      color: _hoverRejected ? context.colors.danger : context.colors.accent,
      borderRadius: BorderRadius.circular(1.5),
    ),
  );

  Widget _buildTabSlot(BuildContext outerContext, int index) {
    final tab = widget.tabs[index];
    final payload = TabDragPayload(
      sourcePaneId: widget.paneId,
      index: index,
      label: tab.label,
    );
    final showIndicator = _insertIndex == index;

    return DragTarget<TabDragPayload>(
      onWillAcceptWithDetails: (details) => _willAccept(details.data),
      onMove: (details) {
        final box = outerContext.findRenderObject();
        double insert = index.toDouble();
        if (box is RenderBox) {
          final local = box.globalToLocal(details.offset);
          if (local.dx > box.size.width / 2) insert = index + 1.0;
        }
        _setInsert(insert.round(), rejected: !_willAccept(details.data));
      },
      onLeave: (_) => _clearDragState(),
      onAcceptWithDetails: (details) => _acceptDrop(details.data, index),
      builder: (context, candidate, _) {
        final tabChild = Listener(
          onPointerDown: (event) {
            if (event.buttons & kMiddleMouseButton != 0) {
              widget.onCloseTab(index);
            }
          },
          child: GestureDetector(
            onTap: () => widget.onSwitchTab(index),
            onSecondaryTapUp: (details) =>
                widget.onTabContextMenu(index, details.globalPosition),
            child: _TabItem(
              label: tab.label,
              path: tab.path,
              isActive: index == widget.activeIndex,
              onTap: () => widget.onSwitchTab(index),
              onClose: () => widget.onCloseTab(index),
              showClose: widget.tabs.length > 1,
            ),
          ),
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          // stretch：保持 ListView 竖向紧约束传给 chip，维持原有撑满高度。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showIndicator) Center(child: _buildInsertIndicator()),
            // 唯一标签无处可拖（排序无意义、跨 pane 移动被拒），禁用拖动。
            if (widget.tabs.length > 1)
              Draggable<TabDragPayload>(
                data: payload,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: _TabDragFeedback(label: tab.label),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: _TabItem(
                    label: tab.label,
                    path: tab.path,
                    isActive: index == widget.activeIndex,
                    onTap: () {},
                    onClose: () {},
                    showClose: false,
                  ),
                ),
                child: tabChild,
              )
            else
              tabChild,
          ],
        );
      },
    );
  }
}

class _TabDragFeedback extends StatelessWidget {
  final String label;

  const _TabDragFeedback({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 与文件拖动反馈一致：偏移到光标右下方，避免遮挡投放位置。
    return Transform.translate(
      offset: const Offset(14, 20),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.menuSurface,
            border: Border.all(color: c.menuBorder),
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            boxShadow: [
              BoxShadow(
                color: c.shadow,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.drag_indicator,
                size: 16,
                color: c.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: AppMetrics.fontSmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTabButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AddTabButton({required this.onTap});

  @override
  State<_AddTabButton> createState() => _AddTabButtonState();
}

class _AddTabButtonState extends State<_AddTabButton> {
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
          width: 24,
          height: 22,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            color: _hovering ? c.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          ),
          child: Icon(
            Icons.add,
            size: AppMetrics.iconSm,
            color: c.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  final String label;
  final String path;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final bool showClose;

  const _TabItem({
    required this.label,
    required this.path,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    required this.showClose,
  });

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hoveringTab = false;
  bool _hoveringClose = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sourceSize =
        (AppMetrics.iconSm * View.of(context).devicePixelRatio).ceil();
    final iconBytes = FileService.isHomePath(widget.path)
        ? null
        : IconService.getFileIconPng(widget.path, true, sourceSize);
    final iconWidget = FileService.isHomePath(widget.path)
        ? const HomeIcon(size: AppMetrics.iconSm)
        : iconBytes != null
        ? Image.memory(
            iconBytes,
            width: AppMetrics.iconSm,
            height: AppMetrics.iconSm,
            gaplessPlayback: true,
          )
        : Icon(Icons.folder, size: AppMetrics.iconSm, color: c.iconFolder);

    final isActive = widget.isActive;
    final Color bgColor = isActive
        ? c.surface
        : _hoveringTab
        ? c.surfaceHover
        : Colors.transparent;

    final decoration = BoxDecoration(
      color: bgColor,
      border: Border.all(
        color: isActive ? c.border : c.border.withValues(alpha: 0.55),
        width: 1,
      ),
      borderRadius: BorderRadius.circular(AppMetrics.tabRadius),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveringTab = true),
      onExit: (_) => setState(() => _hoveringTab = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 150),
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          decoration: decoration,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: AppMetrics.iconSm,
                height: AppMetrics.iconSm,
                child: iconWidget,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: AppMetrics.fontSmall,
                    color: isActive ? c.textPrimary : c.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.showClose) ...[
                const SizedBox(width: 2),
                MouseRegion(
                  onEnter: (_) => setState(() => _hoveringClose = true),
                  onExit: (_) => setState(() => _hoveringClose = false),
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: _hoveringClose ? c.danger : c.textTertiary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
