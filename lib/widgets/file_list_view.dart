import 'package:flutter/material.dart';
import '../models/file_entry.dart';

class FileListView extends StatelessWidget {
  final List<FileEntry> entries;
  final Set<String> selectedPaths;
  final ValueChanged<String> onSingleTap;
  final ValueChanged<String> onDoubleTap;
  final bool loading;

  const FileListView({
    super.key,
    required this.entries,
    required this.selectedPaths,
    required this.onSingleTap,
    required this.onDoubleTap,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Column(
      children: [
        _ColumnHeader(),
        Container(height: 1, color: const Color(0xFFD0D0D0)),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text(
                    '空文件夹',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemExtent: 22,
                  padding: EdgeInsets.zero,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _FileRow(
                      entry: entry,
                      isSelected: selectedPaths.contains(entry.path),
                      onSingleTap: () => onSingleTap(entry.path),
                      onDoubleTap: () => onDoubleTap(entry.path),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: const Row(
        children: [
          _HeaderCell(label: '名称', flex: 4),
          _HeaderCell(label: '修改日期', flex: 2),
          _HeaderCell(label: '类型', flex: 2),
          _HeaderCell(label: '大小', flex: 1),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;

  const _HeaderCell({required this.label, required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF333333),
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final FileEntry entry;
  final bool isSelected;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;

  const _FileRow({
    required this.entry,
    required this.isSelected,
    required this.onSingleTap,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? const Color(0xFF0078D4)
        : Colors.transparent;
    final textColor = isSelected ? Colors.white : const Color(0xFF1A1A1A);

    return GestureDetector(
      onTap: onSingleTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Icon(
                    entry.isDirectory ? Icons.folder : Icons.insert_drive_file,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : (entry.isDirectory
                            ? Colors.amber.shade700
                            : Colors.grey.shade600),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      entry.name,
                      style: TextStyle(fontSize: 12, color: textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                entry.formattedDate,
                style: TextStyle(fontSize: 12, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                entry.type,
                style: TextStyle(fontSize: 12, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                entry.formattedSize,
                style: TextStyle(fontSize: 12, color: textColor),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
