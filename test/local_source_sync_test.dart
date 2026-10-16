import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/library/local_source_sync.dart';
import 'package:music_time/persistence/library_store.dart';

void main() {
  test('reindexação reconcilia ausentes, restaura retornos e preserva referências e arquivos', () async {
    final root = await Directory.systemTemp.createTemp(
      'music-time-local-sync-',
    );
    final store = await LibraryStore.open(':memory:');
    final sync = LocalSourceSync(store);
    try {
      final sub = await Directory(path.join(root.path, 'sub')).create();
      final a = await File(path.join(root.path, 'a.mp3'))
          .writeAsBytes([1, 2, 3]);
      final b = await File(path.join(sub.path, 'b.flac'))
          .writeAsBytes([4, 5, 6]);
      final image = await File('${root.path}/cover.jpg').writeAsBytes([7]);
      await sync.sync(root.path);
      expect((await store.loadTracks()).length, 2);
      final playlist = await store.importPlaylist('Original', [a.path, b.path]);
      final added = (await store.loadTracks())
          .singleWhere((t) => t.id == a.path)
          .addedAt;
      await store.registerLocalSource('other', 'Outra fonte', [a.path]);
      // Moving a fixture out of this source simulates a missing file without
      // deleting it. The synchronizer never writes/deletes source files.
      await a.rename('${root.path}/a.backup');
      await b.rename('${sub.path}/b.backup');
      await sync.sync(root.path);
      expect((await store.loadTracks()).map((t) => t.id).toList(), [a.path]);
      expect(
        await store.database.query(
          'playlist_entries',
          where: 'playlist_id=?',
          whereArgs: [playlist],
        ),
        hasLength(2),
      );
      expect(
        (jsonDecode(
          (await store.localSources()).singleWhere(
                (r) => r['id'] == root.path,
              )['sync_summary']
              as String,
        ) as Map)['missing'],
        2,
      );
      await store.removeLocalSource('other');
      expect(await store.loadTracks(), isEmpty);
      await File('${root.path}/a.backup').rename(a.path);
      await sync.sync(root.path);
      expect((await store.loadTracks()).single.id, a.path);
      expect((await store.loadTracks()).single.addedAt, added);
      expect(await image.readAsBytes(), [7]);
      expect(await a.readAsBytes(), [1, 2, 3]);
    } finally {
      sync.dispose();
      await store.close();
      await root.delete(recursive: true);
    }
  });
  test('pasta inacessível e cancelamento não reconciliam a fonte', () async {
    final root = await Directory.systemTemp.createTemp(
      'music-time-local-fail-',
    );
    final store = await LibraryStore.open(':memory:');
    final sync = LocalSourceSync(store);
    try {
      final a = await File(path.join(root.path, 'a.mp3')).writeAsBytes([1]);
      await sync.sync(root.path);
      final original = (await store.localSources()).singleWhere(
        (r) => r['id'] == root.path,
      )['sync_summary'];
      await expectLater(
        sync.sync('${root.path}/missing'),
        throwsA(isA<FileSystemException>()),
      );
      expect((await store.loadTracks()).single.id, a.path);
      void cancel() {
        if (sync.running) sync.cancelled = true;
      }

      sync.addListener(cancel);
      await expectLater(
        sync.sync(root.path),
        throwsA(isA<LocalSyncCancelled>()),
      );
      expect(
        (await store.localSources()).singleWhere(
          (r) => r['id'] == root.path,
        )['sync_summary'],
        original,
      );
      expect((await store.loadTracks()).single.id, a.path);
    } finally {
      sync.dispose();
      await store.close();
      await root.delete(recursive: true);
    }
  });
}
