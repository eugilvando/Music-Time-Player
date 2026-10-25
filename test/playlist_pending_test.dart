import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/m3u8.dart';
import 'package:music_time/library/playlist_reference.dart';
import 'package:music_time/library/playlist_batch_import.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/presentation/playlists_dialog.dart';

import 'catalog_widget_test.dart' show waitForCatalog;

void main() {
  test('pending OneDrive references keep drive-root meaning when exported elsewhere', () {
    final report = reviewM3u8(
      '#MUSICTIME-DRIVE:drive\n../Album/missing.mp3',
      r'C:\Users\Listener\OneDrive\Music\list.m3u8',
      [],
    );
    final entry = report.entries.single;
    final exported = exportPlaylistOccurrences(
      'Pending',
      [
        {
          'track_id': null,
          'original_reference': entry.reference,
          'reference_base': entry.sourcePath,
          'reference_drive': entry.driveId,
        },
      ],
      {},
      r'D:\Playlists\list.m3u8',
    );
    expect(exported, contains('/Album/missing.mp3'));
    expect(exported, contains('#MUSICTIME-DRIVE:drive'));
    final again = reviewM3u8(
      exported,
      r'D:\Playlists\list.m3u8',
      [],
    ).entries.single;
    expect(again.driveId, 'drive');
    expect(again.trackId, isNull);
    expect(again.reference, '/Album/missing.mp3');
  });
  const a = Track(
    id: 'a',
    title: 'Song A',
    artist: 'Artist',
    localPath: r'C:\Music\A #1.mp3',
  );
  const b = Track(
    id: 'b',
    title: 'Song B',
    artist: 'Artist',
    localPath: r'C:\Music\B.mp3',
  );
  const content =
      '#EXTM3U\n#PLAYLIST:Same\nA #1.mp3\n#EXTINF:123,Missing artist - Missing song\nmissing.mp3\nA #1.mp3';
  test('batch import continues after bad and unreadable files; all pending is valid', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([a]);
    final progress = <int>[];
    final results = await importPlaylistBatch(
      store,
      [
        PlaylistImportFile(r'C:\Music\one.m3u8', () async => content),
        PlaylistImportFile(
          r'C:\Music\bad.m3u8',
          () async => '#EXTM3U\n# no tracks',
        ),
        PlaylistImportFile(
          r'C:\Music\read.m3u8',
          () async => throw const FileSystemException('read'),
        ),
        PlaylistImportFile(
          r'C:\Music\two.m3u8',
          () async => '#PLAYLIST:Same\nnot-found.mp3',
        ),
      ],
      [a],
      onProgress: (done, total, current) {
        expect(total, 4);
        progress.add(done);
      },
    );
    expect(results.map((r) => r.failure), [null, 'format', 'read', null]);
    expect(results.first.found, 2);
    expect(results.first.pending, 1);
    expect(results.last.found, 0);
    expect(results.last.pending, 1);
    expect(progress.last, 4);
    expect((await store.playlists()).map((r) => r['name']), [
      'Same',
      'Same (2)',
    ]);
    final rows = await store.playlistOccurrences(results.first.id!);
    expect(rows.map((r) => r['track_id']), ['a', null, 'a']);
    expect(rows[1]['import_title'], 'Missing song');
    expect(rows[1]['import_artist'], 'Missing artist');
    expect(rows[1]['import_duration'], 123);
    expect(await store.playlistTrackIds(results.last.id!), isEmpty);
    expect(await store.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test('pending occurrences persist, manual linking keeps ordinal; retry rejects ambiguity', () async {
    final dir = await Directory.systemTemp.createTemp('music-time-pending-');
    addTearDown(() => dir.delete(recursive: true));
    final db = '${dir.path}/test.db';
    var store = await LibraryStore.open(db);
    final id = await store.importReviewedPlaylist(
      'Pending',
      reviewM3u8('B.mp3\nB.mp3', r'C:\Music\list.m3u8', []),
    );
    await store.close();
    store = await LibraryStore.open(db);
    addTearDown(store.close);
    final before = await store.playlistOccurrences(id);
    await store.addTracks([
      b,
      const Track(
        id: 'duplicate',
        title: 'Other',
        artist: 'Other',
        localPath: r'C:\Music\B.mp3',
      ),
    ]);
    expect(
      await retryPlaylistReferences(
        store,
        id,
        await store.loadTracks(includeCovers: false),
      ),
      0,
    );
    await store.linkPlaylistOccurrence(before.first['id'] as int, 'b');
    final rows = await store.playlistOccurrences(id);
    expect(rows.map((r) => r['ordinal']), [0, 1]);
    expect(rows.map((r) => r['id']), before.map((r) => r['id']));
    expect(rows.map((r) => r['track_id']), ['b', null]);
    await store.removePlaylistEntry(rows.last['id'] as int);
    expect((await store.playlists()).single['pending_count'], 0);
  });
  test(
    'retry after synchronization links every exact repeated occurrence',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final id = await store.importReviewedPlaylist(
        'Retry',
        reviewM3u8('B.mp3\nB.mp3', r'C:\Music\list.m3u8', []),
      );
      await store.addTracks([b]);
      expect(await retryPlaylistReferences(store, id, [b]), 2);
      expect(await store.playlistTrackIds(id), ['b', 'b']);
    },
  );
  test('SQLite 15 migration preserves occurrence IDs, favorites, history and queue', () async {
    final dir = await Directory.systemTemp.createTemp('music-time-migrate-');
    addTearDown(() => dir.delete(recursive: true));
    final file = '${dir.path}/test.db';
    var store = await LibraryStore.open(file);
    await store.addTracks([a]);
    final id = await store.importPlaylist('Old', ['a', 'a']);
    await store.setFavorite('a', true);
    await store.savePlayback(
      [a, a],
      1,
      const Duration(seconds: 12),
      title: 'Preserved',
    );
    await store.recordHistory(
      'a',
      DateTime.utc(2026),
      const Duration(seconds: 30),
    );
    await store.database.insert('downloads', {
      'track_id': 'a',
      'status': 'complete',
      'path': 'C:/fixture/download.mp3',
      'received': 123,
      'total': 123,
    });
    await store.database.execute('DROP INDEX playlist_entries_order_idx');
    await store.database.execute(
      'ALTER TABLE playlist_entries RENAME TO entries_new',
    );
    await store.database.execute(
      'CREATE TABLE playlist_entries(id INTEGER PRIMARY KEY AUTOINCREMENT,playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,track_id TEXT NOT NULL REFERENCES tracks(id),ordinal INTEGER NOT NULL)',
    );
    await store.database.execute(
      'INSERT INTO playlist_entries SELECT id,playlist_id,track_id,ordinal FROM entries_new',
    );
    await store.database.execute('DROP TABLE entries_new');
    await store.database.rawInsert(
      'INSERT INTO playlist_entries VALUES(9,?,?,2)',
      [id, 'a'],
    );
    await store.database.execute('DELETE FROM playlist_entries WHERE id=9');
    await store.database.execute('PRAGMA user_version=15');
    await store.close();
    store = await LibraryStore.open(file);
    addTearDown(store.close);
    expect(await store.playlistTrackIds(id), ['a', 'a']);
    expect((await store.playlistOccurrences(id)).map((r) => r['id']), [1, 2]);
    expect(await store.favoriteIds(), {'a'});
    final playback = await store.loadPlayback();
    expect(playback.queue.map((t) => t.id), ['a', 'a']);
    expect(playback.position, const Duration(seconds: 12));
    expect(playback.title, 'Preserved');
    expect((await store.history()).length, 1);
    expect((await store.database.query('downloads')).single['received'], 123);
    expect(
      (await store.database.rawQuery('PRAGMA user_version'))
          .single
          .values
          .single,
      18,
    );
    expect(await store.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await store.appendToPlaylist(id, 'a');
    expect((await store.playlistOccurrences(id)).last['id'], 10);
  });
  test(
    'schema17 backup roundtrip retains pending metadata and deliberate repeats',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      await store.addTracks([a]);
      final id = await store.importReviewedPlaylist(
        'Backup',
        reviewM3u8(content, r'C:\Music\list.m3u8', [a]),
      );
      final backup = await AppData.backup(store, prefs);
      expect(AppData.parse(backup)['schema'], 17);
      await store.deletePlaylist(id);
      await AppData.restore(store, prefs, backup);
      expect((await store.playlistOccurrences(id)).map((r) => r['track_id']), [
        'a',
        null,
        'a',
      ]);
    },
  );
  test('export rebases missing relative refs and preserves resolved Unicode and cloud IDs', () {
    const cloud = Track(
      id: 'webdav:account/á&b',
      title: 'Nuvem',
      artist: 'Artista',
      sourceProvider: 'webdav',
    );
    final report = reviewM3u8(content, r'C:\Music\old.m3u8', [a]);
    final rows = [
      for (final e in report.entries)
        {
          'track_id': e.trackId,
          'original_reference': e.reference,
          'reference_base': e.sourcePath,
          'reference_drive': e.driveId,
          'import_title': e.title,
          'import_artist': e.artist,
          'import_duration': e.durationSeconds,
        },
      {'track_id': cloud.id},
    ];
    final exported = exportPlaylistOccurrences('Mix', rows, {
      'a': a,
      cloud.id: cloud,
    }, r'C:\Else\new.m3u8');
    expect(exported, contains(r'..\Music\missing.mp3'));
    final again = reviewM3u8(exported, r'C:\Else\new.m3u8', [a, cloud]);
    expect(again.entries.map((e) => e.trackId), ['a', null, 'a', cloud.id]);
    expect(
      PlaylistReference.local(again.entries[1].reference, r'C:\Else\new.m3u8'),
      r'C:\Music\missing.mp3',
    );
    expect(again.entries[1].title, 'Missing song');
    expect(again.entries[1].durationSeconds, 123);
    expect(exported, isNot(contains('https://')));
  });
  test('local special characters stay literal; signed URLs are never persisted or exported', () {
    expect(PlaylistReference.safe(r'C:\Music\A #1.mp3'), r'C:\Music\A #1.mp3');
    final e = reviewM3u8(
      'https://host/audio?token=secret',
      r'C:\list.m3u8',
      [],
    ).entries.single;
    expect(e.reference, isNot(contains('secret')));
    expect(e.reason, 'unsupported');
    expect(
      () =>
          PlaylistReference.rebase('https://host/audio?token=secret', 'a', 'b'),
      throwsFormatException,
    );
    const downloaded = Track(
      id: 'cloud',
      title: 'Cloud',
      artist: 'A',
      sourceProvider: 'webdav',
      localPath: r'C:\managed\cache.audio',
    );
    expect(exportM3u8('X', [downloaded]), isNot(contains('cache.audio')));
  });
  testWidgets(
    'resolving the last pending item hides repair controls and restores all tracks',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final id = (await tester.runAsync(() async {
        await store.addTracks([a]);
        return store.importReviewedPlaylist(
          'Repair',
          reviewM3u8('B.mp3\nA #1.mp3', r'C:\Music\l.m3u8', [a]),
        );
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistsPage(
              store: store,
              tracks: const [a],
              initialPlaylist: id,
              onPlay: (_, _) {},
            ),
          ),
        ),
      );
      await waitForCatalog(
        tester,
        () => find.text('Song A').evaluate().isNotEmpty,
      );
      expect(find.text('Retry resolution'), findsOneWidget);
      await tester.tap(find.text('Missing items'));
      await tester.pump();
      expect(find.text('Song A'), findsNothing);
      await tester.runAsync(() => store.addTracks([b]));
      await tester.tap(find.text('Retry resolution'));
      await waitForCatalog(
        tester,
        () => find.text('Song A').evaluate().isNotEmpty,
      );
      expect(find.text('Song B'), findsOneWidget);
      expect(find.text('Missing items'), findsNothing);
      expect(find.text('Retry resolution'), findsNothing);
      expect(find.text('1 items not found'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'pending item list skips unresolved occurrences when playing and shows warning',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final id = (await tester.runAsync(() async {
        await store.addTracks([a, b]);
        return store.importReviewedPlaylist(
          'Partial',
          reviewM3u8('missing.mp3\nB.mp3\nA #1.mp3', r'C:\Music\l.m3u8', [
            a,
            b,
          ]),
        );
      }))!;
      List<Track>? played;
      int? index;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistsPage(
              store: store,
              tracks: const [a, b],
              initialPlaylist: id,
              onPlay: (v, i) {
                played = v;
                index = i;
              },
            ),
          ),
        ),
      );
      await waitForCatalog(
        tester,
        () => find.text('Song A').evaluate().isNotEmpty,
      );
      expect(find.text('1 items not found'), findsOneWidget);
      await tester.tap(find.text('Song A'));
      await tester.pump();
      expect(played?.map((t) => t.id), ['b', 'a']);
      expect(index, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
    },
  );
}
