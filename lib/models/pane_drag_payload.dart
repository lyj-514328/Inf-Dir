import 'layout_node.dart';

/// 仅用于应用内布局拖放；与文件、标签拖放 payload 类型隔离。
class PaneDragPayload {
  const PaneDragPayload({required this.source, required this.label});

  final LayoutNode source;
  final String label;
}
