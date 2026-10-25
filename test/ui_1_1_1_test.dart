import 'support/flutter_sdk.dart';

import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/main.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/presentation/library_screen.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/presentation/media_card_size.dart';
import 'package:music_time/presentation/media_indicators.dart';
import 'package:music_time/presentation/now_playing_page.dart';
import 'package:music_time/presentation/player_bar.dart';
import 'package:music_time/presentation/playlists_dialog.dart';
import 'package:music_time/settings/app_settings.dart';

import 'catalog_widget_test.dart' show drainCatalog, waitForCatalog;
import 'ui_0_7_4_test.dart' show app;

const song = Track(
  id: 'one',
  title: 'A song',
  artist: 'An artist',
  album: 'An album',
  localPath: 'C:/fixture/one.mp3',
);

Future<void> capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (Platform.environment['MUSIC_TIME_CAPTURE_DESIGN'] != '1') return;
  await tester.pump();
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('build/design-previews');
    await folder.create(recursive: true);
    await File('${folder.path}/1.1.1-$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    );
    if (Platform.environment['MUSIC_TIME_CAPTURE_DESIGN'] == '1') {
      final font = await File(
        '${Platform.environment['WINDIR']}/Fonts/segoeui.ttf',
      ).readAsBytes();
      await (FontLoader(
        'Ahem',
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
      final icons = await File(materialIconFontPath()).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    }
  });

  testWidgets('Home card sizes belong to their section and survive backup', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'visual.home_sections': ['mixes', 'favorite_tracks'],
      'visual.media_card_size': 'Large',
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final index = CatalogIndex(
      tracks: const [song],
      favorites: {'one'},
      offline: {},
      stats: {},
      sources: {},
    );
    await tester.pumpWidget(
      app(
        AnimatedBuilder(
          animation: settings,
          builder: (context, _) => MediaCardSizeScope.wrap(
            settings,
            HomePage(
              index: index,
              tracks: const [song],
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
      ),
    );
    await tester.pumpAndSettle();
    MediaCardSizeScope scope(String key) => tester.widget<MediaCardSizeScope>(
      find
          .ancestor(
            of: find.byKey(ValueKey('home.section.$key')),
            matching: find.byType(MediaCardSizeScope),
          )
          .first,
    );
    expect(scope('mixes').value, 'Large');
    scope('mixes').onChanged('Small');
    await tester.pumpAndSettle();
    expect(scope('mixes').value, 'Small');
    expect(scope('favorite_tracks').value, 'Large');
    expect(settings.visualChoice('media_card_size', ''), 'Large');
    await settings.updateVisual('media_card_size', 'Larger');
    await tester.pumpAndSettle();
    expect(scope('favorite_tracks').value, 'Large');
    expect(scope('mixes').value, 'Small');
    final backup = (await tester.runAsync(
      () => AppData.backup(store, settings.preferences),
    ))!;
    await settings.updateVisual('home_card_size_mixes', 'Larger');
    await tester.runAsync(
      () => AppData.restore(store, settings.preferences, backup),
    );
    expect(settings.visualChoice('home_card_size_mixes', ''), 'Small');
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    await tester.runAsync(store.close);
  });

  testWidgets(
    'Playlist favorite belongs to the cover and never its collage thumbnails',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final id = (await tester.runAsync(() async {
        await store.addTracks([song]);
        return store.importPlaylist('Favorites collage', ['one']);
      }))!;
      await tester.pumpWidget(
        app(
          MediaIndicatorScope(
            favorites: const {'one'},
            collections: const {},
            currentId: 'one',
            playing: true,
            child: Center(
              child: SizedBox.square(
                dimension: 160,
                child: PlaylistArtwork(
                  store: store,
                  id: id,
                  hasCover: false,
                  revision: 0,
                  favorite: true,
                ),
              ),
            ),
          ),
        ),
      );
      await drainCatalog(tester);
      expect(find.byKey(const ValueKey('playlist.tile.0')), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
    },
  );

  test(
    'Named playback survives save and backup while older backups remain valid',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      await store.addTracks([song]);
      await store.savePlayback(
        [song],
        0,
        const Duration(seconds: 12),
        title: 'My selected mix',
      );
      expect((await store.loadPlayback()).title, 'My selected mix');
      final backup = await AppData.backup(store, prefs);
      await store.savePlayback([song], 0, Duration.zero);
      expect((await store.loadPlayback()).title, isNull);
      await AppData.restore(store, prefs, backup);
      expect((await store.loadPlayback()).title, 'My selected mix');
      final old = AppData.parse(backup);
      old['schema'] = 12;
      for (final row in old['tables']['playback']) {
        row.remove('title');
      }
      // Schema 12 restoration is covered through the same public import path below.
      final oldContent = jsonEncode(old);
      await AppData.restore(store, prefs, oldContent);
      expect((await store.loadPlayback()).title, isNull);
      expect(
        (await store.loadPlayback()).position,
        const Duration(seconds: 12),
      );
    },
  );

  testWidgets(
    'Queue spans content below topbar and the player spans the full window',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'visual.artist_photos': false,
        'visual.show_queue': true,
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      await tester.runAsync(() async {
        await store.addTracks([song]);
        await store.importPlaylist('My playlist', ['one']);
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MusicTimeApp(settings: settings, store: store),
        ),
      );
      await drainCatalog(tester);
      final dynamic state = tester.state(find.byType(LibraryScreen));
      await waitForCatalog(
        tester,
        () => (state.tracks as List<Track>).isNotEmpty,
      );
      for (final section in [
        'playlists',
        'library',
        'artists',
        'albums',
        'favorites',
        'history',
        'nowPlaying',
      ]) {
        await tester.tap(find.byKey(ValueKey('navigation.$section')));
        await drainCatalog(tester);
        final queue = tester.getRect(
          find.byKey(const ValueKey('queue.floating')),
        );
        final bar = tester.getRect(find.byType(PlayerBar));
        expect(queue.top, closeTo(64, 2), reason: section);
        expect(queue.bottom, closeTo(bar.top, 2), reason: section);
        final footer = tester.getRect(
          find.byKey(const ValueKey('navigation.settings.footer')),
        );
        expect(footer.bottom, closeTo(bar.top, .1));
        expect(bar.left, 0);
        expect(bar.right, 1600);
        if (section == 'playlists') {
          final header = tester.getRect(
            find.byKey(const ValueKey('playlists.heading')),
          );
          expect(
            header.center.dy,
            closeTo(
              tester
                  .getCenter(
                    find.byKey(const ValueKey('playlists.controls.toggle')),
                  )
                  .dy,
              1,
            ),
          );
          await tester.tap(
            find.byKey(const ValueKey('playlists.controls.toggle')),
          );
          await tester.pump();
          expect(
            tester.getCenter(find.byKey(const ValueKey('playlists.sort'))).dy,
            closeTo(
              tester
                  .getCenter(find.byKey(const ValueKey('playlists.heading')))
                  .dy,
              2,
            ),
          );
        }
        if (['library', 'artists', 'albums'].contains(section)) {
          final filter = find.byKey(const ValueKey('catalog.quickFavorites'));
          expect(
            find.ancestor(of: filter, matching: find.byType(AppBar)),
            findsNothing,
          );
          expect(
            tester.getCenter(filter).dy,
            closeTo(
              tester
                  .getCenter(
                    find.byKey(const ValueKey('catalog.controls.toggle')),
                  )
                  .dy,
              1,
            ),
          );
        }
        if (section == 'favorites') {
          final headerRight =
              tester.getRect(find.byType(CatalogBrowser)).right - 24;
          expect(
            tester
                .getRect(find.byKey(const ValueKey('catalog.controls.toggle')))
                .right,
            closeTo(headerRight, 1),
          );
        }
        expect(tester.takeException(), isNull, reason: section);
        if (['playlists', 'favorites', 'library'].contains(section)) {
          await capture(tester, boundary, section);
        }
      }
      (state.controller as PlayerController).queueTitle = 'My playlist';
      state.setState(() {});
      await tester.pump();
      expect(find.text('My playlist'), findsOneWidget);
      final player = state.controller as PlayerController;
      player.queue.addAll([song, song]);
      player.queueKeys.addAll([9001, 9002]);
      state.setState(() {});
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('queue.save-playlist')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Saved queue',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await drainCatalog(tester);
      await tester.runAsync(() async {
        final lists = await store.playlists();
        final id = lists.firstWhere((p) => p['name'] == 'Saved queue')['id'];
        final rows = await store.database.query(
          'playlist_entries',
          where: 'playlist_id=?',
          whereArgs: [id],
          orderBy: 'ordinal',
        );
        expect(rows.map((r) => r['track_id']).toList(), ['one', 'one']);
      });
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      // media_kit schedules native handle destruction five seconds after dispose.
      await tester.pump(const Duration(seconds: 6));
      await drainCatalog(tester);
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );

  testWidgets('Now Playing stays centered in short and narrow windows', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'visual.style': 'classic',
      'visual.cover_scale': 2.6,
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    final controller = (await tester.runAsync(() async => PlayerController()))!;
    controller.current = song;
    for (final style in ['classic', 'vinyl']) {
      await settings.updateVisual('style', style);
      for (final size in [
        const Size(1100, 460),
        const Size(480, 620),
        const Size(900, 900),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          app(
            NowPlayingPage(
              controller: controller,
              settings: settings,
              showLyrics: false,
              favorite: false,
              onFavorite: () {},
              onDetails: () {},
            ),
          ),
        );
        await tester.pump();
        final composition = tester.getRect(
          find.byKey(const ValueKey('nowPlaying.composition')),
        );
        expect(composition.center.dx, closeTo(size.width / 2, 1));
        expect(composition.center.dy, closeTo((size.height + 16) / 2, 2));
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    settings.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'Playlist play, individual rows and shuffle carry the playlist title',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final id = (await tester.runAsync(() async {
        await store.addTracks([song]);
        return store.importPlaylist('Named playlist', ['one']);
      }))!;
      final names = <String>[];
      var unnamed = 0;
      await tester.pumpWidget(
        app(
          PlaylistsPage(
            store: store,
            tracks: const [song],
            initialPlaylist: id,
            onPlay: (_, _) => unnamed++,
            onPlayNamed: (values, index, title) async {
              names.add(title);
              expect(values[index].id, 'one');
            },
          ),
        ),
      );
      await waitForCatalog(
        tester,
        () => find.text('A song').evaluate().isNotEmpty,
      );
      await tester.tap(find.widgetWithIcon(FilledButton, Icons.play_arrow));
      await tester.tap(find.text('A song'));
      await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.shuffle));
      expect(names, ['Named playlist', 'Named playlist', 'Named playlist']);
      expect(unnamed, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
    },
  );

  testWidgets('Artist mix labels the queue with the selected artist', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'visual.home_sections': ['mixes'],
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    String? title;
    await tester.pumpWidget(
      app(
        HomePage(
          index: CatalogIndex(
            tracks: const [song],
            favorites: {},
            offline: {},
            stats: {},
            sources: {},
          ),
          tracks: const [song],
          settings: settings,
          onAction: (_, _) async {},
          onPlay: (_, _) async {},
          onPlayNamed: (_, _, value) async {
            title = value;
          },
          trackActions: (_) => const SizedBox(),
          onExplore: (_, _) {},
          onAddSource: () {},
          library: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artist mix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('An artist').last);
    await tester.pumpAndSettle();
    expect(title, contains('An artist'));
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
