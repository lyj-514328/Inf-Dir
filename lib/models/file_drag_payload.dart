import 'package:flutter/foundation.dart';

class FileDragItem {
  const FileDragItem({required this.path, required this.isDirectory});

  final String path;
  final bool isDirectory;
}

class FileDragTargetFeedback {
  const FileDragTargetFeedback({
    required this.owner,
    required this.accepted,
    required this.copy,
    required this.destination,
    required this.message,
  });

  final String owner;
  final bool accepted;
  final bool copy;
  final String destination;
  final String message;

  String get label =>
      accepted ? '${copy ? '复制' : '移动'}到 $destination' : message;

  @override
  bool operator ==(Object other) =>
      other is FileDragTargetFeedback &&
      owner == other.owner &&
      accepted == other.accepted &&
      copy == other.copy &&
      destination == other.destination &&
      message == other.message;

  @override
  int get hashCode => Object.hash(owner, accepted, copy, destination, message);
}

class FileDragPayload {
  FileDragPayload({
    required this.sourceDirectory,
    required List<FileDragItem> items,
  }) : items = List.unmodifiable(items);

  final String sourceDirectory;
  final List<FileDragItem> items;
  final ValueNotifier<FileDragTargetFeedback?> targetFeedback = ValueNotifier(
    null,
  );

  List<String> get paths =>
      items.map((item) => item.path).toList(growable: false);

  void showTargetFeedback(FileDragTargetFeedback feedback) {
    if (targetFeedback.value != feedback) targetFeedback.value = feedback;
  }

  void clearTargetFeedback([String? owner]) {
    final current = targetFeedback.value;
    if (current == null || (owner != null && current.owner != owner)) return;
    targetFeedback.value = null;
  }
}
