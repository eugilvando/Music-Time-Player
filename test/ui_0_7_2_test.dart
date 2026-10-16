import 'support/flutter_sdk.dart';

import 'package:flutter/services.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/presentation/catalog_browser.dart';

import 'provider_auth_test.dart' show MemoryVault;
import 'catalog_widget_test.dart' show waitForCatalog, drainCatalog;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'dart:convert';
import 'dart:io';

import 'package:music_time/library/local_metadata.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/presentation/compact_media_card.dart';
import 'package:music_time/presentation/media_details_table.dart';
import 'package:music_time/presentation/now_playing_page.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final windows = Platform.environment['WINDIR'];
    if (windows != null) {
      final bytes = await File('$windows/Fonts/segoeui.ttf').readAsBytes();
      await (FontLoader(
        'Segoe UI',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    final bytes = await File(materialIconFontPath()).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
  final tracks = List.generate(
    12,
    (i) => Track(
      id: '$i',
      title: 'Track $i',
      artist: 'Artist',
      album: 'Album',
      year: 1990,
      trackNumber: i + 1,
      addedAt: DateTime(2026, 10, 15),
    ),
  );
  final boundary = GlobalKey();
  Widget app(Widget child) => RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Segoe UI'),
      locale: const Locale('en'),
      localizationsDelegates: const [UiLanguageDelegate()],
      home: Scaffold(body: child),
    ),
  );

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('build/design-previews');
      await folder.create(recursive: true);
      await File('${folder.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final mode in homeViewStyles.values.expand((f) => f.keys)) {
    testWidgets(
      'Home $mode renders tracks, mixes and collections with actions',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1100, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({
          'visual.home_sections': [
            'recent',
            'mixes',
            'favorite_albums',
            'explore',
          ],
          'visual.home_mix_types': ['artists', 'decades'],
          'visual.home_modes': jsonEncode({
            for (final key in ['recent', 'mixes', 'favorite_albums', 'explore'])
              key: mode,
          }),
        });
        final settings = AppSettings(await SharedPreferences.getInstance());
        final index = CatalogIndex(
          tracks: tracks,
          favorites: {},
          offline: {},
          stats: {},
          sources: {},
          collectionFavorites: {'album:${albumKey(tracks.first)}'},
        );
        var actions = 0;
        await tester.pumpWidget(
          app(
            HomePage(
              index: index,
              tracks: tracks,
              settings: settings,
              onPlay: (_, _) async {},
              onAction: (_, _) async {},
              trackActions: (_) => IconButton(
                tooltip: 'Track actions',
                onPressed: () => actions++,
                icon: const Icon(Icons.more_horiz),
              ),
              onExplore: (_, _) {},
              onAddSource: () {},
              onSources: () {},
              library: const SizedBox(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if ({
          'grid',
          'compact_cards_grid',
          'detailed',
          'carousel_3',
          'carousel_5',
        }.contains(mode)) {
          await capture(tester, 'home-0.7.2-$mode');
        }
        final source = tester.getCenter(
          find.byKey(const ValueKey('home.sources')),
        );
        final offline = tester.getCenter(
          find.byKey(const ValueKey('home.offline')),
        );
        final customize = tester.getCenter(
          find.byKey(const ValueKey('home.customize')),
        );
        expect(offline.dx, lessThan(source.dx));
        expect(source.dx, lessThan(customize.dx));
        expect(find.text('Activate Available Offline'), findsOneWidget);
        if (mode == 'detailed') {
          expect(find.byType(MediaDetailsTable), findsWidgets);
        }
        if (homeCompactItem(mode)) {
          expect(find.byType(CompactMediaCard), findsWidgets);
        }
        await tester.tap(find.byTooltip('Track actions').first);
        expect(actions, 1);
        for (var i = 0; i < 9; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -450));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: mode);
        }
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      },
    );
  }
  testWidgets(
    'Collection compact cards share a model and every album view shows numbers',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'visual.artist_photos': false,
        'visual.albums_view': 'compact_card',
        'visual.artists_view': 'compact_card',
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
      List<Track>? played;
      final songs = [
        Track(
          id: 'one',
          title: 'First song',
          artist: 'Artist',
          album: 'Album',
          trackNumber: 7,
          localPath: 'C:/fixture/1.mp3',
        ),
        Track(
          id: 'two',
          title: 'Second song',
          artist: 'Artist',
          album: 'Album',
          trackNumber: 12,
          localPath: 'C:/fixture/2.mp3',
        ),
      ];
      await tester.runAsync(() => store.addTracks(songs));
      await tester.pumpWidget(
        app(
          AnimatedBuilder(
            animation: settings,
            builder: (context, _) => CatalogBrowser(
              tracks: songs,
              favorites: {},
              store: store,
              settings: settings,
              downloads: downloads,
              query: '',
              initialCategory: 'artists',
              onPlay: (_, _) async {},
              onAction: (action, values) async {
                if (action == 'play') {
                  played = values;
                }
              },
              trackActions: (_) => const Icon(Icons.more_horiz),
              onAddSource: () {},
              onPlaylist: (_) {},
            ),
          ),
        ),
      );
      await waitForCatalog(
        tester,
        () => find.byType(CompactMediaCard).evaluate().isNotEmpty,
      );
      final state = tester.state<CatalogBrowserState>(
        find.byType(CatalogBrowser),
      );
      state.chooseCategory('albums');
      await drainCatalog(tester);
      await waitForCatalog(tester, () => !state.refreshing);
      await tester.pumpAndSettle();
      expect(find.byType(CompactMediaCard), findsOneWidget);
      await tester.tap(find.byTooltip('Play').first);
      await drainCatalog(tester);
      expect(played?.length, 2);
      await waitForCatalog(tester, () => !state.refreshing);
      await tester.tap(find.text('Album').last);
      await drainCatalog(tester);
      await tester.pumpAndSettle();
      for (final style in ['compact_card', 'compact', 'detailed']) {
        await settings.updateVisual('albums_view', style);
        await drainCatalog(tester);
        await tester.pumpAndSettle();
        expect(find.text('7'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
        if (style == 'detailed') {
          expect(find.byType(MediaDetailsTable), findsOneWidget);
          await capture(tester, 'album-detailed-0.7.2');
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      downloads.dispose();
      providers.dispose();
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'Lyrics allocate one quarter to information and preserve layout at 150 percent',
    (tester) async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final controller = PlayerController();
      for (final width in [1000.0, 1600.0]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(
          app(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(1.5),
              ),
              child: NowPlayingPage(
                controller: controller,
                settings: settings,
                favorite: false,
                showLyrics: true,
                onFavorite: () {},
                onDetails: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('nowPlaying.lyricsInformation')),
              )
              .width,
          width * .25,
        );
        expect(tester.takeException(), isNull);
        if (width == 1600) {
          await capture(tester, 'lyrics-0.7.2');
        }
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      settings.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
}
