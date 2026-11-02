import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/presentation/compact_media_card.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;
import 'catalog_widget_test.dart' show drainCatalog;

const albumTracks = [
  Track(
    id: 'c',
    title: 'C',
    artist: 'Band',
    album: 'Test Album',
    discNumber: 2,
    trackNumber: 1,
  ),
  Track(
    id: 'b',
    title: 'B',
    artist: 'Band',
    album: 'Test Album',
    discNumber: 1,
    trackNumber: 2,
  ),
  Track(
    id: 'a',
    title: 'A',
    artist: 'Band',
    album: 'Test Album',
    discNumber: 1,
    trackNumber: 1,
  ),
];
void main() {
  for (final mode in ['grid', 'compact', 'compact_card', 'detailed']) {
    testWidgets('catalog album drag preserves disc order: $mode', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'visual.albums_grid': mode == 'grid',
        'visual.albums_view': mode == 'grid' ? 'compact' : mode,
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
      List<Track>? accepted;
      final memory = CatalogMemory()
        ..ready = true
        ..catalogRevision = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: CatalogBrowser(
                    initialCategory: 'albums',
                    tracks: albumTracks,
                    favorites: {},
                    store: store,
                    settings: settings,
                    downloads: downloads,
                    query: '',
                    memory: memory,
                    onPlay: (_, _) async {},
                    onAction: (_, _) async {},
                    trackActions: (_) => const Icon(Icons.more_horiz),
                    onAddSource: () {},
                    onPlaylist: (_) {},
                  ),
                ),
                DragTarget<List<Track>>(
                  onAcceptWithDetails: (d) => accepted = d.data,
                  builder: (_, _, _) => const SizedBox(
                    height: 70,
                    width: 300,
                    child: Text('Queue target'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await drainCatalog(tester);
      await tester.pumpAndSettle();
      final source = tester.getCenter(find.text('Test Album').first),
          target = tester.getCenter(find.text('Queue target'));
      await tester.dragFrom(source, target - source);
      await tester.pumpAndSettle();
      expect(accepted!.map((t) => t.id), ['a', 'b', 'c']);
      expect(albumTracks.map((t) => t.id), ['c', 'b', 'a']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      downloads.dispose();
      providers.dispose();
      settings.dispose();
      await tester.runAsync(store.close);
    });
  }
  for (final mode in ['detailed', 'compact_cards_list']) {
    testWidgets('home album drag retains layout and tap: $mode', (
      tester,
    ) async {
      var tapped = 0;
      List<Track>? accepted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                HomeCardLayout(
                  mode: mode,
                  children: [
                    CompactMediaCard(
                      artwork: const Icon(Icons.album),
                      title: 'Album',
                      subtitle: 'Band',
                      actions: const SizedBox(),
                      onTap: () => tapped++,
                      dragTracks: albumTracks,
                    ),
                  ],
                ),
                DragTarget<List<Track>>(
                  onAcceptWithDetails: (d) => accepted = d.data,
                  builder: (_, _, _) =>
                      const SizedBox(height: 100, child: Text('Queue')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Album'));
      expect(tapped, 1);
      final source = tester.getCenter(find.text('Album')),
          target = tester.getCenter(find.text('Queue'));
      await tester.dragFrom(source, target - source);
      await tester.pumpAndSettle();
      expect(accepted!.map((t) => t.id), ['a', 'b', 'c']);
      expect(tapped, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
