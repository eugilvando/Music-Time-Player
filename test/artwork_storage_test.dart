import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/catalog_query.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/persistence/library_store.dart';

Track track(String id, [Uint8List? cover]) => Track(
  id: id,
  title: id,
  artist: 'Artist',
  localPath: 'C:/$id.mp3',
  cover: cover,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'identical covers stored once and read through every player/catalog path',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      await store.addTracks([track('a', bytes), track('b', bytes)]);
      expect((await store.database.query('artworks')).length, 1);
      expect(
        (await store.database.query('tracks')).every((r) => r['cover'] == null),
        true,
      );
      expect(await store.artwork.storedBytes(), 4);
      expect(await store.trackCover('b'), bytes);
      expect(
        (await store.loadTracks()).every(
          (t) => t.hasArtwork && t.cover != null,
        ),
        true,
      );
      expect(
        (await store.loadTracks(includeCovers: false))
            .every((t) => t.hasArtwork && t.cover == null),
        true,
      );
      final page = await store.catalogPage(
        CatalogSqlQuery(filters: CatalogFilters()),
      );
      expect(page.tracks.first.cover, bytes);
      await store.savePlayback(page.tracks, 0, Duration.zero);
      expect((await store.loadPlayback()).queue.first.cover, bytes);
      final id = await store.importPlaylist('Playlist', ['a', 'b']);
      expect(
        (await store.playlistArtworkTracks(id)).every((t) => t.hasArtwork),
        true,
      );
      expect(
        (await store.playlistEntries(id)).every((r) => r['has_cover'] == 1),
        true,
      );
      expect(
        await store.database.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
    },
  );

  test(
    'preserving, replacing and removing a cover never changes a shared sibling',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final original = Uint8List.fromList([1, 2]);
      await store.addTracks([track('a', original), track('b', original)]);
      await store.addTracks([track('a')], preserveCovers: true);
      expect(await store.trackCover('a'), original);
      await store.addTracks([
        track('a', Uint8List.fromList([9])),
      ]);
      expect(await store.trackCover('b'), original);
      await store.addTracks([track('a')]);
      expect(await store.trackCover('a'), null);
      await store.artwork.optimize(compact: false);
      expect((await store.database.query('artworks')).length, 1);
    },
  );

  test('legacy conversion can stop, resume and compact losslessly while preserving relationships', () async {
    final dir = await Directory.systemTemp.createTemp('music-time-artwork-');
    final file = File('${dir.path}/fixture.db');
    var store = await LibraryStore.open(file.path);
    try {
      final bytes = Uint8List(32768)..fillRange(0, 32768, 7);
      await store.addTracks(List.generate(40, (i) => track('$i')));
      await store.database.update('tracks', {'cover': bytes});
      await store.database.execute('PRAGMA user_version=14');
      await store.setFavorite('1', true);
      await store.importPlaylist('Repeated', ['1', '1', '2']);
      await store.close();
      store = await LibraryStore.open(file.path);
      final before = await file.length();
      await store.artwork.optimize(onProgress: (_) => store.artwork.cancel());
      expect(
        (await store.database.rawQuery(
          'SELECT count(*) AS n FROM tracks WHERE cover IS NOT NULL',
        )).single['n'],
        24,
      );
      await store.artwork.optimize();
      expect((await store.database.query('artworks')).length, 1);
      expect(await store.artwork.storedBytes(), bytes.length);
      expect(
        (await store.loadTracks()).every(
          (t) => listEqualsBytes(t.cover, bytes),
        ),
        true,
      );
      expect(await store.favoriteIds(), {'1'});
      expect(
        (await store.playlistEntries(
          (await store.playlists()).single['id'] as int,
        )).length,
        3,
      );
      expect(await file.length(), lessThan(before));
      expect(
        await store.database.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('backup exports shared artwork once, restores it, and rejects changed content', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final bytes = Uint8List.fromList([4, 5, 6]);
    await store.addTracks([track('a', bytes), track('b', bytes)]);
    final backup = await AppData.backup(store, prefs);
    final doc = jsonDecode(backup);
    expect(doc['schema'], 16);
    expect(doc['tables']['artworks'].length, 1);
    await AppData.restore(store, prefs, backup);
    expect(await store.trackCover('b'), bytes);
    doc['tables']['artworks'][0]['byte_count'] = 12;
    await expectLater(
      AppData.restore(store, prefs, jsonEncode(doc)),
      throwsFormatException,
    );
    expect(await store.trackCover('b'), bytes);
  });

  test('old backup with embedded covers remains readable', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([track('a')]);
    final doc = jsonDecode(await AppData.backup(store, prefs));
    doc['schema'] = 12;
    (doc['tables'] as Map).remove('artworks');
    final row = doc['tables']['tracks'][0] as Map;
    row.remove('cover_hash');
    row['cover'] = {
      'base64': base64Encode([7, 8]),
    };
    await AppData.restore(store, prefs, jsonEncode(doc));
    expect(await store.trackCover('a'), [7, 8]);
    await store.artwork.optimize(compact: false);
    expect(await store.trackCover('a'), [7, 8]);
  });
}

bool listEqualsBytes(Uint8List? a, Uint8List b) =>
    a != null &&
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
