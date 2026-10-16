import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;
import 'catalog_widget_test.dart' show waitForCatalog;

void main() {
  testWidgets(
    'favoritos reutiliza primeira página e reconstruções não reiniciam índices',
    (tester) async {
      SharedPreferences.setMockInitialValues({'visual.artist_photos': false});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      const track = Track(
        id: 'f',
        title: 'Favorita retida',
        artist: 'Artist',
        localPath: 'C:/fixture/favorite.mp3',
      );
      await tester.runAsync(() async {
        await store.addTracks([track]);
        await store.setFavorite(track.id, true);
      });
      final provider = ProviderConnections(
        settings.preferences,
        store,
        vault: MemoryVault(),
      );
      final downloads = DownloadManager(store, provider);
      final memory = CatalogMemory();
      final key = GlobalKey<CatalogBrowserState>();
      Widget build() => MaterialApp(
        home: Scaffold(
          body: CatalogBrowser(
            key: key,
            memory: memory,
            tracks: const [track],
            favorites: const {'f'},
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
      await tester.pumpWidget(build());
      await waitForCatalog(
        tester,
        () =>
            find.text('Favorita retida').evaluate().isNotEmpty &&
            !key.currentState!.refreshing &&
            !key.currentState!.pageLoading,
      );
      final generation = key.currentState!.generation;
      final index = key.currentState!.index;
      final revision = memory.revision;
      await tester.runAsync(() => key.currentState!.refresh());
      await tester.pump();
      expect(memory.revision, revision);
      expect(identical(key.currentState!.index, index), isTrue);
      expect(key.currentState!.pageLoading, isFalse);
      await tester.pumpWidget(build());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(key.currentState!.generation, generation + 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(build());
      expect(find.text('Favorita retida'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(key.currentState!.pageHasData, isTrue);
      expect(identical(key.currentState!.index, index), isTrue);
      await waitForCatalog(tester, () => !key.currentState!.pageLoading);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      downloads.dispose();
      provider.dispose();
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );
}
