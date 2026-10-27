import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/library/artist_selection.dart';
import 'package:music_time/library/artist_similarity.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/artist_selection_dialog.dart';
import 'package:music_time/settings/app_settings.dart';

import 'catalog_widget_test.dart' show waitForCatalog;

void main() {
  const main = Track(
    id: 'main',
    title: 'Main song',
    artist: 'Main; Guest',
    albumArtist: 'Owner',
    genre: 'Rock',
  );
  const related = Track(
    id: 'related',
    title: 'Related song',
    artist: 'Related',
    genre: 'rock',
  );
  const other = Track(
    id: 'other',
    title: 'Other song',
    artist: 'Other',
    genre: 'Jazz',
  );
  test('artist navigation prefers the first album artist and falls back to track artist', () {
    expect(navigationArtistName(main), 'Owner');
    expect(
      navigationArtistName(
        const Track(
          id: 'explicit',
          title: 'X',
          artist: 'Legacy',
          artists: ['First', 'Second'],
        ),
      ),
      'First',
    );
    expect(
      navigationArtistName(
        const Track(id: 'x', title: 'X', artist: 'First; Second'),
      ),
      'First',
    );
    expect(
      navigationArtistName(
        const Track(
          id: 'x',
          title: 'X',
          artist: 'First; Second',
          albumArtists: ['Album owner', 'Guest'],
        ),
      ),
      'Album owner',
    );
  });
  test('item mix keeps the selected track first and uses related eligible library tracks', () {
    final preview = prepareItemPreview((
      work: (
        tracks: [main, related, other],
        artist: 'Main',
        count: 40,
        radio: false,
        local: false,
        similar: <String>[],
      ),
      seeds: [main],
    ));
    expect(preview.tracks.first.id, 'main');
    expect(preview.tracks.map((t) => t.id), ['main', 'related']);
    expect(
      prepareItemPreview((
        work: (
          tracks: [main],
          artist: 'Main',
          count: 40,
          radio: false,
          local: false,
          similar: <String>[],
        ),
        seeds: [main],
      )).tracks,
      [main],
    );
  });
  test('album and track radio keep an eligible seed and reject unavailable seed items', () {
    const second = Track(
      id: 'second',
      title: 'Second',
      artist: 'Main',
      albumArtist: 'Owner',
    );
    final work = (
      tracks: [main, second, related],
      artist: 'Owner',
      count: 40,
      radio: true,
      local: false,
      similar: ['Related'],
    );
    final preview = prepareItemPreview((work: work, seeds: [main, second]));
    expect(preview.tracks.first.id, 'main');
    expect(
      preview.tracks.map((t) => t.id),
      unorderedEquals(['main', 'second', 'related']),
    );
    expect(prepareItemPreview((work: work, seeds: [other])).tracks, isEmpty);
    for (var i = 0; i < 10; i++) {
      final small = prepareItemPreview((
        work: (
          tracks: work.tracks,
          artist: work.artist,
          count: 2,
          radio: true,
          local: false,
          similar: work.similar,
        ),
        seeds: [main],
      ));
      expect(small.tracks.map((t) => t.id), ['main', 'related']);
    }
  });
  testWidgets(
    'item mix starts its named queue directly without a playlist or a Last.fm request',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      List<Track>? queue;
      String? title;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showArtistSelection(
                  context,
                  artist: 'Main',
                  radio: false,
                  action: 'play',
                  seeds: [main],
                  seedLabel: main.title,
                  eligible: [main, related, other],
                  settings: settings,
                  similarity: ArtistSimilarity(
                    store,
                    () async => throw StateError('item mix must work locally'),
                  ),
                  onPlay: (tracks, _, name) async {
                    queue = tracks;
                    title = name;
                  },
                  onSave: (_) async {
                    saves++;
                  },
                ),
                child: const Text('Open item'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open item'));
      await waitForCatalog(tester, () => queue != null);
      expect(queue!.map((t) => t.id), ['main', 'related']);
      expect(title, 'Local item mix · Main song');
      expect(saves, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
      settings.dispose();
    },
  );
  test('local radio is bounded, credit/genre based and does not invent unrelated tracks', () {
    expect(localSimilarArtists([main], 'Main'), isEmpty);
    final result = prepareArtistPreview((
      tracks: [main, related, other],
      artist: 'Main',
      count: 40,
      radio: true,
      local: true,
      similar: <String>[],
    ));
    expect(
      result.tracks.map((t) => t.id),
      unorderedEquals(['main', 'related']),
    );
    expect(result.matched, greaterThan(0));
    expect(result.tracks.map((t) => t.id).toSet().length, result.tracks.length);
    expect(
      prepareArtistPreview((
        tracks: [main],
        artist: 'Missing',
        count: 40,
        radio: false,
        local: false,
        similar: <String>[],
      )).tracks,
      isEmpty,
    );
  });
  test('empty cache expires early, manual refresh bypasses it, and empty replies preserve useful data', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    var requests = 0;
    var empty = true;
    final client = MockClient((_) async {
      requests++;
      return http.Response(
        empty ? '{"similarartists":{"artist":[]}}' : '{"similarartists":{"artist":[{"name":"Related"},{"name":"RELATED"}]}}',
        200,
      );
    });
    addTearDown(client.close);
    final similarity = ArtistSimilarity(
      store,
      () async => LastFmClient(client, apiKey: 'test', apiSecret: ''),
    );
    expect((await similarity.lookup('Main')).issue, SimilarityIssue.noResults);
    await similarity.lookup('Main');
    expect(requests, 1);
    await store.database.update('artist_similarity_cache', {
      'updated_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 20))
          .toIso8601String(),
    });
    empty = false;
    expect((await similarity.lookup('Main')).names, ['Related']);
    expect(requests, 2);
    empty = true;
    final stale = await similarity.lookup('Main', refresh: true);
    expect(stale.names, ['Related']);
    expect(stale.cached, isTrue);
    expect(requests, 3);
  });
  test(
    'missing key is distinguished, and malformed cache can recover',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final client = MockClient(
        (_) async => http.Response(
          '{"similarartists":{"artist":[{"name":"Related"}]}}',
          200,
        ),
      );
      addTearDown(client.close);
      final missing = ArtistSimilarity(
        store,
        () async => LastFmClient(client, apiKey: '', apiSecret: ''),
      );
      expect((await missing.lookup('Main')).issue, SimilarityIssue.missingKey);
      await store.database.rawInsert(
        'INSERT OR REPLACE INTO artist_similarity_cache VALUES(?,?,?)',
        ['main', 'invalid json', 'bad date'],
      );
      final valid = ArtistSimilarity(
        store,
        () async => LastFmClient(client, apiKey: 'test', apiSecret: ''),
      );
      expect((await valid.lookup('Main')).names, ['Related']);
    },
  );
  test('transient server failure retries once and succeeds', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    var requests = 0;
    final client = MockClient(
      (_) async => ++requests == 1
          ? http.Response('', 503)
          : http.Response(
              '{"similarartists":{"artist":[{"name":"Related"}]}}',
              200,
            ),
    );
    addTearDown(client.close);
    final similarity = ArtistSimilarity(
      store,
      () async => LastFmClient(client, apiKey: 'test', apiSecret: ''),
    );
    expect((await similarity.lookup('Main')).names, ['Related']);
    expect(requests, 2);
  });
  test(
    'offline request does not join or await a pending online lookup',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final started = Completer<void>(), response = Completer<http.Response>();
      final client = MockClient((_) {
        started.complete();
        return response.future;
      });
      addTearDown(client.close);
      final similarity = ArtistSimilarity(
        store,
        () async => LastFmClient(client, apiKey: 'test', apiSecret: ''),
      );
      final online = similarity.lookup('Main');
      await started.future;
      final offline = await similarity
          .lookup('Main', offline: true)
          .timeout(const Duration(seconds: 2));
      expect(offline.issue, SimilarityIssue.offline);
      expect(offline.names, isEmpty);
      response.complete(
        http.Response(
          '{"similarartists":{"artist":[{"name":"Related"}]}}',
          200,
        ),
      );
      expect((await online).names, ['Related']);
    },
  );
  testWidgets(
    'local radio is explicitly chosen and starts a named queue without saving a playlist',
    (tester) async {
      tester.view.physicalSize = const Size(480, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({'visual.offline_only': true});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      var saves = 0;
      List<Track>? queue;
      String? title;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showArtistSelection(
                  context,
                  artist: 'Main',
                  radio: true,
                  action: 'preview',
                  eligible: [main, related, other],
                  settings: settings,
                  similarity: ArtistSimilarity(
                    store,
                    () async => throw StateError('must stay offline'),
                  ),
                  onPlay: (tracks, _, name) async {
                    queue = tracks;
                    title = name;
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
        () =>
            find.text('2 tracks / 40 requested').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(queue, isNull);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(queue!.map((t) => t.id), unorderedEquals(['main', 'related']));
      expect(title, 'Local artist radio · Main');
      expect(saves, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
      settings.dispose();
    },
  );
  testWidgets(
    'item mix prefers Last.fm by default and only uses local fallback when needed',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response(
          '{"similarartists":{"artist":[{"name":"Other"}]}}',
          200,
        );
      });
      addTearDown(client.close);
      List<Track>? queue;
      String? title;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showArtistSelection(
                  context,
                  artist: 'Main',
                  radio: false,
                  action: 'play',
                  seeds: [main],
                  seedLabel: main.title,
                  eligible: [main, other],
                  settings: settings,
                  similarity: ArtistSimilarity(
                    store,
                    () async =>
                        LastFmClient(client, apiKey: 'test', apiSecret: ''),
                  ),
                  onPlay: (tracks, _, name) async {
                    queue = tracks;
                    title = name;
                  },
                  onSave: (_) async {
                    fail('No automatic playlist');
                  },
                ),
                child: const Text('Create'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Create'));
      await waitForCatalog(tester, () => queue != null);
      expect(requests, 1);
      expect(queue!.map((t) => t.id), ['main', 'other']);
      expect(title, 'Item mix · Main song');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
      settings.dispose();
    },
  );
}
