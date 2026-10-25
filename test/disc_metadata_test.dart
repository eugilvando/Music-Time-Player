import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/catalog_query.dart';
import 'package:music_time/library/cloud_metadata.dart';
import 'package:music_time/library/local_metadata.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'cloud_metadata_test.dart' show mp3Fixture, rangeResponse;
import 'catalog_widget_test.dart' show waitForCatalog, drainCatalog;
import 'provider_auth_test.dart' show MemoryVault;

const tracks = [
  Track(
    id: 'd2',
    title: 'B third',
    artist: 'Band',
    album: 'Double album',
    discNumber: 2,
    trackNumber: 1,
    localPath: 'C:/Music/Double/CD2/01.mp3',
  ),
  Track(
    id: 'd1b',
    title: 'A second',
    artist: 'Band',
    album: 'Double album',
    discNumber: 1,
    trackNumber: 2,
    localPath: 'C:/Music/Double/CD1/02.mp3',
  ),
  Track(
    id: 'd1a',
    title: 'Z first',
    artist: 'Band',
    album: 'Double album',
    discNumber: 1,
    trackNumber: 1,
    localPath: 'C:/Music/Double/CD1/01.mp3',
  ),
];

CatalogIndex indexOf(List<Track> values, {Set<String> favorites = const {}}) =>
    CatalogIndex(
      tracks: values,
      favorites: {},
      offline: {},
      stats: {},
      sources: {},
      collectionFavorites: favorites,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('disc tags accept number/total; explicit folders are a fallback, tags take priority', () {
    expect(metadataPosition(' 2 / 3 '), 2);
    expect(metadataPosition('0/2'), isNull);
    expect(metadataPosition('two'), isNull);
    expect(discFolderNumber('/Music/Album/Disc 02'), 2);
    expect(discFolderNumber('/Music/Album/CD1 remaster'), isNull);
    const noTag = Track(
      id: 'folder',
      title: '',
      artist: 'Band',
      album: 'Double album',
      localPath: 'C:/Music/Double/CD2/01.mp3',
    );
    expect(effectiveDiscNumber(noTag), 2);
    expect(albumKey(noTag), albumKey(tracks.first));
    const conflict = Track(
      id: 'conflict',
      title: '',
      artist: 'Band',
      album: 'Double album',
      discNumber: 3,
      localPath: 'C:/Music/Double/CD2/01.mp3',
    );
    expect(effectiveDiscNumber(conflict), 3);
    expect(albumKey(conflict), isNot(albumKey(tracks.first)));
  });
  test('album identity joins explicit disc subfolders, preserves editions and old favorites', () {
    expect(tracks.map(albumKey).toSet(), hasLength(1));
    const other = Track(
      id: 'other',
      title: '',
      artist: 'Band',
      album: 'Double album',
      discNumber: 1,
      trackNumber: 1,
      localPath: 'C:/Music/Another edition/CD1/01.mp3',
    );
    expect(albumKey(other), isNot(albumKey(tracks.first)));
    final oldFavorite = 'album:${albumKey(tracks.first, combineDiscs: false)}';
    final index = indexOf(tracks, favorites: {oldFavorite});
    expect(index.groups('albums', tracks), hasLength(1));
    expect(index.groups('albums', tracks).single.tracks.map((t) => t.id), [
      'd1a',
      'd1b',
      'd2',
    ]);
    expect(tracks.every(index.isAlbumFavorite), isTrue);
    expect(
      index.query(
        CatalogFilters()..album = albumKey(tracks.first, combineDiscs: false),
      ),
      hasLength(3),
    );
    expect(index.query(CatalogFilters(), sort: 'track').map((t) => t.id), [
      'd1a',
      'd1b',
      'd2',
    ]);
    const sameFolder = [
      Track(
        id: '2',
        title: 'A',
        artist: 'Band',
        album: 'Album',
        discNumber: 2,
        trackNumber: 1,
        localPath: 'C:/Album/2.mp3',
      ),
      Track(
        id: '1',
        title: 'Z',
        artist: 'Band',
        album: 'Album',
        discNumber: 1,
        trackNumber: 1,
        localPath: 'C:/Album/1.mp3',
      ),
    ];
    expect(indexOf(sameFolder).groups('albums', sameFolder), hasLength(1));
    expect((List.of(sameFolder)..sort(compareAlbumTracks)).map((t) => t.id), [
      '1',
      '2',
    ]);
  });
  test('MP3 disc tags with spaces are read locally and through bounded cloud ranges', () async {
    final folder = await Directory.systemTemp.createTemp(
      'music-time-disc-tags-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final image = await File('assets/branding/icon.png').readAsBytes();
    final bytes = mp3Fixture(image, disc: '2 / 2');
    final file = await File('${folder.path}/song.mp3').writeAsBytes(bytes);
    expect(readLocalTracks([file.path]).single.discNumber, 2);
    final client = MockClient((request) async => rangeResponse(request, bytes));
    addTearDown(client.close);
    final tags = await CloudMetadataReader(client)
        .read(Uri.parse('https://content.test/song'), 'song.mp3');
    expect(tags!.discNumber, 2);
    expect(tags.trackNumber, 3);
    expect(await file.readAsBytes(), bytes);
  });
  test('SQLite16 migration rebuilds disc order and album identity without changing track references', () async {
    final folder = await Directory.systemTemp.createTemp(
      'music-time-disc-index-',
    );
    var store = await LibraryStore.open('${folder.path}/library.db');
    try {
      await store.addTracks(tracks);
      await store.setFavorite('d2', true);
      await store.importPlaylist('Keep references', ['d2', 'd1a', 'd2']);
      await store.database.rawUpdate(
        'UPDATE catalog_search SET disc_number=NULL,album_identity=track_id',
      );
      await store.database.execute(
        'ALTER TABLE catalog_search DROP COLUMN disc_number',
      );
      await store.database.execute(
        'ALTER TABLE catalog_search DROP COLUMN track_number',
      );
      await store.database.execute('DROP INDEX catalog_album_previous_idx');
      await store.database.execute(
        'ALTER TABLE catalog_search DROP COLUMN album_previous',
      );
      await store.database.execute('PRAGMA user_version=16');
      await store.close();
      store = await LibraryStore.open('${folder.path}/library.db');
      expect(
        (await store.database.rawQuery('PRAGMA user_version'))
            .single
            .values
            .single,
        18,
      );
      final page = await store.catalogPage(
        CatalogSqlQuery(
          filters: CatalogFilters()..album = albumKey(tracks.first),
          sort: 'track',
        ),
      );
      expect(page.tracks.map((t) => t.id), ['d1a', 'd1b', 'd2']);
      final oldFilter = await store.catalogPage(
        CatalogSqlQuery(
          filters: CatalogFilters()
            ..album = albumKey(tracks.first, combineDiscs: false),
          sort: 'track',
        ),
      );
      expect(oldFilter.tracks.map((t) => t.id), ['d1a', 'd1b', 'd2']);
      expect(await store.favoriteIds(), contains('d2'));
      expect(
        (await store.loadTracks()).map((t) => t.id).toSet(),
        tracks.map((t) => t.id).toSet(),
      );
      final refs = await store.database.query(
        'playlist_entries',
        orderBy: 'ordinal',
      );
      expect(refs.map((r) => r['track_id']), ['d2', 'd1a', 'd2']);
      expect(
        await store.database.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
    } finally {
      await store.close();
      await folder.delete(recursive: true);
    }
  });
  for (final language in ['en', 'pt']) {
    for (final view in ['detailed', 'compact', 'compact_card']) {
      testWidgets(
        'album has disc sections and plays the full ordered album in $view / $language',
        (tester) async {
          tester.view.physicalSize = const Size(1440, 1500);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({
            'visual.albums_view': view,
            'visual.artist_photos': false,
            'visual.artist_biographies': false,
          });
          final settings = AppSettings(await SharedPreferences.getInstance());
          final store = (await tester.runAsync(
            () => LibraryStore.open(':memory:'),
          ))!;
          await tester.runAsync(() => store.addTracks(tracks));
          final providers = ProviderConnections(
            settings.preferences,
            store,
            vault: MemoryVault(),
          );
          final downloads = DownloadManager(store, providers);
          List<String>? played;
          int? playedIndex;
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('pt')],
              localizationsDelegates: const [
                ...GlobalMaterialLocalizations.delegates,
                UiLanguageDelegate(),
              ],
              home: Scaffold(
                body: CatalogBrowser(
                  initialCategory: 'albums',
                  tracks: tracks,
                  favorites: const {},
                  query: '',
                  settings: settings,
                  store: store,
                  downloads: downloads,
                  onPlay: (values, at) async {
                    played = values.map((t) => t.id).toList();
                    playedIndex = at;
                  },
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
          await waitForCatalog(tester, () => !state.refreshing);
          state.openGroup(
            CatalogGroup(albumKey(tracks.first), 'Double album', tracks),
            type: 'albums',
          );
          await drainCatalog(tester);
          await waitForCatalog(
            tester,
            () => find
                .byKey(const ValueKey('album.disc.2'))
                .evaluate()
                .isNotEmpty,
          );
          expect(
            find.text(language == 'en' ? 'Disc 1' : 'Disco 1'),
            findsOneWidget,
          );
          expect(
            find.text(language == 'en' ? 'Disc 2' : 'Disco 2'),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('album.disc.1'))).dy,
            lessThan(
              tester.getTopLeft(find.byKey(const ValueKey('album.disc.2'))).dy,
            ),
          );
          await tester.ensureVisible(find.text('B third'));
          await tester.tap(find.text('B third'));
          await tester.pump();
          expect(played, ['d1a', 'd1b', 'd2']);
          expect(playedIndex, 2);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await drainCatalog(tester);
          downloads.dispose();
          providers.dispose();
          await tester.runAsync(store.close);
          settings.dispose();
        },
      );
    }
  }
}
