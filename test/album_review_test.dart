import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/persistence/backup_archive.dart';

import 'provider_auth_test.dart' show MemoryVault;

import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/metadata_editor.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'catalog_widget_test.dart' show drainCatalog;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LibraryStore store;
  const tracks = [
    Track(
      id: 'a',
      title: 'One',
      artist: 'Guest A',
      album: 'Album',
      albumArtist: 'Band',
      discNumber: 1,
      trackNumber: 1,
      year: 2001,
      localPath: '/album/1.mp3',
    ),
    Track(
      id: 'b',
      title: 'Two',
      artist: 'Guest B',
      album: 'Album',
      albumArtist: 'Band',
      discNumber: 2,
      trackNumber: 1,
      year: 2002,
      localPath: '/album/2.mp3',
    ),
    Track(
      id: 'other',
      title: 'Other',
      artist: 'Other',
      album: 'Other',
      localPath: '/other/3.mp3',
    ),
  ];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('album-review-');
    store = await LibraryStore.open('${root.path}/test.db');
    await store.addTracks(tracks);
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  testWidgets(
    'open album details follow metadata changes without losing the selected tracks',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final providers = ProviderConnections(
        settings.preferences,
        store,
        vault: MemoryVault(),
      );
      final downloads = DownloadManager(store, providers);
      Widget page(List<Track> values, int revision) => MaterialApp(
        home: Scaffold(
          body: CatalogBrowser(
            initialCategory: 'albums',
            revision: revision,
            tracks: values,
            favorites: {},
            store: store,
            settings: settings,
            downloads: downloads,
            query: '',
            onPlay: (_, _) async {},
            onAction: (_, _) async {},
            trackActions: (_) => const Icon(Icons.more_horiz),
            onAddSource: () {},
            onPlaylist: (_) {},
          ),
        ),
      );
      await tester.runAsync(() => store.setUserMetadata(['b'], {'year': 2001}));
      final initial = (await tester.runAsync(
        () => store.loadTracks(includeCovers: false),
      ))!;
      await tester.pumpWidget(page(initial, 0));
      final state = tester.state<CatalogBrowserState>(
        find.byType(CatalogBrowser),
      );
      state.openTrackCollection(tracks.first, true);
      await tester.pump();
      await tester.runAsync(
        () => store.setUserMetadata(
          ['a', 'b'],
          {'album': 'Revised', 'year': 2005},
        ),
      );
      final updated = (await tester.runAsync(
        () => store.loadTracks(includeCovers: false),
      ))!;
      await tester.pumpWidget(page(updated, 1));
      expect(state.selectedGroup!.name, 'Revised');
      expect(state.selectedGroup!.tracks.map((t) => t.id).toSet(), {'a', 'b'});
      expect(state.selectedGroup!.tracks.every((t) => t.year == 2005), isTrue);
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      downloads.dispose();
      providers.dispose();
      settings.dispose();
    },
  );

  test('v17 upgrade preserves catalog; a legacy cleanup cannot remove manually referenced artwork', () async {
    await store.database.execute('DROP TRIGGER protect_manual_album_artwork');
    await store.database.execute('PRAGMA user_version=17');
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5WQAAAAASUVORK5CYII=',
    );
    await store.setCatalogAlbumCover(['a'], png);
    await store.close();
    store = await LibraryStore.open('${root.path}/test.db');
    expect(
      (await store.database.rawQuery('PRAGMA user_version'))
          .single['user_version'],
      18,
    );
    expect(
      (await store.loadTracks(includeCovers: false)).map((t) => t.id).toSet(),
      {'a', 'b', 'other'},
    );
    await expectLater(
      store.database.execute(
        'DELETE FROM artworks WHERE NOT EXISTS(SELECT 1 FROM tracks WHERE cover_hash=artworks.hash)',
      ),
      throwsA(anything),
    );
    expect(await store.trackCover('a'), png);
    await store.artwork.optimize(compact: false);
    expect(await store.trackCover('a'), png);
  });

  test('manual cover round-trips in artwork backup and restoring the source image keeps source bytes', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5WQAAAAASUVORK5CYII=',
    );
    final source = Uint8List.fromList([...png, 0]);
    await store.addTracks([
      Track(
        id: 'a',
        title: 'One',
        artist: 'Band',
        album: 'Album',
        localPath: '/album/1.mp3',
        cover: source,
      ),
    ]);
    await store.setCatalogAlbumCover(['a', 'b'], png);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final backup = await BackupArchive.read(
      await BackupArchive.create(store, prefs, MemoryVault(), {
        'library',
        'artwork',
      }),
    );
    final restored = await LibraryStore.open('${root.path}/restored.db');
    try {
      await BackupArchive.restore(restored, prefs, MemoryVault(), backup, {
        'library',
        'artwork',
      });
      expect(await restored.trackCover('a'), png);
      expect(await restored.trackCover('b'), png);
      await restored.setCatalogAlbumCover(['a'], null);
      expect(await restored.trackCover('a'), source);
    } finally {
      await restored.close();
    }
  });

  testWidgets(
    'album review changes only checked shared fields and keeps individual disc/track metadata',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  editAlbumMetadata(context, store, tracks.take(2).toList()),
              child: const Text('review'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('review'));
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Ano',
      );
      await tester.enterText(field, '2020');
      await tester.ensureVisible(find.text('Salvar no catálogo'));
      await tester.tap(find.text('Salvar no catálogo'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final values = {
          for (final t in await store.loadTracks(includeCovers: false)) t.id: t,
        };
        expect(values['a']!.year, 2020);
        expect(values['b']!.year, 2020);
        expect(values['a']!.title, 'One');
        expect(values['b']!.artist, 'Guest B');
        expect(values['a']!.discNumber, 1);
        expect(values['b']!.discNumber, 2);
        expect(values['b']!.trackNumber, 1);
        expect(values['other']!.year, isNull);
      });
      await tester.pump(const Duration(seconds: 2));
    },
  );

  test('shared album artwork survives source sync, metadata reset, optimization and reopening; reset restores source cover', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5WQAAAAASUVORK5CYII=',
    );
    await store.setCatalogAlbumCover(['a', 'b'], png);
    expect(await store.trackCover('a'), png);
    expect(await store.trackCover('b'), png);
    expect(await store.trackCover('other'), isNull);
    expect(
      (await store.loadTracks(includeCovers: false))
          .where((t) => t.hasArtwork)
          .map((t) => t.id)
          .toSet(),
      {'a', 'b'},
    );
    await store.addTracks(tracks);
    await store.setUserMetadata(['a'], {}, clear: true);
    await store.artwork.optimize(compact: false);
    expect((await store.database.query('artworks')).length, 1);
    expect(await store.trackCover('a'), png);
    await store.close();
    store = await LibraryStore.open('${root.path}/test.db');
    expect(await store.trackCover('b'), png);
    await store.setCatalogAlbumCover(['a', 'b'], null);
    expect(await store.trackCover('a'), isNull);
    expect(
      (await store.loadTracks(includeCovers: false)).any((t) => t.hasArtwork),
      isFalse,
    );
  });
}
