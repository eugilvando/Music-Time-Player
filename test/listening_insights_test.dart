import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/library/listening_insights.dart';
import 'package:music_time/library/listening_playlist.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/listening_insights_page.dart';

final from = DateTime.utc(2026, 10, 1), until = DateTime.utc(2026, 10, 31);
Map<String, Object?> event(
  String title,
  DateTime date, {
  String artist = 'Band',
  String album = 'Album',
}) => {
  'name': title,
  'artist': {'#text': artist},
  'album': {'#text': album},
  'date': {'uts': '${date.millisecondsSinceEpoch ~/ 1000}'},
};
http.Response page(int number, int total, List<Object?> events) =>
    http.Response(
      jsonEncode({
        'recenttracks': {
          '@attr': {'page': '$number', 'totalPages': '$total'},
          'track': events,
        },
      }),
      200,
    );

ListeningReport sampleReport({bool complete = true}) => aggregateListening((
  base: null,
  user: 'fixture',
  from: from,
  until: until,
  previousFrom: from.subtract(until.difference(from)),
  events: [
    LastFmTrack('A', 'Band', 'Album', DateTime.utc(2026, 10, 2)),
    LastFmTrack('B', 'Guest', 'Other', DateTime.utc(2026, 10, 3)),
    LastFmTrack('Old', 'Band', 'Album', DateTime.utc(2026, 9, 20)),
  ],
  nextPage: 2,
  totalPages: 1,
  complete: complete,
  invalid: 0,
));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pagination preserves repeated scrobbles, bounds and previous period',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final calls = <Uri>[];
      final api = LastFmClient(
        MockClient((request) async {
          calls.add(request.url);
          final n = int.parse(request.url.queryParameters['page']!);
          return page(
            n,
            2,
            n == 1
                ? [
                    event('A', from),
                    event('A', from),
                    {
                      ...event('Active', from),
                      '@attr': {'nowplaying': 'true'},
                    },
                    event('Outside', until),
                  ]
                : [
                    event('Old', DateTime.utc(2026, 9, 20)),
                    event('Old', DateTime.utc(2026, 9, 20)),
                  ],
          );
        }),
        apiKey: 'test',
        apiSecret: '',
      );
      final repo = ListeningInsightsRepository(store, () async => api);
      final result = await repo.load(
        user: 'fixture',
        period: '30',
        from: from,
        until: until,
        request: ListeningRequest(),
      );
      expect(calls.length, 2);
      expect(
        calls.first.queryParameters['to'],
        '${until.millisecondsSinceEpoch ~/ 1000}',
      );
      expect(result.scrobbles, 2);
      expect(result.previousScrobbles, 2);
      expect(result.tracks.single.count, 2);
      expect(result.complete, true);
      expect((await repo.cached('fixture', '30'))!.scrobbles, 2);
      expect(await repo.cached('another-user', '30'), isNull);
      expect(await repo.cached('fixture', '7'), isNull);
      expect(await store.database.query('history'), isEmpty);
    },
  );
  test(
    'page budget is explicit and continuation resumes without double counting',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final called = <int>[];
      final repo = ListeningInsightsRepository(
        store,
        () async => LastFmClient(
          MockClient((req) async {
            final n = int.parse(req.url.queryParameters['page']!);
            called.add(n);
            return page(n, 3, [event('Song $n', DateTime.utc(2026, 10, n))]);
          }),
          apiKey: 'test',
          apiSecret: '',
        ),
      );
      final first = await repo.load(
        user: 'fixture',
        period: '30',
        from: from,
        until: until,
        request: ListeningRequest(),
        pageBudget: 1,
      );
      expect(first.complete, false);
      expect(first.nextPage, 2);
      final rest = await repo.load(
        user: 'fixture',
        period: '30',
        from: from,
        until: until,
        request: ListeningRequest(),
        resume: first,
      );
      expect(called, [1, 2, 3]);
      expect(rest.scrobbles, 3);
      expect(rest.complete, true);
      await expectLater(
        repo.load(
          user: 'other',
          period: '30',
          from: from,
          until: until,
          request: ListeningRequest(),
          resume: first,
        ),
        throwsArgumentError,
      );
    },
  );
  test('cancelled reading does not commit partial results', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final token = ListeningRequest();
    var calls = 0;
    final repo = ListeningInsightsRepository(
      store,
      () async => LastFmClient(
        MockClient((req) async {
          calls++;
          return page(1, 2, [event('A', from)]);
        }),
        apiKey: 'test',
        apiSecret: '',
      ),
    );
    await expectLater(
      repo.load(
        user: 'fixture',
        period: '30',
        from: from,
        until: until,
        request: token,
        onProgress: (_, _) => token.cancelled = true,
      ),
      throwsA(isA<ListeningCancelled>()),
    );
    expect(calls, 1);
    expect(await repo.cached('fixture', '30'), isNull);
  });
  test(
    'malformed pagination and a changed history do not replace valid cache',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      var bad = false;
      final repo = ListeningInsightsRepository(
        store,
        () async => LastFmClient(
          MockClient((req) async {
            if (!bad) return page(1, 1, [event('A', from)]);
            final n = int.parse(req.url.queryParameters['page']!);
            return page(n, n == 1 ? 2 : 3, [event('B', from)]);
          }),
          apiKey: 'test',
          apiSecret: '',
        ),
      );
      await repo.load(
        user: 'fixture',
        period: '30',
        from: from,
        until: until,
        request: ListeningRequest(),
      );
      bad = true;
      await expectLater(
        repo.load(
          user: 'fixture',
          period: '30',
          from: from,
          until: until,
          request: ListeningRequest(),
        ),
        throwsFormatException,
      );
      expect((await repo.cached('fixture', '30'))!.tracks.single.title, 'A');
    },
  );
  test(
    'invalid dated rows are visible as gaps; now playing is not an error',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final repo = ListeningInsightsRepository(
        store,
        () async => LastFmClient(
          MockClient(
            (_) async => page(1, 1, [
              {'name': 'Bad'},
              {
                'name': 'Active',
                '@attr': {'nowplaying': 'true'},
              },
              event('A', from),
            ]),
          ),
          apiKey: 'test',
          apiSecret: '',
        ),
      );
      final result = await repo.load(
        user: 'fixture',
        period: '30',
        from: from,
        until: until,
        request: ListeningRequest(),
      );
      expect(result.invalid, 1);
      expect(result.scrobbles, 1);
    },
  );
  test('selection is conservative, bounded and rediscovery needs complete coverage', () {
    const catalog = [
      Track(id: 'a', title: 'A', artist: 'Band', album: 'Album'),
      Track(id: 'b', title: 'B', artist: 'Guest', album: 'Other'),
      Track(id: 'old', title: 'Old', artist: 'Band', album: 'Album'),
      Track(id: 'live', title: 'A (Live)', artist: 'Band', album: 'Album'),
    ];
    final report = sampleReport();
    final top = prepareListeningPlaylist((
      report: report,
      catalog: catalog,
      criterion: 'top',
      limit: 30,
      perArtist: 1,
    ));
    expect(top.ids, ['a', 'b']);
    expect(top.ids, isNot(contains('live')));
    final old = prepareListeningPlaylist((
      report: report,
      catalog: catalog,
      criterion: 'rediscover',
      limit: 30,
      perArtist: 3,
    ));
    expect(old.ids, ['old']);
    expect(
      () => prepareListeningPlaylist((
        report: sampleReport(complete: false),
        catalog: catalog,
        criterion: 'rediscover',
        limit: 30,
        perArtist: 3,
      )),
      throwsStateError,
    );
    final ambiguous = prepareListeningPlaylist((
      report: report,
      catalog: [
        ...catalog,
        const Track(id: 'copy', title: 'A', artist: 'Band', album: 'Album'),
      ],
      criterion: 'top',
      limit: 30,
      perArtist: 3,
    ));
    expect(ambiguous.unresolved, 1);
    final empty = prepareListeningPlaylist((
      report: report,
      catalog: <Track>[],
      criterion: 'top',
      limit: 30,
      perArtist: 3,
    ));
    expect(empty.ids, isEmpty);
    expect(empty.unresolved, 2);
  });
  test('CSV escapes metadata and marks incomplete coverage', () {
    expect(listeningCsvCell('=SUM(1,2)'), '"\'=SUM(1,2)"');
    expect(listeningCsvCell('A "quote"'), '"A ""quote"""');
    final csv = listeningReportCsv(sampleReport(complete: false));
    expect(csv, contains('"Coverage","partial"'));
    expect(csv, contains('"Track","A","Band","1"'));
    expect(csv, contains('"Last.fm profile","fixture"'));
  });
}
