import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/library/artist_ranking.dart';
import 'package:music_time/library/insight_artist_templates.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/artist_featured_tracks.dart';
import 'package:music_time/presentation/compact_media_card.dart';
import 'package:music_time/presentation/queue_drag_row.dart';

void main() {
  const a = Track(id: 'a', title: 'Alpha', artist: 'Band');
  const b = Track(id: 'b', title: 'Beta', artist: 'Band');
  const other = Track(id: 'other', title: 'Alpha', artist: 'Other');
  final stats = <String, Map<String, Object?>>{
    'b': {'play_count': 100},
    'a': {'play_count': 2},
  };
  test('global ranking wins, unrelated artists excluded, local fills, deduplicated', () {
    final result = rankArtistTracks(
      artist: 'Band',
      eligible: [b, other, a, a],
      stats: stats,
      ranking: [
        LastFmTrack('Missing', 'Band', '', null),
        LastFmTrack('Alpha', 'Other', '', null),
        LastFmTrack('Alpha', 'Band', '', null),
        LastFmTrack('Alpha', 'Band', '', null),
      ],
    );
    expect(result.tracks.map((t) => t.id), ['a', 'b']);
    expect(result.remoteMatches, 1);
    expect(
      rankArtistTracks(
        artist: 'Band',
        eligible: [a, other, b],
        stats: stats,
      ).tracks,
      [b, a],
    );
  });
  test('20-item limit, missing/hidden exclusion and empty pool', () {
    final catalog = [
      for (var i = 0; i < 25; i++) Track(id: '$i', title: '$i', artist: 'Band'),
      const Track(
        id: 'hidden',
        title: 'Hidden',
        artist: 'Band',
        libraryHidden: true,
      ),
      const Track(
        id: 'missing',
        title: 'Missing',
        artist: 'Band',
        available: false,
      ),
    ];
    final result = rankArtistTracks(
      artist: 'Band',
      eligible: catalog,
      stats: {},
    );
    expect(result.tracks.length, 20);
    expect(result.tracks.any((t) => !t.available || t.libraryHidden), false);
    expect(
      rankArtistTracks(artist: 'Unknown', eligible: catalog, stats: {}).tracks,
      isEmpty,
    );
  });
  test(
    'track and album reference retain one artist; compilations need choice',
    () {
      expect(mixSeedArtist([a]), 'Band');
      expect(mixSeedArtist([a, b]), 'Band');
      expect(mixSeedArtist([a, other]), '');
      expect(
        mixSeedArtist([
          const Track(
            id: '1',
            title: 'One',
            artist: 'A',
            albumArtist: 'Various Artists',
          ),
          const Track(
            id: '2',
            title: 'Two',
            artist: 'B',
            albumArtist: 'Various Artists',
          ),
        ]),
        '',
      );
    },
  );
  test(
    'Last.fm API cached/offline/refresh/error all preserve ranked local scope',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.database.close);
      var calls = 0, fail = false;
      final api = LastFmClient(
        MockClient((request) async {
          calls++;
          expect(request.url.queryParameters['method'], 'artist.getTopTracks');
          if (fail) return http.Response('{}', 503);
          return http.Response(
            jsonEncode({
              'toptracks': {
                'track': [
                  {
                    'name': 'Alpha',
                    'artist': {'name': 'Band'},
                  },
                ],
              },
            }),
            200,
          );
        }),
        apiKey: 'test',
        apiSecret: 'test',
      );
      final service = InsightArtistTemplates(store, () async => api);
      expect((await service.rankedArtist('Band', [a, b, other], 20)).tracks, [
        a,
        b,
      ]);
      expect(calls, 1);
      await service.rankedArtist('Band', [a, b], 20, offline: true);
      expect(calls, 1);
      await service.rankedArtist('Band', [a, b], 20, refresh: true);
      expect(calls, 2);
      fail = true;
      expect(
        (await service.rankedArtist(
          'Band',
          [a, b, other],
          20,
          refresh: true,
        )).tracks,
        [a, b],
      );
      expect(
        (await service.rankedArtist(
          'Other',
          [a, b, other],
          20,
          refresh: true,
        )).tracks,
        [other],
      );
    },
  );
  testWidgets(
    '20 featured cards, icon actions and track drag deliver ranked tracks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tracks = [
        for (var i = 0; i < 25; i++)
          Track(id: '$i', title: 'Song $i', artist: 'Band'),
      ];
      List<Track>? played, shuffled, dropped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: ArtistFeaturedTracks(
                      artist: 'Band',
                      tracks: tracks,
                      stats: {},
                      offline: false,
                      load: (_, items, limit, refresh) async => (
                        tracks: items.reversed.take(limit).toList(),
                        remoteMatches: 20,
                      ),
                      actions: (_) => const SizedBox(),
                      onPlay: (items, _) async {
                        played = items;
                      },
                      onShuffle: (items) async {
                        shuffled = items;
                      },
                    ),
                  ),
                ),
                DragTarget<List<Track>>(
                  onAcceptWithDetails: (d) => dropped = d.data,
                  builder: (_, __, ___) => const SizedBox(
                    height: 100,
                    width: 1200,
                    child: Text('Queue target'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CompactMediaCard), findsNWidgets(20));
      await tester.tap(find.byKey(const ValueKey('artist.featured.play')));
      expect(played!.length, 20);
      expect(played!.first.id, '24');
      await tester.tap(find.byKey(const ValueKey('artist.featured.shuffle')));
      expect(shuffled, played);
      final start = tester.getCenter(find.text('Song 24'));
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('Queue target')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(dropped!.single.id, '24');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late old-artist ranking cannot replace current artist', (
    tester,
  ) async {
    final pending = Completer<ArtistRankedTracks>();
    Widget view(String artist, List<Track> tracks) => MaterialApp(
      home: Scaffold(
        body: ArtistFeaturedTracks(
          artist: artist,
          tracks: tracks,
          stats: {},
          offline: false,
          actions: (_) => const SizedBox(),
          load: (name, items, limit, refresh) => name == 'Band'
              ? pending.future
              : Future.value((tracks: items, remoteMatches: 1)),
          onPlay: (_, __) async {},
          onShuffle: (_) async {},
        ),
      ),
    );
    await tester.pumpWidget(view('Band', [a, b]));
    await tester.pumpWidget(view('Other', [other]));
    await tester.pumpAndSettle();
    pending.complete((tracks: [b], remoteMatches: 1));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Other'), findsOneWidget);
  });
  testWidgets('queue reorders by row text and retains normal taps/actions', (
    tester,
  ) async {
    final items = ['A', 'B', 'C'];
    var taps = 0, actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: items.length,
              onReorderItem: (oldIndex, newIndex) => setState(() {
                final value = items.removeAt(oldIndex);
                items.insert(newIndex, value);
              }),
              itemBuilder: (context, i) => QueueDragRow(
                key: ValueKey(items[i]),
                index: i,
                child: ListTile(
                  title: Text('Track ${items[i]}'),
                  onTap: () => taps++,
                  trailing: IconButton(
                    icon: const Icon(Icons.more_horiz),
                    onPressed: () => actions++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Track A'));
    expect(taps, 1);
    await tester.tap(find.byType(IconButton).first);
    expect(actions, 1);
    final target = tester.getBottomLeft(find.text('Track C')) + const Offset(0, 55);
    final drag = await tester.startGesture(tester.getCenter(find.text('Track A')));
    await drag.moveBy(const Offset(0, 25));
    await tester.pump(const Duration(milliseconds: 300));
    await drag.moveTo(target);
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    await tester.pumpAndSettle();
    expect(items, ['B', 'C', 'A']);
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
