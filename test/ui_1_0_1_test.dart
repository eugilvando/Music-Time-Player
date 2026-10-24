import 'package:music_time/presentation/settings_dialog.dart';
import 'package:music_time/presentation/playlists_dialog.dart';
import 'package:music_time/presentation/now_playing_page.dart';
import 'package:music_time/library/local_metadata.dart' show albumKey;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/main.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/settings/player_bar_layout.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/presentation/compact_media_card.dart';
import 'package:music_time/presentation/media_indicators.dart';
import 'package:music_time/presentation/now_playing_artwork.dart';
import 'package:music_time/presentation/artist_portrait.dart';
import 'package:music_time/presentation/player_bar.dart';
import 'package:music_time/presentation/track_availability_button.dart';
import 'package:music_time/presentation/global_library_search.dart';
import 'package:music_time/presentation/library_screen.dart';
import 'package:music_time/presentation/navigation.dart';
import 'package:music_time/presentation/ui_language.dart';

import 'catalog_widget_test.dart' show drainCatalog, waitForCatalog;
import 'provider_auth_test.dart' show MemoryVault;
import 'offline_test.dart' show Resolver;

Widget app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [UiLanguageDelegate()],
  home: Scaffold(body: child),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    );
  });
  testWidgets(
    'Artwork overlays identify favorite tracks albums artists and the playing track',
    (tester) async {
      const track = Track(
        id: 't',
        title: 'Track',
        artist: 'Artist',
        album: 'Album',
      );
      await tester.pumpWidget(
        app(
          MediaIndicatorScope(
            favorites: const {'t'},
            collections: {'album:${albumKey(track)}', 'artist:Artist'},
            currentId: 't',
            playing: true,
            currentTrack: track,
            child: const Row(
              children: [
                SizedBox.square(dimension: 44, child: TrackCover(track: track)),
                SizedBox.square(
                  dimension: 100,
                  child: TrackCover(track: track, album: true),
                ),
                SizedBox.square(
                  dimension: 100,
                  child: ArtistPortrait(artist: 'Artist', enabled: false),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.favorite), findsNWidgets(3));
      expect(find.byIcon(Icons.graphic_eq), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Secondary click opens the same item actions as the button', (
    tester,
  ) async {
    String? action;
    await tester.pumpWidget(
      app(
        SizedBox(
          height: 100,
          child: CompactMediaCard(
            artwork: const Icon(Icons.album),
            title: 'Album item',
            subtitle: 'Artist',
            actions: PopupMenuButton<String>(
              onSelected: (v) => action = v,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'queue', child: Text('Queue action')),
              ],
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Album item'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Queue action'), findsOneWidget);
    await tester.tap(find.text('Queue action'));
    await tester.pumpAndSettle();
    expect(action, 'queue');
  });
  testWidgets(
    'Volume icon restores previous volume and three separators can move and hide',
    (tester) async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      SharedPreferences.setMockInitialValues({
        'visual.bar_item_order': [
          'separator3',
          'volume',
          'separator1',
          'separator2',
        ],
        'visual.bar_items': [
          'separator3',
          'volume',
          'separator1',
          'separator2',
        ],
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final controller = (await tester.runAsync(
        () async => PlayerController(),
      ))!;
      await tester.binding.setSurfaceSize(const Size(1300, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() => controller.setVolume(37));
      await tester.pumpWidget(
        app(
          AnimatedBuilder(
            animation: Listenable.merge([settings, controller]),
            builder: (_, _) => PlayerBar(
              controller: controller,
              settings: settings,
              favorite: false,
              onFavorite: () {},
              onDetails: () {},
              onQueue: () {},
              onExpand: () {},
              onSave: () async {},
            ),
          ),
        ),
      );
      expect(find.byType(VerticalDivider), findsNWidgets(3));
      expect(
        tester
            .getCenter(find.byKey(const ValueKey('player.item.separator3')))
            .dx,
        lessThan(
          tester.getCenter(find.byKey(const ValueKey('player.item.volume'))).dx,
        ),
      );
      await tester.runAsync(() async {
        final dynamic action = tester
            .widget<IconButton>(find.byKey(const ValueKey('player.mute')))
            .onPressed;
        await action();
      });
      await tester.pump();
      expect(controller.volume, 0);
      await tester.runAsync(() async {
        final dynamic action = tester
            .widget<IconButton>(find.byKey(const ValueKey('player.mute')))
            .onPressed;
        await action();
      });
      await tester.pump();
      expect(controller.volume, 37);
      await settings.updateVisual('bar_items', ['volume', 'separator2']);
      await tester.pump();
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(
        validPlayerBarItems(['separator1', 'separator2', 'separator3']),
        true,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      settings.dispose();
    },
  );
  testWidgets('Larger artwork remains within narrow and wide layouts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'visual.animations': false,
      'visual.cover_position': 'left',
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    final controller = (await tester.runAsync(() async => PlayerController()))!;
    Future<void> render(double width) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        app(
          NowPlayingPage(
            controller: controller,
            settings: settings,
            favorite: false,
            onFavorite: () {},
            onDetails: () {},
          ),
        ),
      );
      await tester.pump();
    }

    await render(1400);
    final original = tester.getSize(find.byType(NowPlayingArtwork)).width;
    await settings.updateVisual('cover_scale', 1.8);
    await render(1400);
    expect(
      tester.getSize(find.byType(NowPlayingArtwork)).width,
      greaterThan(original * 1.3),
    );
    expect(tester.takeException(), isNull);
    await render(480);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    settings.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets(
    'Availability reports permanent and cache copies without toggling global offline',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('music-time-status-'),
      ))!;
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      const track = Track(
        id: 'remote',
        title: 'Remote track',
        artist: 'Artist',
        driveId: 'd',
        itemId: 'i',
        revision: 'r',
      );
      final permanent = File('${dir.path}/permanent.audio'),
          cache = File('${dir.path}/cache.audio');
      await tester.runAsync(() async {
        await store.addTracks([track]);
        await store.selectOffline('one', [track]);
        await permanent.writeAsBytes([1, 2]);
        await cache.writeAsBytes([3, 4]);
        await store.updateDownload(
          track.id,
          'complete',
          path: permanent.path,
          received: 2,
        );
        await store.database.insert('media_cache', {
          'track_id': track.id,
          'revision': 'r',
          'path': cache.path,
          'bytes': 2,
          'cached_at': DateTime.now().toUtc().toIso8601String(),
        });
      });
      final downloads = DownloadManager(
        store,
        Resolver(),
        directory: () async => dir,
      );
      await tester.pumpWidget(
        app(TrackAvailabilityButton(track: track, downloads: downloads)),
      );
      await waitForCatalog(
        tester,
        () => find.byTooltip('Permanent download').evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('player.availability')));
      await drainCatalog(tester);
      await tester.pumpAndSettle();
      expect(find.text('Track availability'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
      expect(downloads.offlineOnly, false);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      downloads.dispose();
      await tester.runAsync(store.close);
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
  testWidgets(
    'Global search finds metadata and links to a library item without playback',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      const track = Track(
        id: 'halo',
        title: 'Halo',
        artist: 'Beyoncé',
        album: 'I Am',
        localPath: 'C:/fixture/halo.mp3',
      );
      await tester.runAsync(() => store.addTracks([track]));
      String? opened;
      CatalogGroup? selected;
      await tester.pumpWidget(
        app(
          GlobalLibrarySearch(
            tracks: const [track],
            query: 'beyonce',
            store: store,
            onOpen: (type, group) {
              opened = type;
              selected = group;
            },
            onPlaylist: (_) {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await drainCatalog(tester);
      expect(find.text('Halo'), findsOneWidget);
      expect(find.text('I Am'), findsOneWidget);
      await tester.tap(find.text('Halo'));
      expect(opened, 'songs');
      expect(selected!.tracks.single.id, track.id);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'Home remount reuses prepared data and download progress does not refresh catalog',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'visual.artist_photos': false,
        'visual.home_sections': ['recent_albums'],
        'visual.home_modes': '{"recent_albums":"grid"}',
        'visual.library_category': 'albums',
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      const songs = [
        Track(
          id: 'one',
          title: 'Track',
          artist: 'Artist',
          album: 'Album',
          localPath: 'C:/fixture/song.mp3',
        ),
      ];
      await tester.runAsync(() => store.addTracks(songs));
      final providers = ProviderConnections(
        settings.preferences,
        store,
        vault: MemoryVault(),
      );
      final downloads = DownloadManager(store, providers);
      final memory = CatalogMemory();
      final key = GlobalKey<CatalogBrowserState>();
      Widget build() => app(
        CatalogBrowser(
          key: key,
          memory: memory,
          home: true,
          tracks: List.of(songs),
          favorites: const {},
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
      );
      await tester.pumpWidget(build());
      await drainCatalog(tester);
      await waitForCatalog(
        tester,
        () => memory.home.isNotEmpty && !key.currentState!.refreshing,
      );
      final saved = Map.of(memory.home), revision = memory.revision;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(build());
      await tester.pump();
      expect(memory.home.keys, saved.keys);
      for (final entry in saved.entries) {
        expect(identical(memory.home[entry.key], entry.value), true);
      }
      expect(memory.home.length, lessThanOrEqualTo(4));
      expect(memory.revision, revision);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final state = key.currentState!, generation = state.generation;
      downloads.running = true;
      state.scheduleAvailability();
      await tester.pump(const Duration(seconds: 2));
      expect(state.generation, generation);
      state.scheduleAvailability();
      await tester.pump(const Duration(seconds: 2));
      expect(state.generation, generation);
      downloads.running = false;
      state.scheduleAvailability();
      await tester.pump(const Duration(milliseconds: 1100));
      await drainCatalog(tester);
      expect(state.generation, generation + 1);
      state.openGroup(CatalogGroup('Artist', 'Artist', songs), type: 'artists');
      await tester.pump();
      expect(find.text('Unplayed'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Offline'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      downloads.dispose();
      providers.dispose();
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'Sidebar returns to section root and Home Now Playing History use global search',
    (tester) async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      SharedPreferences.setMockInitialValues({
        'visual.artist_photos': false,
        'visual.artist_biographies': false,
        'visual.cache_enabled': false,
        'visual.language': 'en',
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => call.method == 'readAll'
                ? <String, String>{}
                : call.method == 'containsKey'
                ? false
                : null,
          );
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      const songs = [
        Track(
          id: 'halo',
          title: 'Halo',
          artist: 'Artist',
          album: 'Album',
          localPath: 'C:/fixture/halo.mp3',
        ),
      ];
      await tester.runAsync(() async {
        await store.addTracks(songs);
        await store.importPlaylist(
          'Sidebar playlist',
          songs.map((t) => t.id).toList(),
        );
      });
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MusicTimeApp(settings: settings, store: store));
      await drainCatalog(tester);
      final dynamic state = tester.state(find.byType(LibraryScreen));
      await waitForCatalog(
        tester,
        () => (state.tracks as List<Track>).isNotEmpty,
      );
      for (final section in ['home', 'nowPlaying', 'history']) {
        await tester.tap(find.byKey(ValueKey('navigation.$section')));
        await drainCatalog(tester);
        await tester.enterText(find.byType(TextField).first, 'Halo');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await drainCatalog(tester);
        expect(
          find.byKey(const ValueKey('search.global.results')),
          findsOneWidget,
        );
        expect(
          tester.widget<LibraryScreen>(find.byType(LibraryScreen)).section.name,
          section,
        );
      }
      await tester.tap(find.text('Halo').first);
      await drainCatalog(tester);
      expect(
        tester.widget<LibraryScreen>(find.byType(LibraryScreen)).section,
        AppSection.library,
      );
      expect(
        (state.catalogKey.currentState as CatalogBrowserState).selectedGroup,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('navigation.library')));
      await drainCatalog(tester);
      final catalog = state.catalogKey.currentState as CatalogBrowserState;
      expect(catalog.selectedGroup, isNull);
      expect(catalog.category, 'songs');
      expect(catalog.sort, 'title');
      expect((state.controller as PlayerController).queue, isEmpty);
      await tester.tap(find.byKey(const ValueKey('navigation.playlists')));
      await drainCatalog(tester);
      await waitForCatalog(
        tester,
        () => find.text('Sidebar playlist').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Sidebar playlist'));
      await drainCatalog(tester);
      expect(
        (tester.state(find.byType(PlaylistsPage)) as dynamic).selected,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('navigation.playlists')));
      await drainCatalog(tester);
      expect(
        (tester.state(find.byType(PlaylistsPage)) as dynamic).selected,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('navigation.settings')));
      await drainCatalog(tester);
      await tester.tap(find.byKey(const ValueKey('settings.playback')));
      await tester.pump();
      expect(
        (tester.state(find.byType(SettingsPage)) as dynamic).category,
        SettingsCategory.playback,
      );
      await tester.tap(find.byKey(const ValueKey('navigation.settings')));
      await drainCatalog(tester);
      expect(
        (tester.state(find.byType(SettingsPage)) as dynamic).category,
        SettingsCategory.general,
      );
      await tester.tap(find.byKey(const ValueKey('navigation.artists')));
      await drainCatalog(tester);
      (state.catalogKey.currentState as CatalogBrowserState).openGroup(
        CatalogGroup('Artist', 'Artist', songs),
        type: 'artists',
      );
      await drainCatalog(tester);
      expect(find.widgetWithText(ChoiceChip, 'Offline'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Unplayed'), findsNothing);
      await tester.runAsync(() => state.save() as Future<void>);
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );
}
