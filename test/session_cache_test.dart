import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/home_catalog.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/presentation/category_artwork.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/offline/download_manager.dart';

import 'catalog_widget_test.dart' show waitForCatalog, drainCatalog;
import 'provider_auth_test.dart' show MemoryVault;

void main() {
  test('Disabled Home collections are not prepared; lightweight result preserves filters', () {
    final tracks = List.generate(
      2000,
      (i) => Track(
        id: '$i',
        title: 'Demo $i',
        artist: 'Artist ${i % 40}',
        album: 'Album ${i % 100}',
      ),
    );
    final index = CatalogIndex(
      tracks: tracks,
      favorites: {'0'},
      offline: {'0'},
      stats: {},
      sources: {},
    );
    final work = (
      index: index,
      tracks: tracks,
      quick: 'offline',
      limit: 20,
      lastfm: false,
    );
    final initial = prepareHome(
      work,
      sections: {'favorite_tracks'},
      lightweight: true,
    );
    expect(initial.lists['values']!.map((t) => t.id), ['0']);
    expect(initial.mixes, isEmpty);
    final result = prepareSelectedHome((work, {'favorite_tracks'}));
    expect(result.collections.values.every((v) => v.isEmpty), isTrue);
    expect(result.mixes, isEmpty);
  });

  testWidgets('Large Home shows usable content on its first frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'visual.home_sections': ['favorite_tracks'],
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    final tracks = List.generate(
      1100,
      (i) => Track(id: '$i', title: 'Demo $i', artist: 'Artist'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            index: CatalogIndex(
              tracks: tracks,
              favorites: {'0'},
              offline: {},
              stats: {},
              sources: {},
            ),
            tracks: tracks,
            settings: settings,
            onAction: (_, _) async {},
            onPlay: (_, _) async {},
            trackActions: (_) => const SizedBox(),
            onExplore: (_, _) {},
            onAddSource: () {},
            library: const SizedBox(),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('home.skeleton')), findsNothing);
    expect(find.text('Demo 0'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 250));
    await drainCatalog(tester);
    settings.dispose();
  });

  testWidgets(
    'Catalog shell opens unfiltered Home without a full catalog sort',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'visual.home_sections': ['favorite_tracks'],
        'visual.artist_photos': false,
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
      final tracks = List.generate(
        1100,
        (i) => Track(id: '$i', title: 'Demo $i', artist: 'Artist'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogBrowser(
              memory: CatalogMemory()
                ..ready = true
                ..catalogRevision = 0,
              tracks: tracks,
              favorites: {'0'},
              store: store,
              settings: settings,
              downloads: downloads,
              query: '',
              home: true,
              onPlay: (_, _) async {},
              onAction: (_, _) async {},
              trackActions: (_) => const SizedBox(),
              onAddSource: () {},
              onPlaylist: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Demo 0'), findsWidgets);
      expect(
        tester
            .state<CatalogBrowserState>(find.byType(CatalogBrowser))
            .derivingCatalog,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 250));
      await drainCatalog(tester);
      downloads.dispose();
      providers.dispose();
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );

  testWidgets(
    'Favorites snapshot survives navigation and invalidates after a favorite changes',
    (tester) async {
      SharedPreferences.setMockInitialValues({'visual.artist_photos': false});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final tracks = [
        Track(
          id: 'a',
          title: 'Demo favorite',
          artist: 'Artist',
          album: 'Album',
        ),
      ];
      final providers = ProviderConnections(
        settings.preferences,
        store,
        vault: MemoryVault(),
      );
      final downloads = DownloadManager(store, providers);
      final memory = CatalogMemory()
        ..ready = true
        ..catalogRevision = 0;
      Widget page(Set<String> favorites) => MaterialApp(
        home: Scaffold(
          body: CatalogBrowser(
            memory: memory,
            tracks: tracks,
            favorites: favorites,
            store: store,
            settings: settings,
            downloads: downloads,
            query: '',
            initialCategory: 'favorites',
            onPlay: (_, _) async {},
            onAction: (_, _) async {},
            trackActions: (_) => const SizedBox(),
            onAddSource: () {},
            onPlaylist: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(page({'a'}));
      await waitForCatalog(tester, () => memory.favorites.isNotEmpty);
      final first = memory.favorites.values.last;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 250));
      await drainCatalog(tester);
      await tester.pumpWidget(page({'a'}));
      expect(identical(memory.favorites.values.last, first), isTrue);
      expect(
        tester
            .state<CatalogBrowserState>(find.byType(CatalogBrowser))
            .preparingFavorites,
        isFalse,
      );
      await tester.pumpWidget(page({}));
      await tester.pump();
      expect(
        tester
            .state<CatalogBrowserState>(find.byType(CatalogBrowser))
            .favoriteData
            .tracks,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 250));
      await drainCatalog(tester);
      downloads.dispose();
      providers.dispose();
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );

  testWidgets(
    'Category artwork fits small thumbnails and long names at enlarged text',
    (tester) async {
      for (final edge in [32.0, 64.0, 240.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SizedBox.square(
                  dimension: edge,
                  child: const CategoryArtwork(
                    label: 'Alternative Progressive Rock',
                    kind: 'genres',
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
