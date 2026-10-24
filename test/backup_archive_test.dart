import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/persistence/backup_archive.dart';
import 'package:music_time/persistence/library_store.dart';

import 'provider_auth_test.dart' show MemoryVault;

void main() {
  test('selected library restore retains source relationships and paused queue position', () async {
    SharedPreferences.setMockInitialValues({
      'visual.continuous_count': 10.0,
      'collections.favorites': ['artist:Artist'],
    });
    final prefs = await SharedPreferences.getInstance(),
        store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    const a = Track(
      id: 'a',
      title: 'A',
      artist: 'Artist',
      localPath: 'C:/a.mp3',
    );
    await store.addTracks([a]);
    await store.registerLocalSource('folder', 'Folder', ['a']);
    await store.savePlayback([a, a], 1, const Duration(seconds: 25));
    await store.setFavorite('a', true);
    final sections = {'library', 'queue', 'favorites', 'preferences'};
    final archive = await BackupArchive.read(
      await BackupArchive.create(store, prefs, MemoryVault(), sections),
    );
    await store.database.delete('local_source_tracks');
    await store.database.delete('local_sources');
    await store.setFavorite('a', false);
    await BackupArchive.restore(store, prefs, MemoryVault(), archive, sections);
    expect(await store.favoriteIds(), {'a'});
    expect(await store.database.query('local_source_tracks'), hasLength(1));
    final playback = await store.loadPlayback();
    expect(playback.index, 1);
    expect(playback.position, const Duration(seconds: 25));
    expect(playback.queue, hasLength(2));
  });
  test('selective archive imports repeated playlist entries without replacing catalog', () async {
    SharedPreferences.setMockInitialValues({
      'visual.online_lyrics': true,
      'visual.artist_biographies': true,
      'visual.bar_icon_spacing': 4.0,
      'visual.songs_controls_expanded': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final folder = await Directory.systemTemp.createTemp(
      'music-time-backup-test-',
    );
    final from = await LibraryStore.open('${folder.path}/from.db'),
        to = await LibraryStore.open('${folder.path}/to.db');
    addTearDown(() async {
      await from.close();
      await to.close();
      await folder.delete(recursive: true);
    });
    const a = Track(
      id: 'a',
      title: 'A',
      artist: 'Artist',
      localPath: 'C:/a.mp3',
    );
    const b = Track(
      id: 'b',
      title: 'B',
      artist: 'Artist',
      localPath: 'C:/b.mp3',
    );
    await from.addTracks([a, b]);
    await from.importPlaylist('Repeated', ['a', 'a', 'b']);
    await to.addTracks([
      a,
      const Track(
        id: 'existing',
        title: 'Existing',
        artist: 'Other',
        localPath: 'C:/existing.mp3',
      ),
    ]);
    final vault = MemoryVault();
    await expectLater(
      BackupArchive.create(from, prefs, vault, {'artwork'}),
      throwsFormatException,
    );
    final bytes = await BackupArchive.create(from, prefs, vault, {
      'playlists',
      'preferences',
    });
    final archive = await BackupArchive.read(bytes);
    final missing = await BackupArchive.restore(to, prefs, vault, archive, {
      'playlists',
    });
    expect(missing, 1);
    expect((await to.loadTracks()).map((t) => t.id).toSet(), {'a', 'existing'});
    final entries = await to.database.query(
      'playlist_entries',
      orderBy: 'ordinal',
    );
    expect(entries.map((e) => e['track_id']).toList(), ['a', 'a', null]);
    expect(entries.last['original_reference'], isNotEmpty);
    expect(AppData.parse(jsonEncode(archive['document']))['schema'], 16);
  });

  test('credentials require encryption and authenticate password, header and payload', () async {
    SharedPreferences.setMockInitialValues({
      'microsoft.client_id': 'public-app-id',
    });
    final prefs = await SharedPreferences.getInstance(),
        store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final vault = MemoryVault();
    await vault.write('microsoft.session', 'test-session-never-plaintext');
    await expectLater(
      BackupArchive.create(store, prefs, vault, {'providers', 'credentials'}),
      throwsFormatException,
    );
    final bytes = await BackupArchive.create(store, prefs, vault, {
      'providers',
      'credentials',
    }, password: 'a-long-test-password');
    expect(
      utf8.decode(bytes, allowMalformed: true),
      isNot(contains('test-session-never-plaintext')),
    );
    expect(BackupArchive.encrypted(bytes), isTrue);
    final decoded = await BackupArchive.read(
      bytes,
      password: 'a-long-test-password',
    );
    expect(
      decoded['secrets']['microsoft.session'],
      'test-session-never-plaintext',
    );
    await expectLater(
      BackupArchive.read(bytes, password: 'incorrect-password'),
      throwsFormatException,
    );
    final damaged = Uint8List.fromList(bytes);
    damaged[damaged.length - 20] ^= 1;
    await expectLater(
      BackupArchive.read(damaged, password: 'a-long-test-password'),
      throwsFormatException,
    );
    await vault.delete('microsoft.session');
    await BackupArchive.restore(store, prefs, vault, decoded, {
      'providers',
      'credentials',
    });
    expect(
      await vault.read('microsoft.session'),
      'test-session-never-plaintext',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('legacy JSON and metadata-only archives remain readable', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance(),
        store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([
      Track(
        id: 'a',
        title: 'A',
        artist: 'Artist',
        localPath: 'C:/a',
        cover: Uint8List.fromList([1, 2, 3]),
      ),
    ]);
    final legacy = await AppData.backup(store, prefs);
    expect(
      (await BackupArchive.read(
        Uint8List.fromList(utf8.encode(legacy)),
      ))['document']['tables']['tracks'],
      hasLength(1),
    );
    final archive = await BackupArchive.read(
      await BackupArchive.create(store, prefs, MemoryVault(), {'library'}),
    );
    expect(archive['document']['tables']['artworks'], isEmpty);
    expect(
      archive['document']['tables']['tracks'][0].containsKey('cover_hash'),
      isFalse,
    );
  });
}
