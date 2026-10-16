import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/metadata_editor.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/offline/download_manager.dart';

import 'provider_auth_test.dart' show MemoryVault;

import 'catalog_widget_test.dart' show waitForCatalog;

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  testWidgets('filtro inclui fonte e modo offline oculta música só na nuvem', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'visual.artist_photos': false});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('music-time-offline-view-'),
    ))!;
    final file = (await tester.runAsync(
      () => File('${dir.path}/local.mp3').writeAsBytes([1, 2, 3]),
    ))!;
    final tracks = [
      Track(
        id: 'local',
        title: 'Presente',
        artist: 'Autor',
        album: 'Álbum local',
        localPath: file.path,
      ),
      const Track(
        id: 'cloud',
        title: 'Somente nuvem',
        artist: 'Nuvem',
        album: 'Álbum nuvem',
        driveId: 'drive',
        itemId: 'cloud',
      ),
    ];
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    await tester.runAsync(() => store.addTracks(tracks));
    final providers = ProviderConnections(
      settings.preferences,
      store,
      vault: MemoryVault(),
    );
    final downloads = DownloadManager(store, providers);
    var disposed = false;
    Future<void> cleanup() async {
      if (disposed) {
        return;
      }
      disposed = true;
      await tester.pumpWidget(const SizedBox());
      downloads.dispose();
      providers.dispose();
      settings.dispose();
      await tester.runAsync(store.close);
      await tester.runAsync(() => dir.delete(recursive: true));
    }

    addTearDown(cleanup);
    final key = GlobalKey<CatalogBrowserState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: settings,
            builder: (context, _) => CatalogBrowser(
              key: key,
              tracks: tracks,
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
        ),
      ),
    );
    await waitForCatalog(
      tester,
      () => find.text('1–2 de 2').evaluate().isNotEmpty,
    );
    expect(find.byType(Checkbox), findsNothing);
    final filters = key.currentState!.editFilters();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Fonte'), findsOneWidget);
    expect(find.text('Conta'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 350));
    await filters;
    await settings.updateVisual('offline_only', true);
    await tester.pump();
    await waitForCatalog(
      tester,
      () => find.text('1–1 de 1').evaluate().isNotEmpty,
    );
    expect(find.text('Presente'), findsOneWidget);
    expect(find.text('Somente nuvem'), findsNothing);
    key.currentState!.chooseCategory('albums');
    await tester.pump();
    await waitForCatalog(
      tester,
      () => find.text('Álbum local').evaluate().isNotEmpty,
    );
    expect(find.text('Álbum nuvem'), findsNothing);
    key.currentState!.chooseCategory('artists');
    await tester.pump();
    await waitForCatalog(
      tester,
      () => find.text('Autor').evaluate().isNotEmpty,
    );
    expect(find.text('Nuvem'), findsNothing);
    await cleanup();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'editor altera catálogo, preserva nome com separador e restaura fonte',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      const track = Track(
        id: '1',
        title: 'Sem tags',
        artist: 'Banda; Nome',
        localPath: 'C:/original.mp3',
      );
      await tester.runAsync(() => store.addTracks([track]));
      var changed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  changed = await editCatalogMetadata(context, store, track);
                },
                child: const Text('Editar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Título'), 'Título corrigido');
      await tester.ensureVisible(find.text('Salvar no catálogo'));
      await tester.tap(find.text('Salvar no catálogo'));
      await waitForCatalog(tester, () => changed);
      final result = (await tester.runAsync(() => store.loadTracks()))!.single;
      expect(result.title, 'Título corrigido');
      expect(result.artistNames, ['Banda', 'Nome']);
      expect(result.localPath, track.localPath);
      changed = false;
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Restaurar tags originais'));
      await tester.tap(find.text('Restaurar tags originais'));
      await waitForCatalog(tester, () => changed);
      expect(
        (await tester.runAsync(() => store.loadTracks()))!.single.title,
        'Sem tags',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(store.close);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mesclagem de álbum exige destino e confirmação e mantém arquivos',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      const source = Track(
        id: '1',
        title: 'A',
        artist: 'Autor',
        album: 'Sem album',
        localPath: 'C:/original/a.mp3',
      );
      const target = Track(
        id: '2',
        title: 'B',
        artist: 'Autor',
        album: 'Destino',
        albumArtist: 'Autor',
        year: 2020,
        localPath: 'C:/original/b.mp3',
      );
      await tester.runAsync(() => store.addTracks([source, target]));
      var changed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  changed = await mergeCatalogCollection(context, store, [
                    source,
                  ], album: true);
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await waitForCatalog(
        tester,
        () => find.text('Destino').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Destino'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar mesclagem no catálogo?'), findsOneWidget);
      expect(changed, false);
      await tester.tap(find.text('Mesclar'));
      await waitForCatalog(tester, () => changed);
      final result = (await tester.runAsync(() => store.loadTracks()))!;
      expect(result.map((t) => t.album), ['Destino', 'Destino']);
      expect(result[0].albumId, result[1].albumId);
      expect(result.map((t) => t.localPath), [
        source.localPath,
        target.localPath,
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(store.close);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'configuração do início aplica quantidade por seção imediatamente',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'visual.home_modes': '{"continue":"wide"}',
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => customizeHome(context, settings),
                child: const Text('Configurar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Configurar'));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(
        find.descendant(
          of: find.byKey(const ValueKey('mixes')),
          matching: find.byType(Slider),
        ),
      );
      slider.onChanged!(17);
      await tester.pumpAndSettle();
      expect(settings.visualNumber('home_count_mixes', 0), 17);
      expect(settings.visualNumber('home_count_recent', 0), 0);
      expect(find.text('Quantidade de itens: 17'), findsOneWidget);
      await tester.tap(find.byTooltip('Fechar').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
