import 'support/flutter_sdk.dart';

import 'package:flutter/services.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/catalog_query.dart';
import 'package:music_time/library/favorite_catalog.dart';
import 'package:music_time/library/local_metadata.dart' show albumKey;
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/artist_portrait.dart';
import 'package:music_time/presentation/media_indicators.dart';
import 'package:music_time/presentation/media_card_size.dart';
import 'package:music_time/presentation/compact_media_card.dart';
import 'package:music_time/presentation/settings_dialog.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;
import 'catalog_widget_test.dart' show waitForCatalog, drainCatalog;

Widget app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [UiLanguageDelegate()],
  theme: ThemeData.dark().copyWith(
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Segoe UI'),
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'nine settings categories and subpages retain preferences and searchable lyrics destinations',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'visual.artist_photos': false,
        'visual.cache_gb': 27.0,
        'visual.style': 'focus',
        'visual.eq_60': 4.0,
        'visual.bar_items': ['play', 'info'],
        'windows.close_to_tray': false,
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final before = {
        for (final key in settings.preferences.getKeys())
          key: settings.preferences.get(key),
      };
      await tester.runAsync(() async {
        final windows = Platform.environment['WINDIR']!;
        final font = await File('$windows/Fonts/segoeui.ttf').readAsBytes();
        await (FontLoader(
          'Segoe UI',
        )..addFont(Future.value(ByteData.sublistView(font)))).load();
        final icons = await File(materialIconFontPath()).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: boundary,
            child: SettingsPage(
              settings: settings,
              onAddFiles: () {},
              trackCount: 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(SettingsCategory.values.length, 9);
      for (final category in SettingsCategory.values) {
        final target = find.byKey(ValueKey('settings.${category.name}'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: category.name);
      }
      await tester.tap(find.byTooltip('Search settings'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('settings.search')),
        'lyrics',
      );
      await tester.pumpAndSettle();
      expect(find.text('Lyrics — presentation'), findsOneWidget);
      expect(find.text('Lyrics providers'), findsOneWidget);
      await tester.tap(find.text('Lyrics — presentation'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Auto-scroll lyrics'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Auto-scroll lyrics'), findsOneWidget);
      expect({
        for (final key in settings.preferences.getKeys())
          key: settings.preferences.get(key),
      }, before);
      await tester.tap(find.byKey(const ValueKey('settings.customization')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Now Playing').last,
        -300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage()
                .timeout(const Duration(seconds: 10));
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        image.dispose();
        final file = File('build/screenshots-1.1.0/settings-interface.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      });
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
  testWidgets(
    'favorites tabs show only the independently favorited entity type',
    (tester) async {
      SharedPreferences.setMockInitialValues({'visual.artist_photos': false});
      final settings = AppSettings(await SharedPreferences.getInstance());
      const tracks = [
        Track(
          id: 'song',
          title: 'Explicit song',
          artist: 'Song author',
          album: 'Song album',
          localPath: 'C:/song.mp3',
        ),
        Track(
          id: 'album',
          title: 'Album child',
          artist: 'Album author',
          album: 'Explicit album',
          localPath: 'C:/album.mp3',
        ),
        Track(
          id: 'artist',
          title: 'Artist child',
          artist: 'Explicit artist',
          album: 'Artist album',
          localPath: 'C:/artist.mp3',
        ),
      ];
      await settings.persist('collections.favorites', [
        'album:${albumKey(tracks[1])}',
        'artist:Explicit artist',
      ]);
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
      final key = GlobalKey<CatalogBrowserState>();
      await tester.pumpWidget(
        app(
          CatalogBrowser(
            key: key,
            tracks: tracks,
            favorites: const {'song'},
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
      await waitForCatalog(tester, () => !key.currentState!.refreshing);
      await tester.tap(find.byKey(const ValueKey('favorites.songs')));
      await tester.pump();
      expect(find.text('Explicit song'), findsOneWidget);
      expect(find.text('Album child'), findsNothing);
      expect(find.text('Artist child'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('favorites.artists')));
      await tester.pump();
      expect(find.text('Explicit artist'), findsOneWidget);
      expect(find.text('Song author'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('favorites.albums')));
      await tester.pump();
      expect(find.text('Explicit album'), findsOneWidget);
      expect(find.text('Song album'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      downloads.dispose();
      providers.dispose();
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );
  test(
    'appearance and now playing resets preserve unrelated settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'visual.language': 'pt',
        'visual.cache_gb': 27.0,
        'visual.style': 'focus',
        'visual.font_body': 28.0,
        'visual.bar_items': ['info', 'play'],
        'visual.eq_enabled': true,
        'visual.eq_60': 4.0,
        'collections.favorites': ['artist:A'],
        'windows.close_to_tray': false,
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      await settings.resetAppearance();
      expect(settings.visualNumber('font_body', 14), 14);
      expect(settings.nowPlayingStyle, 'lyrics_only');
      await settings.resetNowPlaying();
      expect(settings.nowPlayingStyle, 'vinyl');
      expect(settings.language, 'pt');
      expect(settings.visualNumber('cache_gb', 10), 27);
      expect(settings.visualBool('eq_enabled'), true);
      expect(settings.visualNumber('eq_60', 0), 4);
      expect(settings.visualList('bar_items', []), ['info', 'play']);
      expect(settings.collectionFavorites, {'artist:A'});
      expect(settings.closeToTray, false);
      settings.dispose();
    },
  );
  test('favorite indexes and SQL keep artist album and track favorites independent', () async {
    const tracks = [
      Track(
        id: 'song',
        localPath: 'C:/fixture/song.mp3',
        title: 'Song favorite',
        artist: 'Other',
        album: 'Other',
      ),
      Track(
        id: 'album',
        localPath: 'C:/fixture/album.mp3',
        title: 'Album child',
        artist: 'Other',
        album: 'Favorite album',
      ),
      Track(
        id: 'artist',
        localPath: 'C:/fixture/artist.mp3',
        title: 'Artist child',
        artist: 'Favorite artist',
        album: 'Third',
      ),
      Track(
        id: 'role',
        localPath: 'C:/fixture/role.mp3',
        title: 'Album artist child',
        artist: 'Guest',
        albumArtist: 'Favorite artist',
        album: 'Fourth',
      ),
    ];
    final collections = {
      'artist:Favorite artist',
      'album:${albumKey(tracks[1])}',
    };
    final index = CatalogIndex(
      tracks: tracks,
      favorites: {'song'},
      offline: {},
      stats: {},
      sources: {},
      collectionFavorites: collections,
    );
    final result = prepareFavoriteCatalog((index: index, tracks: tracks));
    expect(result.tracks.map((t) => t.id), ['song']);
    expect(result.albums.map((g) => g.name), ['Favorite album']);
    expect(result.artists.single.name, 'Favorite artist');
    expect(result.artists.single.tracks.map((t) => t.id).toSet(), {
      'artist',
      'role',
    });
    final filter = CatalogFilters()..favorites = true;
    expect(index.query(filter).map((t) => t.id), ['song']);
    final store = await LibraryStore.open(':memory:');
    try {
      await store.addTracks(tracks);
      await store.setFavorite('song', true);
      final page = await store.catalogPage(
        CatalogSqlQuery(filters: filter, collectionFavorites: collections),
        offset: 0,
        limit: 100,
        includeCovers: false,
      );
      expect(page.tracks.map((t) => t.id), ['song']);
    } finally {
      await store.close();
    }
  });
  testWidgets(
    'artist portrait stays circular inside a wide card and favorite uses accent',
    (tester) async {
      await tester.pumpWidget(
        app(
          Theme(
            data: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.green)
                  .copyWith(primary: Colors.green),
            ),
            child: const SizedBox(
              width: 350,
              height: 180,
              child: MediaBadges(
                favorite: true,
                child: ArtistPortrait(
                  artist: 'A',
                  enabled: false,
                  cachedOnly: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final portrait = find.descendant(
        of: find.byType(ArtistPortrait),
        matching: find.byType(MediaBadges),
      );
      final size = tester.getSize(portrait);
      expect(size.width, size.height);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.favorite)).color,
        Colors.green,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Figma compact cards use 36 48 64 and 80 pixel artwork', (
    tester,
  ) async {
    const expected = {
      'Extra Small': 36.0,
      'Small': 36.0,
      'Medium': 48.0,
      'Large': 64.0,
      'Extra Large': 80.0,
    };
    for (final entry in mediaCardSizes.entries) {
      await tester.pumpWidget(
        app(
          MediaCardSizeScope(
            value: entry.key,
            onChanged: (_) {},
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                height: 200,
                child: CompactMediaCard(
                  artwork: const SizedBox(key: ValueKey('art')),
                  title: 'Title',
                  subtitle: 'Artist',
                  actions: const Icon(Icons.more_horiz),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byKey(const ValueKey('art')));
      expect(size.width, expected[entry.key]);
      expect(tester.takeException(), isNull);
    }
  });
}
