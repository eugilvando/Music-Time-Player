import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;
import 'catalog_widget_test.dart' show waitForCatalog;

import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/home_catalog.dart';

void main() {
  testWidgets(
    'consulta nova descarta resposta antiga e a UI responde durante agrupamento',
    (tester) async {
      SharedPreferences.setMockInitialValues({'visual.artist_photos': false});
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
        30000,
        (i) => Track(
          id: '$i',
          title: 'Música $i',
          artist: 'Artista',
          album: 'Grupo ${i.isEven ? 'A' : 'B'} ${i % 30}',
          localPath: i == 1 ? 'C:/fixture/1.mp3' : null,
        ),
      );
      final key = GlobalKey<CatalogBrowserState>();
      await tester.runAsync(() => store.addTracks([tracks[1]]));
      final query = ValueNotifier('Grupo A');
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => taps++,
                  child: const Text('UI livre'),
                ),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: query,
                    builder: (context, value, _) => CatalogBrowser(
                      key: key,
                      tracks: tracks,
                      favorites: const {},
                      store: store,
                      settings: settings,
                      downloads: downloads,
                      query: value,
                      initialCategory: 'albums',
                      onPlay: (_, _) async {},
                      onAction: (_, _) async {},
                      trackActions: (_) => const SizedBox(),
                      onAddSource: () {},
                      onPlaylist: (_) {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('UI livre'));
      await tester.pump();
      expect(taps, 1);
      query.value = 'Grupo B';
      await tester.pump();
      await waitForCatalog(
        tester,
        () =>
            !key.currentState!.refreshing &&
            !key.currentState!.derivingCatalog &&
            key.currentState!.filtered().isNotEmpty,
      );
      expect(
        key.currentState!.filtered().every(
          (t) => t.album.startsWith('Grupo B'),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      final prepared = key.currentState!.filtered();
      final workGeneration = key.currentState!.catalogWorkGeneration;
      await tester.runAsync(() => key.currentState!.refresh());
      await tester.pump();
      expect(identical(key.currentState!.filtered(), prepared), isTrue);
      expect(key.currentState!.catalogWorkGeneration, workGeneration);
      query.value = 'Grupo A';
      await tester.pump();
      expect(key.currentState!.derivingCatalog, isTrue);
      expect(identical(key.currentState!.filtered(), prepared), isTrue);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      await tester.tap(find.text('UI livre'));
      expect(taps, 2);
      await waitForCatalog(tester, () => !key.currentState!.derivingCatalog);
      query.value = 'Grupo B';
      await tester.pump();
      expect(key.currentState!.derivingCatalog, isFalse);
      expect(identical(key.currentState!.filtered(), prepared), isTrue);
      // A real history change must invalidate both index and derived results.
      await tester.runAsync(() async {
        await store.recordHistory(
          tracks[1].id,
          DateTime.now(),
          const Duration(seconds: 40),
        );
        await key.currentState!.refresh();
      });
      await tester.pump();
      await waitForCatalog(tester, () => !key.currentState!.derivingCatalog);
      expect(identical(key.currentState!.filtered(), prepared), isFalse);
      expect(key.currentState!.index.plays(tracks[1]), 1);
      await tester.pumpWidget(const SizedBox());
      query.dispose();
      downloads.dispose();
      providers.dispose();
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );
  test('30 mil faixas: agrupamento em isolate deixa eventos principais avançarem', () async {
    final tracks = List.generate(
      30000,
      (i) => Track(
        id: '$i',
        title: 'Canção $i',
        artist: 'Artista ${i % 300}',
        album: 'Álbum ${i % 3000}',
        genre: i.isEven ? 'Rock' : 'Pop',
        year: 1990 + i % 30,
      ),
    );
    final index = CatalogIndex(
      tracks: tracks,
      favorites: {'2'},
      offline: {'2', '4'},
      stats: {},
      sources: {},
    );
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    final clock = Stopwatch()..start();
    try {
      final result = await compute(prepareCatalog, (
        index: index,
        filters: CatalogFilters()..genre = 'Rock',
        text: 'canção',
        sort: 'title',
        descending: false,
        category: 'albums',
      ));
      expect(result.tracks.length, 15000);
      expect(result.groups, isNotEmpty);
      expect(ticks, greaterThan(0));
      debugPrint(
        'Fixture 30 mil: agrupamento isolado ${clock.elapsedMilliseconds}ms, $ticks eventos principais.',
      );
      final home = await compute(prepareHome, (
        index: index,
        tracks: tracks,
        quick: 'offline',
        limit: 20,
        lastfm: false,
      ));
      expect(home.lists['values']!.map((t) => t.id).toSet(), {'2', '4'});
      expect(home.mixes['Mix pessoal']!.map((t) => t.id).toSet(), {'2', '4'});
      expect(home.lists['history'], isEmpty);
      expect(home.albums, isEmpty);
    } finally {
      timer.cancel();
    }
  });
}
