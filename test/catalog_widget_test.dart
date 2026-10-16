import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/presentation/cover_scope.dart';
import 'package:music_time/presentation/now_playing_artwork.dart';

import 'provider_auth_test.dart' show MemoryVault;

Future<void> waitForCatalog(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    ready(),
    isTrue,
    reason:
        'A consulta do catálogo não concluiu em 5 segundos. ${find.byType(CatalogBrowser).evaluate().map((element) {
          final state = tester.state<CatalogBrowserState>(find.byWidget(element.widget));
          return "${state.category}: offset=${state.pageOffset}, loaded=${state.loadedOffset}, total=${state.pageTotal}, tracks=${state.pageTracks.length}, loading=${state.pageLoading}, error=${state.pageError}";
        }).join('; ')}',
  );
}

// SQLite callbacks can complete in the fake widget zone after a real IO turn.
// Drain both zones before closing a fixture database with pending page queries.
Future<void> drainCatalog(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('capa do catálogo sem BLOB é carregada sob demanda', (
    tester,
  ) async {
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j0ioAAAAASUVORK5CYII=',
    );
    await tester.runAsync(
      () => store.addTracks([
        Track(
          id: 'art',
          title: 'Faixa',
          artist: 'Artista',
          localPath: 'C:/art.mp3',
          cover: bytes,
        ),
      ]),
    );
    final track = (await tester.runAsync(
      () => store.loadTracks(includeCovers: false),
    ))!.single;
    expect(track.cover, isNull);
    expect(track.hasArtwork, isTrue);
    final cache = CatalogCoverCache(store);
    await tester.pumpWidget(
      MaterialApp(
        home: CatalogCoverScope(
          cache: cache,
          revision: 0,
          child: SizedBox.square(
            dimension: 50,
            child: TrackCover(track: track),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await waitForCatalog(
      tester,
      () => find.byType(Image).evaluate().isNotEmpty,
    );
    expect(find.byType(Image), findsOneWidget);
    expect(cache.values['art'], bytes);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.close);
  });
  testWidgets(
    'paginação mantém seleção entre páginas e reproduz resultado completo',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'visual.artist_photos': false,
        'visual.catalog_page_size': '50',
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final values = List.generate(
        75,
        (i) => Track(
          id: '$i',
          title: 'Faixa ${i.toString().padLeft(2, '0')}',
          artist: 'Artista',
          localPath: 'C:/music/$i.mp3',
        ),
      );
      await tester.runAsync(() => store.addTracks(values));
      final providers = ProviderConnections(
        settings.preferences,
        store,
        vault: MemoryVault(),
      );
      final downloads = DownloadManager(store, providers);
      int played = 0, start = -1;
      final revision = ValueNotifier(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: revision,
              builder: (context, value, _) => CatalogBrowser(
                revision: value,
                tracks: values,
                favorites: {},
                store: store,
                settings: settings,
                downloads: downloads,
                query: '',
                onPlay: (tracks, index) async {
                  played = tracks.length;
                  start = index;
                },
                onAction: (_, tracks) async {},
                trackActions: (_) => const Icon(Icons.more_horiz),
                onAddSource: () {},
                onPlaylist: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await waitForCatalog(
        tester,
        () => find.text('1–50 de 75').evaluate().isNotEmpty,
      );
      expect(find.text('1–50 de 75'), findsOneWidget);
      await tester.tap(find.byTooltip('Próxima página'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await waitForCatalog(
        tester,
        () => find.text('51–75 de 75').evaluate().isNotEmpty,
      );
      expect(find.text('51–75 de 75'), findsOneWidget);
      await tester.tap(find.text('Faixa 50'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await waitForCatalog(tester, () => played == 75);
      expect(played, 75);
      expect(start, 50);
      await tester.tap(find.text('Selecionar todas'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await waitForCatalog(
        tester,
        () => find.text('75 músicas · 75 selecionadas').evaluate().isNotEmpty,
      );
      expect(find.text('75 músicas · 75 selecionadas'), findsOneWidget);
      revision.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await waitForCatalog(
        tester,
        () => find.text('51–75 de 75').evaluate().isNotEmpty,
      );
      expect(find.text('51–75 de 75'), findsOneWidget);
      expect(find.text('75 músicas · 75 selecionadas'), findsOneWidget);
      await tester.tap(find.byTooltip('Página anterior'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await waitForCatalog(
        tester,
        () => find.text('75 músicas · 75 selecionadas').evaluate().isNotEmpty,
      );
      expect(find.text('75 músicas · 75 selecionadas'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      downloads.dispose();
      revision.dispose();
      providers.dispose();
      settings.dispose();
      await drainCatalog(tester);
      await tester.runAsync(store.close);
    },
  );
  testWidgets('categorias, seleção em lote e lista detalhada adaptam janela', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'visual.artist_photos': false});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final values = [
      Track(
        id: 'a',
        title: 'Canção',
        artist: 'Artista',
        album: 'Álbum',
        albumArtist: 'Álbum artista',
        genres: ['Jazz'],
        year: 1999,
        localPath: 'C:/music/a.mp3',
        addedAt: DateTime.utc(2026, 10, 13),
      ),
      const Track(
        id: 'b',
        title: 'Outra',
        artist: 'Earth, Wind & Fire',
        localPath: 'C:/music/b.mp3',
      ),
    ];
    await tester.runAsync(() => store.addTracks(values));
    final providers = ProviderConnections(
      settings.preferences,
      store,
      vault: MemoryVault(),
    );
    final downloads = DownloadManager(store, providers);
    final actions = <String>[];
    final search = ValueNotifier('');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: Listenable.merge([settings, search]),
            builder: (context, _) => CatalogBrowser(
              tracks: values,
              favorites: {},
              store: store,
              settings: settings,
              downloads: downloads,
              query: search.value,
              onPlay: (t, i) async {},
              onAction: (a, t) async {
                actions.add('$a:${t.length}');
              },
              trackActions: (_) => const Icon(Icons.more_horiz),
              onAddSource: () {},
              onPlaylist: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Filtros'), findsNothing);
    expect(find.byType(DropdownButton<String>), findsNothing);
    final toggle = find.byKey(const ValueKey('catalog.controls.toggle'));
    final controlsRight = tester.getTopRight(toggle).dx;
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.getTopRight(toggle).dx, controlsRight);
    expect(find.byType(DropdownButton<String>), findsWidgets);
    search.value = 'Canção';
    await tester.pump();
    expect(find.text('Filtros'), findsNothing);
    search.value = '';
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await waitForCatalog(
      tester,
      () =>
          find.text('1–2 de 2').evaluate().isNotEmpty &&
          !tester
              .state<CatalogBrowserState>(find.byType(CatalogBrowser))
              .pageLoading,
    );
    await tester.tap(find.text('Selecionar todas'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await waitForCatalog(
      tester,
      () => find.text('2 músicas · 2 selecionadas').evaluate().isNotEmpty,
    );
    expect(find.text('2 músicas · 2 selecionadas'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Ações da coleção'));
    await tester.tap(find.byTooltip('Ações da coleção'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar à fila'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await waitForCatalog(tester, () => actions.isNotEmpty);
    await waitForCatalog(
      tester,
      () =>
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    expect(actions, ['queue:2']);
    await settings.updateVisual('songs_view', 'detailed');
    await tester.pump();
    expect(find.text('Título'), findsWidgets);
    for (final size in [
      const Size(480, 600),
      const Size(800, 600),
      const Size(1280, 720),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    for (final type in [
      'albums',
      'artists',
      'albumArtists',
      'genres',
      'years',
      'decades',
      'folders',
      'favorites',
      'offline',
      'playlists',
    ]) {
      final dropdown = find.byType(DropdownButton<String>).first;
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(catalogCategories[type]!).last);
      await tester.tap(find.text(catalogCategories[type]!).last);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    downloads.dispose();
    providers.dispose();
    settings.dispose();
    await tester.runAsync(store.close);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets(
    'album and artist links open detail pages and preserve contextual back navigation',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'visual.artist_photos': false,
        'visual.artist_biographies': false,
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      const values = [
        Track(
          id: 'a',
          title: 'Song A',
          artist: 'Artist A',
          albumArtist: 'Artist A',
          album: 'Album A',
          localPath: 'C:/a/song.mp3',
        ),
        Track(
          id: 'b',
          title: 'Song B',
          artist: 'Artist A',
          albumArtist: 'Artist A',
          album: 'Album B',
          localPath: 'C:/b/song.mp3',
        ),
      ];
      await tester.runAsync(() => store.addTracks(values));
      final providers = ProviderConnections(
        settings.preferences,
        store,
        vault: MemoryVault(),
      );
      final downloads = DownloadManager(store, providers);
      final key = GlobalKey<CatalogBrowserState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: settings,
              builder: (context, _) => CatalogBrowser(
                key: key,
                tracks: values,
                favorites: {},
                store: store,
                settings: settings,
                downloads: downloads,
                initialCategory: 'albums',
                query: '',
                onPlay: (_, _) async {},
                onAction: (_, _) async {},
                trackActions: (_) => const Icon(Icons.more_horiz),
                onAddSource: () {},
                onPlaylist: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await tester.pump();
      await waitForCatalog(
        tester,
        () =>
            find.text('Album A').evaluate().isNotEmpty &&
            !key.currentState!.refreshing,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album A').first);
      await tester.pumpAndSettle();
      expect(key.currentState!.category, 'albums');
      await tester.tap(find.widgetWithText(TextButton, 'Artist A').first);
      await tester.pumpAndSettle();
      expect(key.currentState!.category, 'albumArtists');
      expect(find.text('Discography'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album B').first);
      await tester.pumpAndSettle();
      expect(key.currentState!.category, 'albums');
      expect(key.currentState!.selectedGroup!.name, 'Album B');
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(key.currentState!.category, 'albumArtists');
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(key.currentState!.selectedGroup!.name, 'Album A');
      for (final width in [480.0, 800.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox());
      downloads.dispose();
      providers.dispose();
      settings.dispose();
      await drainCatalog(tester);
      await tester.runAsync(store.close);
    },
  );
  testWidgets('personalização do início persiste ordem e visibilidade', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => customizeHome(context, settings),
              child: const Text('Personalizar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Personalizar'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('mixes')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(
      settings.preferences.getStringList('visual.home_sections'),
      isNot(contains('mixes')),
    );
    expect(settings.visualNumber('home_count', 12), 12);
    expect(tester.takeException(), isNull);
  });
}
