import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/home_service.dart';
import 'app_theme.dart';

Future<void> showFavoritesDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _FavoritesDialog(),
  );
}

class _FavoritesDialog extends StatefulWidget {
  const _FavoritesDialog();

  @override
  State<_FavoritesDialog> createState() => _FavoritesDialogState();
}

class _FavoritesDialogState extends State<_FavoritesDialog> {
  late List<RecentFile> _favorites;

  @override
  void initState() {
    super.initState();
    _favorites = HomeService.getFavorites(limit: 200);
  }

  void _remove(RecentFile favorite) {
    HomeService.removeFavorite(favorite.path);
    setState(() {
      _favorites = _favorites
          .where((item) => item.path != favorite.path)
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('管理收藏夹'),
      content: SizedBox(
        width: 480,
        height: 360,
        child: _favorites.isEmpty
            ? Center(
                child: Text('暂无收藏', style: TextStyle(color: c.textSecondary)),
              )
            : ListView.separated(
                itemCount: _favorites.length,
                separatorBuilder: (_, _) => Divider(color: c.border),
                itemBuilder: (context, index) {
                  final favorite = _favorites[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.folder_outlined,
                      color: c.textSecondary,
                    ),
                    title: Text(p.basename(favorite.path)),
                    subtitle: Text(
                      favorite.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSecondary),
                    ),
                    trailing: IconButton(
                      tooltip: '移除收藏',
                      icon: const Icon(Icons.remove_circle_outline),
                      color: c.textSecondary,
                      onPressed: () => _remove(favorite),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
