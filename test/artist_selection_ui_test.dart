import 'support/flutter_sdk.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/library/artist_similarity.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/artist_selection_dialog.dart';
import 'package:music_time/presentation/settings_dialog.dart';
import 'package:music_time/settings/app_settings.dart';

import 'catalog_widget_test.dart' show waitForCatalog;
import 'ui_0_7_4_test.dart' show app;

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['MUSIC_TIME_CAPTURE_DESIGN'] != '1') return;
  await tester.pump();
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('build/1.2.0-$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'Home exposes artist mix and radio by default and artist cards share these actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'visual.home_sections': ['mixes'],
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final tracks = [
        for (var i = 0; i < 12; i++)
          Track(
            id: '$i',
            title: 'Track $i',
            artist: i < 6 ? 'Main' : 'Other',
            genre: 'Genre ${i % 4}',
          ),
      ];
      final index = CatalogIndex(
        tracks: tracks,
        favorites: tracks.map((t) => t.id).toSet(),
        offline: tracks.map((t) => t.id).toSet(),
        stats: {
          '0': {'play_count': 2, 'last_played': '2026-10-16T00:00:00Z'},
        },
        sources: {},
        collectionFavorites: {'artist:Main'},
      );
      String? artist;
      bool? radio;
      List<Track>? candidates;
      Widget home(String key) => app(
        HomePage(
          key: ValueKey(key),
          index: index,
          tracks: tracks,
          settings: settings,
          onAction: (_, _) async {},
          onPlay: (_, _) async {},
          lastfmMix: (_) async => [],
          trackActions: (_) => const SizedBox(),
          onExplore: (_, _) {},
          onAddSource: () {},
          library: const SizedBox(),
          onArtistSelection: (a, r, t, _) async {
            artist = a;
            radio = r;
            candidates = t;
          },
        ),
      );
      await tester.pumpWidget(home('mixes'));
      await tester.pumpAndSettle();
      expect(find.text('Artist mix'), findsOneWidget);
      expect(find.text('Artist radio'), findsOneWidget);
      await settings.updateVisual('home_sections', ['favorite_artists']);
      await tester.pumpWidget(home('artists'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Artist radio'));
      await tester.pumpAndSettle();
      expect(artist, 'Main');
      expect(radio, true);
      expect(candidates!.length, tracks.length);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
  setUpAll(() async {
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const song = Track(id: 'one', title: 'A song', artist: 'Main');
  testWidgets('mix preview adapts to a narrow window and 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 600));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final settings = AppSettings(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showArtistSelection(
              context,
              artist: 'Main',
              radio: false,
              eligible: const [song],
              settings: settings,
              similarity: ArtistSimilarity(
                store,
                () async => throw StateError('unused'),
              ),
              onPlay: (_, _, _) async {},
              onSave: (_) async {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await waitForCatalog(
      tester,
      () => find.text('1 tracks / 40 requested').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.close);
    settings.dispose();
  });
  testWidgets(
    'mix preview reports real count, regenerates and plays a named snapshot',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final settings = AppSettings(await SharedPreferences.getInstance());
      List<Track>? queue;
      String? title;
      var saves = 0;
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showArtistSelection(
                  context,
                  artist: 'Main',
                  radio: false,
                  eligible: const [song],
                  settings: settings,
                  similarity: ArtistSimilarity(
                    store,
                    () async => throw StateError('unused'),
                  ),
                  onPlay: (v, i, n) async {
                    queue = v;
                    title = n;
                  },
                  onSave: (_) async {
                    saves++;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await waitForCatalog(
        tester,
        () => find.text('A song').evaluate().isNotEmpty,
      );
      expect(find.text('1 tracks / 40 requested'), findsOneWidget);
      await capture(tester, key, 'mix-preview');
      await tester.tap(find.text('Regenerate'));
      await waitForCatalog(
        tester,
        () =>
            find.text('A song').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(queue, [song]);
      expect(title, 'Local artist mix · Main');
      expect(saves, 0);
      expect((await tester.runAsync(store.playlists)), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
      settings.dispose();
    },
  );
  testWidgets(
    'radio without local similars previews the automatic seed mix fallback',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final settings = AppSettings(await SharedPreferences.getInstance());
      await settings.updateVisual('offline_only', true);
      var plays = 0;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showArtistSelection(
                context,
                artist: 'Main',
                radio: true,
                eligible: const [song],
                settings: settings,
                similarity: ArtistSimilarity(
                  store,
                  () async => throw StateError('offline'),
                ),
                onPlay: (_, _, _) async {
                  plays++;
                },
                onSave: (_) async {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await waitForCatalog(
        tester,
        () => find.text('A song').evaluate().isNotEmpty,
      );
      expect(plays, 0);
      expect(find.text('Local artist mix · Main'), findsOneWidget);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(plays, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
      settings.dispose();
    },
  );
  testWidgets(
    'mix size controls validate bounds, persist and restore, without losing focus',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = AppSettings(await SharedPreferences.getInstance());
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(
            ListenableBuilder(
              listenable: settings,
              builder: (_, _) => SettingsPage(
                settings: settings,
                onAddFiles: () {},
                trackCount: 2,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('settings.playback')));
      await tester.pumpAndSettle();
      expect(find.text('Mixes and radios'), findsWidgets);
      final fields = find.byType(TextFormField);
      await tester.ensureVisible(fields.first);
      await tester.enterText(fields.first, '0');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter a number from 1 to 500'), findsOneWidget);
      await tester.enterText(fields.first, '120');
      await tester.enterText(fields.last, '55');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(AppSettings(settings.preferences).artistSelectionSize(), 120);
      expect(settings.artistSelectionSize(radio: true), 55);
      await capture(tester, key, 'mix-settings');
      await tester.ensureVisible(find.text('Restore defaults'));
      await tester.tap(find.text('Restore defaults'));
      await tester.pumpAndSettle();
      expect(settings.artistSelectionSize(), 40);
      expect(settings.artistSelectionSize(radio: true), 40);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
