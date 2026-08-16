import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/services/icon_service.dart';
import 'package:inf_dir/services/prefs_store.dart';
import 'package:inf_dir/services/thumbnail_cache.dart';
import 'package:inf_dir/services/thumbnail_worker.dart';
import 'package:inf_dir/state/app_state.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('inf-dir-thumbs-');
    IconService.debugReset(
      cache: ThumbnailCache(directory: Directory(p.join(tempDir.path, 'thumbs'))),
    );
    ThumbnailWorker.extractImpl = null;
  });

  tearDown(() {
    ThumbnailWorker.extractImpl = null;
    IconService.debugReset(
      cache: ThumbnailCache(directory: Directory(p.join(tempDir.path, 'reset'))),
    );
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('wantsThumbnail follows icon-mode size threshold', () {
    expect(IconService.wantsThumbnail(16), isFalse);
    expect(IconService.wantsThumbnail(20), isFalse);
    expect(IconService.wantsThumbnail(34), isTrue);
    expect(IconService.wantsThumbnail(96), isTrue);
  });

  test('cache key includes path, mtime and size', () {
    final modified = DateTime.fromMillisecondsSinceEpoch(123);
    expect(
      IconService.thumbnailCacheKey(
        path: r'C:\pic.jpg',
        size: 192,
        modified: modified,
      ),
      'T:C:\\pic.jpg:123:192',
    );
  });

  test('memory cache evicts oldest entries', () {
    final cache = ThumbnailCache(
      directory: Directory(p.join(tempDir.path, 'lru')),
      maxEntries: 2,
      maxBytes: 1024,
    );
    cache.putMemory('a', Uint8List.fromList([1]));
    cache.putMemory('b', Uint8List.fromList([2]));
    cache.putMemory('c', Uint8List.fromList([3]));
    expect(cache.getMemory('a'), isNull);
    expect(cache.getMemory('b'), [2]);
    expect(cache.getMemory('c'), [3]);
  });

  test('getThumbnailPng caches extract result and skips retries on miss', () async {
    var extracts = 0;
    ThumbnailWorker.extractImpl = (path, size, flags) {
      extracts += 1;
      expect(flags, IconService.imageThumbnailOnly);
      return Uint8List.fromList([10, 20, 30]);
    };

    final first = await IconService.getThumbnailPng(
      path: r'C:\pic.jpg',
      size: 96,
      modified: DateTime.fromMillisecondsSinceEpoch(1),
    );
    final second = await IconService.getThumbnailPng(
      path: r'C:\pic.jpg',
      size: 96,
      modified: DateTime.fromMillisecondsSinceEpoch(1),
    );
    expect(first, [10, 20, 30]);
    expect(second, [10, 20, 30]);
    expect(extracts, 1);

    extracts = 0;
    ThumbnailWorker.extractImpl = (path, size, flags) {
      extracts += 1;
      return null;
    };
    final missed = await IconService.getThumbnailPng(
      path: r'C:\none.jpg',
      size: 96,
    );
    final retried = await IconService.getThumbnailPng(
      path: r'C:\none.jpg',
      size: 96,
    );
    expect(missed, isNull);
    expect(retried, isNull);
    expect(extracts, 1);
  });

  test('prefs store persists showThumbnails', () {
    final store = PrefsStore(filePath: p.join(tempDir.path, 'prefs.json'));
    expect(store.load(), isEmpty);
    store.save({'showThumbnails': false});
    expect(store.load()['showThumbnails'], isFalse);
  });

  test('AppState thumbnail toggle is persisted', () {
    final store = PrefsStore(filePath: p.join(tempDir.path, 'prefs.json'));
    final repository = DirectoryRepository(
      cursorFactory: (_, {bool directoriesOnly = false}) async => null,
      hasChildrenProbe: (_) => false,
    );
    final first = AppState(repository: repository, prefs: store);
    expect(first.showThumbnails, isTrue);
    first.setShowThumbnails(false);
    first.dispose();

    final restored = AppState(repository: repository, prefs: store);
    expect(restored.showThumbnails, isFalse);
    restored.dispose();
  });
}
