import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/settings_dialog.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/offline/download_manager.dart';

import 'provider_auth_test.dart' show MemoryVault;
import 'catalog_widget_test.dart' show waitForCatalog;

void main() {
  setUp(
    () =>
        SharedPreferences.setMockInitialValues({'visual.artist_photos': false}),
  );
  testWidgets('idioma muda imediatamente, persiste e mantém categorias', (
    tester,
  ) async {
    final settings = AppSettings(await SharedPreferences.getInstance());
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: settings,
        builder: (context, _) => MaterialApp(
          locale: Locale(settings.language),
          supportedLocales: const [Locale('pt'), Locale('en')],
          localizationsDelegates: const [
            UiLanguageDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: SettingsPage(
              settings: settings,
              onAddFiles: () {},
              trackCount: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(settings.language, 'en');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('en')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portuguese (Brazil)').last);
    await tester.pumpAndSettle();
    expect(find.text('Idioma'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('pt')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inglês').last);
    await tester.pumpAndSettle();
    expect(find.text('General and appearance'), findsWidgets);
    expect(find.text('Language'), findsWidgets);
    expect(find.text('App language'), findsOneWidget);
    final restored = AppSettings(settings.preferences);
    expect(restored.language, 'en');
    restored.dispose();
    await tester.ensureVisible(find.text('Window and tray'));
    await tester.pumpAndSettle();
    expect(find.text('Window and tray'), findsWidgets);
    expect(find.text('Keep in tray'), findsOneWidget);
    await settings.setLanguage('unsupported');
    expect(settings.language, 'en');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cabeçalho toca somente o álbum aberto e favorita coleção', (
    tester,
  ) async {
    final settings = AppSettings(await SharedPreferences.getInstance());
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final providers = ProviderConnections(
      settings.preferences,
      store,
      vault: MemoryVault(),
    );
    final downloads = DownloadManager(store, providers);
    final tracks = [
      Track(
        id: '1',
        title: 'Primeira',
        artist: 'Autor',
        album: 'Álbuns',
        localPath: 'C:/a/1.mp3',
        trackNumber: 1,
      ),
      Track(
        id: '2',
        title: 'Segunda',
        artist: 'Autor',
        album: 'Álbuns',
        localPath: 'C:/a/2.mp3',
        trackNumber: 2,
      ),
      Track(
        id: '3',
        title: 'Outra',
        artist: 'Outro',
        album: 'Outro álbum',
        localPath: 'C:/b/3.mp3',
      ),
    ];
    await tester.runAsync(() => store.addTracks(tracks));
    final actions = <String>[];
    List<Track> acted = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: settings,
            builder: (context, _) => CatalogBrowser(
              tracks: tracks,
              favorites: {},
              store: store,
              settings: settings,
              downloads: downloads,
              query: '',
              initialCategory: 'albums',
              onPlay: (_, _) async {},
              onAction: (action, values) async {
                actions.add(action);
                acted = values;
              },
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
      () =>
          find.text('Outro álbum').evaluate().isNotEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    final toggle = find.byKey(const ValueKey('catalog.controls.toggle'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final view = tester.getCenter(find.byKey(const ValueKey('catalog.view')));
    final order = tester.getCenter(find.byKey(const ValueKey('catalog.sort')));
    final button = tester.getCenter(toggle);
    expect(order.dx, lessThan(view.dx));
    expect(view.dx, lessThan(button.dx));
    expect(view.dy, closeTo(button.dy, 1));
    final viewButton = find.byKey(const ValueKey('catalog.view'));
    await tester.tap(viewButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view.style.grid')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Small').last);
    await tester.pumpAndSettle();
    expect(settings.visualBool('albums_grid'), true);
    expect(settings.visualNumber('catalog_cover_size', 180), 144);
    await tester.tap(viewButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view.style.list')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lista detalhada').last);
    await tester.pumpAndSettle();
    expect(settings.visualChoice('albums_view', ''), 'detailed');
    expect(settings.visualBool('albums_grid'), false);
    await tester.tap(viewButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cards'));
    await tester.pumpAndSettle();
    expect(settings.visualChoice('albums_view', ''), 'compact_card');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Álbuns').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog.controls.toggle')), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Reproduzir'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await waitForCatalog(
      tester,
      () =>
          actions.isNotEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    expect(actions.last, 'play');
    expect(acted.map((t) => t.id), ['1', '2']);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Aleatório'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await waitForCatalog(
      tester,
      () =>
          actions.length == 2 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    expect(actions.last, 'shuffle');
    expect(acted.map((t) => t.id).toSet(), {'1', '2'});
    await tester.tap(find.byTooltip('Favoritar coleção'));
    await tester.pumpAndSettle();
    expect(settings.collectionFavorites.length, 1);
    expect(find.byTooltip('Remover favorito da coleção'), findsOneWidget);
    expect(find.text('Álbuns'), findsWidgets); // Metadata remains verbatim.
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    downloads.dispose();
    providers.dispose();
    settings.dispose();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await store.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  });
}
