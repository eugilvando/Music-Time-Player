import 'dart:async';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:music_time/presentation/startup_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/presentation/media_details_table.dart';
import 'package:music_time/presentation/now_playing_artwork.dart';
import 'package:music_time/presentation/playlists_dialog.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/settings/app_settings.dart';

import 'catalog_widget_test.dart' show waitForCatalog;
import 'playlist_display_test.dart' show png;

Widget app(Widget child, {String language = 'en'}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
  localizationsDelegates: const [
    UiLanguageDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: Scaffold(body: child),
);

void main() {
  testWidgets('startup uses the saved Portuguese preference while loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'visual.language': 'pt'});
    final opening = Completer<Widget>();
    await tester.pumpWidget(StartupGate(initialize: (_) => opening.future));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Abrindo o Music Time'), findsOneWidget);
    expect(find.textContaining('Preparando sua biblioteca.'), findsOneWidget);
    opening.complete(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Home navigation does not start playback, and filters have the requested order',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'visual.home_sections': ['continue'],
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      const track = Track(
        id: 'a',
        title: 'Original song title',
        artist: 'Artist',
        album: 'Album',
      );
      var opened = 0, resumed = 0;
      await tester.pumpWidget(
        app(
          HomePage(
            index: CatalogIndex(
              tracks: const [track],
              favorites: {},
              offline: {'a'},
              stats: {},
              sources: {},
            ),
            tracks: const [track],
            settings: settings,
            resumeTrack: track,
            onResume: () => resumed++,
            onNowPlaying: () => opened++,
            onAction: (_, _) async {},
            onPlay: (_, _) async {},
            trackActions: (_) => const SizedBox(),
            onExplore: (_, _) {},
            onAddSource: () {},
            library: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Now listening'), findsOneWidget);
      final title = tester.widget<Text>(find.text('Now listening'));
      expect(title.style!.fontSize, lessThan(20));
      final offline = tester.getCenter(
        find.byKey(const ValueKey('home.offline')),
      );
      final sources = tester.getCenter(
        find.byKey(const ValueKey('home.sources')),
      );
      final customize = tester.getCenter(
        find.byKey(const ValueKey('home.customize')),
      );
      expect(offline.dx, lessThan(sources.dx));
      expect(sources.dx, lessThan(customize.dx));
      expect(find.text('All music'), findsOneWidget);
      await tester.tap(find.text('Original song title'));
      expect(opened, 1);
      expect(resumed, 0);
      await tester.tap(find.byType(FilledButton));
      expect(resumed, 1);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets(
    'playlist collage uses the first four occurrences and custom artwork takes priority',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final tracks = List.generate(
        5,
        (i) => Track(
          id: '$i',
          title: 'Song $i',
          artist: 'Artist',
          album: 'Album $i',
          localPath: 'C:/fixture/$i.mp3',
        ),
      );
      final id = (await tester.runAsync(() async {
        await store.addTracks(tracks);
        return store.importPlaylist('Collage', ['3', '1', '1', '0', '4']);
      }))!;
      await tester.pumpWidget(
        app(
          Center(
            child: SizedBox.square(
              dimension: 200,
              child: PlaylistArtwork(
                store: store,
                id: id,
                hasCover: false,
                revision: 0,
              ),
            ),
          ),
        ),
      );
      await waitForCatalog(
        tester,
        () =>
            tester
                .widgetList<TrackCover>(find.byType(TrackCover))
                .where((w) => w.track != null)
                .length ==
            4,
      );
      expect(
        tester
            .widgetList<TrackCover>(find.byType(TrackCover))
            .map((w) => w.track!.id),
        ['3', '1', '1', '0'],
      );
      final dynamic state = tester.state(find.byType(PlaylistArtwork));
      final pending = state.collage;
      await tester.pump();
      expect(identical(state.collage, pending), isTrue);
      await tester.runAsync(() => store.setPlaylistCover(id, png));
      await tester.pumpWidget(
        app(
          Center(
            child: SizedBox.square(
              dimension: 200,
              child: PlaylistArtwork(
                store: store,
                id: id,
                hasCover: true,
                revision: 1,
              ),
            ),
          ),
        ),
      );
      await waitForCatalog(
        tester,
        () => find.byType(Image).evaluate().isNotEmpty,
      );
      expect(find.byKey(const ValueKey('playlist.collage')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
    },
  );

  testWidgets(
    'detailed rows fill available width without horizontal scrolling',
    (tester) async {
      for (final width in [320.0, 500.0, 1200.0]) {
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: width,
                height: 360,
                child: MediaDetailsTable(
                  headers: const ['Title', 'Artist', 'Album', 'Duration', ''],
                  widths: const [300, 220, 220, 120, 128],
                  itemCount: 2,
                  rowBuilder: (_) => [
                    Row(
                      children: [
                        const Icon(Icons.album),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('A long song title')),
                      ],
                    ),
                    const Text(''),
                    const Text('Album'),
                    const Text('3:20'),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.play_arrow),
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.more_horiz),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final available = width.clamp(0, 800);
        for (final row
            in find
                .descendant(
                  of: find.byType(MediaDetailsTable),
                  matching: find.byType(Row),
                )
                .evaluate()
                .where((e) => (e.widget as Row).children.first is SizedBox)) {
          expect(
            (row.renderObject! as RenderBox).size.width,
            closeTo(available, .01),
          );
        }
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'interface labels translate both ways without changing metadata',
    (tester) async {
      const labels = [
        'Now listening',
        'Activate Available Offline',
        'Compact cards',
        'View type',
        'Open playlist',
        'No files',
        'Start again and restart',
      ];
      for (final language in ['pt', 'en']) {
        await tester.pumpWidget(
          app(
            Column(
              children: [
                for (final label in labels) UiText(label),
                const Text('Now listening — album title'),
              ],
            ),
            language: language,
          ),
        );
        for (final label in labels) {
          final expected = language == 'pt' ? portugueseLabel(label) : label;
          expect(find.text(expected), findsOneWidget);
          if (language == 'pt') expect(expected, isNot(label));
        }
        expect(find.text('Now listening — album title'), findsOneWidget);
      }
      for (final entry in englishLabels.entries) {
        expect(englishLabel(entry.key), entry.value);
      }
    },
  );
}
