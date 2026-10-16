import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/presentation/compact_media_card.dart';
import 'package:music_time/presentation/ui_language.dart';

import 'catalog_widget_test.dart' show waitForCatalog, drainCatalog;
import 'provider_auth_test.dart' show MemoryVault;

import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:music_time/application/player_controller.dart';

import 'design_test.dart' show demoWave;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/smart_play.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/persistence/library_store.dart';

import 'offline_test.dart' show Resolver;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    ),
  );
  testWidgets(
    'Artist discography is chronological and album metadata is conditional',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'visual.artist_photos': false,
        'visual.artist_biographies': false,
        'visual.albums_view': 'compact_card',
        'visual.offline_only': true,
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final providers = ProviderConnections(
        settings.preferences,
        store,
        vault: MemoryVault(),
      );
      final downloads = DownloadManager(store, providers);
      final songs = [
        const Track(
          id: 'new',
          title: 'New track',
          artist: 'Band',
          album: 'New album',
          year: 2024,
          genre: 'Rock',
          localPath: 'C:/new.mp3',
        ),
        const Track(
          id: 'old',
          title: 'Old track',
          artist: 'Band',
          album: 'Old album',
          year: 1990,
          localPath: 'C:/old.mp3',
        ),
        const Track(
          id: 'unknown',
          title: 'Unknown track',
          artist: 'Band',
          album: 'Unknown album',
          localPath: 'C:/unknown.mp3',
        ),
      ];
      await tester.runAsync(() => store.addTracks(songs));
      // No offline filtering here: fixtures use metadata only, without personal files.
      await settings.updateVisual('offline_only', false);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [UiLanguageDelegate()],
          home: Scaffold(
            body: CatalogBrowser(
              tracks: songs,
              favorites: {},
              store: store,
              settings: settings,
              downloads: downloads,
              query: '',
              initialCategory: 'artists',
              onPlay: (_, _) async {},
              onAction: (_, _) async {},
              trackActions: (_) => const Icon(Icons.more_horiz),
              onAddSource: () {},
              onPlaylist: (_) {},
            ),
          ),
        ),
      );
      final state = tester.state<CatalogBrowserState>(
        find.byType(CatalogBrowser),
      );
      await drainCatalog(tester);
      await waitForCatalog(tester, () => !state.refreshing);
      state.openGroup(CatalogGroup('Band', 'Band', songs), type: 'artists');
      await drainCatalog(tester);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<CompactMediaCard>(find.byType(CompactMediaCard))
            .map((c) => c.title),
        ['Old album', 'New album', 'Unknown album'],
      );
      state.openGroup(
        CatalogGroup('New album', 'New album', [songs.first]),
        type: 'albums',
      );
      await drainCatalog(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('album.releaseYear')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('album.releaseYear')))
            .data,
        '2024',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('album.genres'))).data,
        'Rock',
      );
      state.openGroup(
        CatalogGroup('Unknown album', 'Unknown album', [songs.last]),
        type: 'albums',
      );
      await drainCatalog(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('album.releaseYear')), findsNothing);
      expect(find.byKey(const ValueKey('album.genres')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      downloads.dispose();
      providers.dispose();
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );
  test('Discography orders release years first and missing years last', () {
    CatalogGroup album(String id, int? year) => CatalogGroup(id, id, [
      Track(id: id, title: id, artist: 'A', year: year),
    ]);
    final albums = [
      album('missing', null),
      album('new', 2024),
      album('old', 1990),
      album('same', 2024),
      album('invalid', 0),
    ];
    expect(chronologicalAlbums(albums).map((a) => a.id), [
      'old',
      'new',
      'same',
      'missing',
      'invalid',
    ]);
    expect(albums.first.id, 'missing');
    expect(albumReleaseYear(albums.first), isNull);
  });
  test('Item mix ranks similar artists, deduplicates and excludes unrelated or inaccessible tracks', () {
    const seed = Track(id: 'seed', title: 'Seed', artist: 'A', genre: 'Rock');
    const similar = Track(id: 'similar', title: 'Related', artist: 'B');
    const same = Track(id: 'same', title: 'Same artist', artist: 'A');
    const genre = Track(
      id: 'genre',
      title: 'Genre',
      artist: 'C',
      genre: 'Rock',
    );
    const unrelated = Track(
      id: 'other',
      title: 'Other',
      artist: 'D',
      genre: 'Jazz',
    );
    const unavailable = Track(
      id: 'missing',
      title: 'Missing',
      artist: 'A',
      available: false,
    );
    final values = itemMix(
      [seed, same, genre, similar, similar, unrelated, unavailable],
      [seed],
      similarArtists: {'b'},
      random: Random(1),
    );
    expect(values.map((t) => t.id), ['seed', 'similar', 'same', 'genre']);
    expect(itemMix([seed, unrelated], [seed]), isEmpty);
    expect(
      itemMix(
        [seed, same, genre],
        [seed],
        offlineOnly: true,
        offline: {'seed', 'genre'},
      ).map((t) => t.id),
      ['seed', 'genre'],
    );
    expect(
      itemMix([seed, same], [seed], offlineOnly: true, offline: {'same'}),
      isEmpty,
    );
  });
  test(
    'Item mix starts a playback queue without creating any playlist',
    () async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      final dir = await Directory.systemTemp.createTemp('music-time-mix-');
      addTearDown(() => dir.delete(recursive: true));
      final audio = await demoWave(dir);
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final a = Track(
        id: 'a',
        title: 'A',
        artist: 'Band',
        localPath: audio.path,
      );
      final b = Track(
        id: 'b',
        title: 'B',
        artist: 'Band',
        localPath: audio.path,
      );
      await store.addTracks([a, b]);
      final player = PlayerController();
      try {
        final mix = prepareItemMix(ItemMixWork([a, b], [a, b], {}, {}, false));
        await player.playQueue(mix, 0);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(player.queue.map((t) => t.id), ['a', 'b']);
        expect(player.current?.id, 'a');
        expect(player.playing, true);
        expect(player.error, isNull);
        expect(await store.playlists(), isEmpty);
      } finally {
        player.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    },
  );
  test('Removing one permanent copy clears its shared memberships and preserves other files and catalogue', () async {
    final dir = await Directory.systemTemp.createTemp('music-time-individual-');
    addTearDown(() => dir.delete(recursive: true));
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final manager = DownloadManager(
      store,
      Resolver(),
      directory: () async => dir,
    );
    addTearDown(manager.dispose);
    const a = Track(
      id: 'a',
      title: 'A',
      artist: 'Band',
      driveId: 'd',
      itemId: 'a',
    );
    const b = Track(
      id: 'b',
      title: 'B',
      artist: 'Band',
      driveId: 'd',
      itemId: 'b',
    );
    await store.addTracks([a, b]);
    await store.selectOffline('playlist', [a, b]);
    await store.selectOffline('favorite', [a]);
    final file = await File(
      '${dir.path}/${sha256.convert(utf8.encode(a.id))}.audio',
    ).writeAsBytes([1, 2]);
    final other = await File(
      '${dir.path}/${sha256.convert(utf8.encode(b.id))}.audio',
    ).writeAsBytes([3]);
    final cache = await File('${dir.path}/cache.audio').writeAsBytes([4]);
    await store.updateDownload('a', 'complete', path: file.path);
    await store.updateDownload('b', 'complete', path: other.path);
    manager.current = 'a';
    await expectLater(manager.removePermanentTrack('a'), throwsStateError);
    expect(await file.exists(), true);
    manager.current = null;
    await manager.removePermanentTrack('a');
    expect(await file.exists(), false);
    expect(await other.exists(), true);
    expect(await cache.exists(), true);
    expect(await store.offlineFile('a'), isNull);
    expect(await store.offlineFile('b'), isNotNull);
    expect(
      (await store.database.query(
        'offline_memberships',
        where: 'track_id=?',
        whereArgs: ['a'],
      )),
      isEmpty,
    );
    expect((await store.loadTracks()).length, 2);
    await store.selectOffline('again', [a]);
    expect(
      (await store.downloadTasks()).firstWhere((r) => r['id'] == 'a')['status'],
      'pending',
    );
  });
  test('Local originals survive individual removal and unexpected remote paths are rejected', () async {
    final dir = await Directory.systemTemp.createTemp('music-time-original-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/original.mp3').writeAsBytes([1]);
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final manager = DownloadManager(
      store,
      Resolver(),
      directory: () async => dir,
    );
    addTearDown(manager.dispose);
    final local = Track(
      id: 'local',
      title: 'Local',
      artist: 'A',
      localPath: file.path,
    );
    const remote = Track(
      id: 'remote',
      title: 'Remote',
      artist: 'A',
      driveId: 'd',
      itemId: 'r',
    );
    await store.addTracks([local, remote]);
    await store.selectOffline('both', [local, remote]);
    await store.updateDownload('local', 'complete', path: file.path);
    await store.updateDownload('remote', 'complete', path: file.path);
    await manager.removePermanentTrack('local');
    expect(await file.exists(), true);
    expect(await store.offlineFile('local'), isNull);
    await expectLater(manager.removePermanentTrack('remote'), throwsStateError);
    expect(await file.exists(), true);
    expect(await store.offlineFile('remote'), isNotNull);
  });
}
