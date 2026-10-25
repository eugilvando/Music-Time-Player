import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/library/insight_artist_templates.dart';
import 'package:music_time/library/lastfm_profile.dart';
import 'package:music_time/library/m3u8.dart';
import 'package:music_time/library/playlist_recommendations.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/playlist_import_review.dart';
import 'package:music_time/presentation/sidebar_settings.dart';
import 'package:music_time/presentation/listening_playlist_dialog.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/settings/sidebar_layout.dart';

import 'listening_insights_test.dart' show sampleReport;
import 'ui_0_7_4_test.dart' show app;

const catalog = [
  Track(
    id: 'a',
    title: 'A',
    artist: 'Band',
    album: 'Album',
    localPath: '/a.mp3',
  ),
  Track(
    id: 'b',
    title: 'B',
    artist: 'Guest',
    album: 'Other',
    localPath: '/b.mp3',
  ),
  Track(id: 'wrong', title: 'A', artist: 'Other', localPath: '/wrong.mp3'),
];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('artist templates cross global and personal ranks with the catalog; cache works offline', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    var calls = 0;
    final api = LastFmClient(
      MockClient((r) async {
        calls++;
        expect(r.url.queryParameters['method'], 'artist.getTopTracks');
        expect(r.url.queryParameters['autocorrect'], '0');
        return http.Response(
          jsonEncode({
            'toptracks': {
              'track': [
                {
                  'name': 'Absent',
                  'artist': {'name': 'Band'},
                },
                {
                  'name': 'A',
                  'artist': {'name': 'Band'},
                },
              ],
            },
          }),
          200,
        );
      }),
      apiKey: 'fixture',
      apiSecret: '',
    );
    final service = InsightArtistTemplates(store, () async => api);
    final top = await service.prepare(
      criterion: 'artist_top',
      artist: 'Band',
      report: sampleReport(),
      catalog: catalog,
      limit: 10,
    );
    expect(top.ids, ['a']);
    expect(calls, 1);
    expect(
      (await service.prepare(
        criterion: 'artist_top',
        artist: 'Band',
        report: sampleReport(),
        catalog: catalog,
        limit: 10,
        offline: true,
      )).ids,
      ['a'],
    );
    expect(calls, 1);
    final personal = await service.prepare(
      criterion: 'artist_period',
      artist: 'Band',
      report: sampleReport(),
      catalog: catalog,
      limit: 10,
    );
    expect(personal.ids, ['a']);
    expect(personal.entries.single.title, 'A');
    expect(calls, 1);
  });
  test('radio uses similar artists in the library only; offline reuses similarity data', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    var calls = 0;
    final api = LastFmClient(
      MockClient((r) async {
        calls++;
        expect(r.url.queryParameters['method'], 'artist.getSimilar');
        return http.Response(
          jsonEncode({
            'similarartists': {
              'artist': [
                {'name': 'Guest'},
                {'name': 'Absent'},
              ],
            },
          }),
          200,
        );
      }),
      apiKey: 'fixture',
      apiSecret: '',
    );
    final service = InsightArtistTemplates(store, () async => api);
    for (final offline in [false, true]) {
      final result = await service.prepare(
        criterion: 'artist_radio',
        artist: 'Band',
        report: sampleReport(),
        catalog: catalog,
        limit: 10,
        offline: offline,
      );
      expect(result.ids.toSet(), {'a', 'b'});
      expect(result.unresolved, 0);
    }
    expect(calls, 1);
    await expectLater(
      service.prepare(
        criterion: 'artist_radio',
        artist: 'Other',
        report: sampleReport(),
        catalog: catalog,
        limit: 10,
        offline: true,
      ),
      throwsStateError,
    );
  });
  test('Last.fm review retains expected metadata and recommendations never resolve automatically', () {
    final report = matchLastFmProfile((
      [LastFmTrack('A', 'Band', '', null)],
      [
        catalog[0],
        const Track(id: 'copy', title: 'A', artist: 'Band', album: 'Edition'),
      ],
    ));
    final entry = report.entries.single;
    expect(entry.title, 'A');
    expect(entry.artist, 'Band');
    expect(entry.unresolved, isTrue);
    final missing = PlaylistImportEntry(
      1,
      '/missing/A.mp3',
      [],
      [],
      title: 'A',
      artist: 'Band',
    );
    final suggestions = recommendPlaylistReplacements(([missing], catalog));
    expect(suggestions[1]!.first, 'a');
    expect(missing.selected, isNull);
    expect(missing.reference, '/missing/A.mp3');
  });
  test('sidebar and larger text/artwork settings roundtrip in backup without removing existing preferences', () async {
    SharedPreferences.setMockInitialValues({
      'visual.lyrics_font': 80.0,
      'visual.lyrics_spacing': .8,
      'visual.cover_scale': 2.6,
      'visual.sidebar_order': [
        'insights',
        ...sidebarItems.where((s) => s != 'insights'),
      ],
      'visual.sidebar_items': ['home', 'insights'],
      'visual.font_body': 18.0,
    });
    final prefs = await SharedPreferences.getInstance();
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final parsed = AppData.parse(await AppData.backup(store, prefs));
    expect(parsed['preferences']['visual.sidebar_items'], ['home', 'insights']);
    expect(parsed['preferences']['visual.font_body'], 18.0);
    expect(
      AppData.validPreferenceType('visual.sidebar_order', ['invalid']),
      isFalse,
    );
    expect(
      sidebarOrder(['insights', 'insights', 'invalid']).toSet(),
      sidebarItems.toSet(),
    );
  });
  testWidgets(
    'sidebar organizer reorders, hides and restores items persistently',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        app(SingleChildScrollView(child: SidebarSettings(settings: settings))),
      );
      final row = find.byKey(const ValueKey('sidebar.setting.library'));
      await tester.tap(
        find.descendant(of: row, matching: find.byTooltip('Move up')),
      );
      await tester.pumpAndSettle();
      expect(settings.visualList('sidebar_order', sidebarItems)[1], 'library');
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();
      expect(
        settings.visualList('sidebar_items', sidebarItems),
        isNot(contains('library')),
      );
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
  testWidgets(
    'artist radio template preview saves only catalog IDs after confirmation',
    (tester) async {
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      await tester.runAsync(() => store.addTracks(catalog));
      final api = LastFmClient(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'similarartists': {
                'artist': [
                  {'name': 'Guest'},
                ],
              },
            }),
            200,
          ),
        ),
        apiKey: 'fixture',
        apiSecret: '',
      );
      var saved = 0, played = 0;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => ListeningPlaylistDialog(
                  report: sampleReport(),
                  catalog: catalog,
                  store: store,
                  offlineIds: const {},
                  artistTemplates: InsightArtistTemplates(
                    store,
                    () async => api,
                  ),
                  onPlay: (_, _, _) async {
                    played++;
                  },
                  onSaved: () => saved++,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Artist radio · similar artists').last);
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
      }
      expect(find.text('Max per artist'), findsNothing);
      expect(find.textContaining('2 matched'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Save playlist · 2');
      await tester.ensureVisible(button);
      await tester.tap(button);
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
      }
      expect(saved, 1);
      expect(played, 0);
      await tester.runAsync(() async {
        final rows = await store.database.query('playlist_entries');
        expect(rows.map((r) => r['track_id']).toSet(), {'a', 'b'});
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
    },
  );

  testWidgets(
    'ambiguity dialog shows expected song and offers explicit substitution',
    (tester) async {
      final entry = PlaylistImportEntry(
        1,
        '/missing/A.mp3',
        [],
        [],
        title: 'A',
        artist: 'Band',
      );
      await tester.pumpWidget(
        app(
          PlaylistImportReview(
            report: PlaylistImportReport([entry]),
            tracks: catalog,
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
      }
      expect(find.text('Expected track: A • Band'), findsOneWidget);
      expect(entry.unresolved, isTrue);
      await tester.tap(find.text('Use: A • Band • Album'));
      await tester.pump();
      expect(entry.selected, 'a');
      expect(entry.reference, '/missing/A.mp3');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
