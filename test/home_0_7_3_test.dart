import 'support/flutter_sdk.dart';

import 'package:music_time/presentation/media_card_size.dart';

import 'dart:io';
import 'dart:ui' as image_ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/home_catalog.dart';
import 'package:music_time/library/local_metadata.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/presentation/home_favorite_playlists.dart';
import 'package:music_time/presentation/playlists_dialog.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/settings/app_settings.dart';

import 'catalog_widget_test.dart' show waitForCatalog;

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
  final boundary = GlobalKey();
  final tracks = [
    Track(
      id: 'a',
      localPath: 'C:/fixture/a.mp3',
      title: 'A',
      artist: 'Guest',
      albumArtist: 'Owner',
      album: 'First',
      addedAt: DateTime(2026, 1),
    ),
    Track(
      id: 'b',
      localPath: 'C:/fixture/b.mp3',
      title: 'B',
      artist: 'Second',
      album: 'Second',
      addedAt: DateTime(2026, 2),
    ),
    const Track(
      id: 'c',
      localPath: 'C:/fixture/c.mp3',
      title: 'C',
      artist: 'Second',
      album: 'Third',
    ),
    const Track(
      id: 'd',
      localPath: 'C:/fixture/d.mp3',
      title: 'D',
      artist: 'Unheard',
      album: 'Unheard',
    ),
  ];
  CatalogIndex index() => CatalogIndex(
    tracks: tracks,
    favorites: {'b'},
    offline: {'a'},
    stats: {
      'a': {'play_count': 5, 'last_played': '2026-10-10T00:00:00'},
      'b': {'play_count': 3, 'last_played': '2026-10-14T00:00:00'},
      'c': {'play_count': 4},
    },
    sources: {},
    collectionFavorites: {
      'artist:Owner',
      'artist:Guest',
      'album:${albumKey(tracks.first)}',
    },
  );
  Widget app(Widget child) => RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      theme: ThemeData(fontFamily: 'Segoe UI'),
      locale: const Locale('en'),
      localizationsDelegates: const [UiLanguageDelegate()],
      home: Scaffold(body: child),
    ),
  );

  test(
    'Home migration applies requested order once and backup preserves it',
    () async {
      SharedPreferences.setMockInitialValues({
        'visual.home_sections': ['recent', 'mixes'],
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      addTearDown(settings.dispose);
      await settings.migrateHomeLayout();
      expect(selectedHomeSections(settings), homeSectionLabels.keys);
      expect(homeSections.values.map(englishLabel), homeSectionLabels.values);
      expect(prefs.getStringList('visual.home_sections_before_0_7_3'), [
        'recent',
        'mixes',
      ]);
      await settings.updateVisual('home_sections', ['history', 'mixes']);
      await settings.migrateHomeLayout();
      expect(selectedHomeSections(settings), ['history', 'mixes']);
      await settings.favoriteCollection('playlist:8');
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final backup = await AppData.backup(store, prefs);
      AppData.parse(backup);
      await settings.favoriteCollection('playlist:8');
      await AppData.restore(store, prefs, backup);
      expect(settings.collectionFavorites, contains('playlist:8'));
      expect(prefs.getBool('visual.home_layout_0_7_3'), isTrue);
    },
  );

  test(
    'collection sections use actual favorites, additions and listening counts',
    () {
      final data = prepareHome((
        index: index(),
        tracks: tracks,
        quick: 'all',
        limit: 20,
        lastfm: false,
      ));
      expect(data.collections['favorite_albums']!.single.name, 'First');
      expect(data.collections['favorite_artists']!.single.name, 'Guest');
      expect(data.collections['favorite_album_artists']!.single.name, 'Owner');
      expect(data.collections['discover_albums']!.map((g) => g.name), [
        'Unheard',
      ]);
      expect(data.collections['discover_artists']!.map((g) => g.name), [
        'Unheard',
      ]);
      expect(data.collections['recent_albums']!.map((g) => g.name), [
        'Second',
        'First',
      ]);
      expect(data.collections['recent_artists']!.map((g) => g.name), [
        'Second',
        'Guest',
      ]);
      expect(data.collections['most_played_artists']!.map((g) => g.name), [
        'Second',
        'Guest',
      ]);
      expect(data.lists['history']!.map((t) => t.id), ['b', 'a']);
      final offline = prepareHome((
        index: index(),
        tracks: tracks,
        quick: 'offline',
        limit: 20,
        lastfm: false,
      ));
      expect(offline.collections['recent_albums']!.single.name, 'First');
      expect(offline.collections['discover_albums'], isEmpty);
    },
  );

  testWidgets(
    'all twelve sections appear in order, with a prominent resume cover',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'visual.artist_photos': false});
      final settings = AppSettings(await SharedPreferences.getInstance());
      var resumes = 0;
      final memory = <String, HomeData>{};
      final catalog = index();
      Widget page() => app(
        HomePage(
          index: catalog,
          tracks: tracks,
          settings: settings,
          memory: memory,
          resumeTrack: tracks.first,
          onResume: () => resumes++,
          onAction: (_, _) async {},
          onPlay: (_, _) async {},
          trackActions: (_) => const SizedBox(),
          onExplore: (_, _) {},
          onAddSource: () {},
          library: const SizedBox(),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final list = tester.widgetList<ListView>(find.byType(ListView)).first;
      final children =
          (list.childrenDelegate as SliverChildListDelegate).children;
      final keys = children
          .map((widget) => widget is MediaCardSizeScope ? widget.child : widget)
          .map(
            (w) => w is HomeFavoritePlaylists
                ? 'home.section.favorite_playlists'
                : (w.key is ValueKey<String>
                      ? (w.key! as ValueKey<String>).value
                      : ''),
          )
          .where((v) => v.startsWith('home.section.'));
      expect(keys, homeSectionLabels.keys.map((k) => 'home.section.$k'));
      final resume = find.byKey(const ValueKey('home.section.continue'));
      await tester.ensureVisible(resume);
      await tester.pumpAndSettle();
      expect(tester.getSize(resume).height, greaterThanOrEqualTo(248));
      await tester.tap(
        find.descendant(of: resume, matching: find.byType(FilledButton)),
      );
      await tester.pump();
      expect(resumes, 1);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(
          format: image_ui.ImageByteFormat.png,
        );
        await Directory('build/design-previews').create(recursive: true);
        await File('build/design-previews/home-0.7.3.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets(
    'playlist favorite is persistent; Home playback filters unavailable tracks and keeps repetitions',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final id = (await tester.runAsync(() async {
        await store.addTracks(tracks);
        return store.importPlaylist('My favorites', ['a', 'b', 'a']);
      }))!;
      await tester.pumpWidget(
        app(
          PlaylistsPage(
            store: store,
            tracks: tracks,
            settings: settings,
            onPlay: (_, _) {},
          ),
        ),
      );
      await waitForCatalog(
        tester,
        () =>
            find.byKey(ValueKey('playlist.favorite.$id')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(ValueKey('playlist.favorite.$id')));
      await tester.pumpAndSettle();
      expect(settings.collectionFavorites, contains('playlist:$id'));
      final rows = (await tester.runAsync(store.playlists))!;
      int? opened;
      List<Track>? played;
      await tester.pumpWidget(
        app(
          HomeFavoritePlaylists(
            settings: settings,
            store: store,
            playlists: rows,
            tracks: [tracks.first],
            mode: 'compact',
            onOpen: (id) => opened = id,
            onPlay: (values, _) async => played = values,
            onAction: (_, _) async {},
          ),
        ),
      );
      await waitForCatalog(
        tester,
        () => find.text('My favorites').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('My favorites'));
      expect(opened, id);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(played!.map((t) => t.id), ['a', 'a']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
      settings.dispose();
    },
  );
}
