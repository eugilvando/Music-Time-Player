import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/artist_selection.dart';
import 'package:music_time/library/artist_similarity.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/settings/app_settings.dart';

void main() {
  test(
    'ambiguous spelling variants are not merged into radio automatically',
    () {
      const main = Track(id: 'main', title: 'Main', artist: 'Seed');
      const a = Track(id: 'a', title: 'A', artist: 'Similar');
      const b = Track(id: 'b', title: 'B', artist: 'SIMILAR');
      expect(
        artistSelection(
          [main, a, b],
          'Seed',
          radio: true,
          similar: ['Similar'],
        ),
        isEmpty,
      );
    },
  );
  const main = Track(id: 'a', title: 'A', artist: 'Main; Guest');
  const other = Track(id: 'b', title: 'B', artist: 'Related');
  const unrelated = Track(id: 'c', title: 'C', artist: 'Else', genre: 'Same');
  test(
    'artist mix is credit-only, finite, accepts one item and deduplicates',
    () {
      final result = artistSelection(
        [main, other, main, unrelated],
        'Guest',
        random: Random(1),
      );
      expect(result.map((t) => t.id), ['a']);
      expect(artistSelection([other], 'Main'), isEmpty);
      expect(artistSelection([main], 'Main', count: 1), [main]);
      expect(
        () => artistSelection([main], 'Main', count: 501),
        throwsRangeError,
      );
    },
  );
  test('radio needs real known similar artists, guarantees main and excludes fuzzy matches', () {
    expect(
      artistSelection([main, other, unrelated], 'Main', radio: true),
      isEmpty,
    );
    final result = artistSelection(
      [main, other, unrelated],
      'Main',
      radio: true,
      similar: ['Related'],
      random: Random(2),
    );
    expect(result.map((t) => t.id), ['a', 'b']);
    expect(
      artistSelection([main, other], 'Main', radio: true, similar: ['Reláted']),
      isEmpty,
    );
    expect(
      artistSelection([other], 'Main', radio: true, similar: ['Related']),
      isEmpty,
    );
  });
  test(
    'radio round robin distributes main and similar artists without padding',
    () {
      final tracks = [
        for (final a in ['Main', 'One', 'Two'])
          for (var i = 0; i < 20; i++)
            Track(id: '$a$i', title: '$i', artist: a),
      ];
      final result = artistSelection(
        tracks,
        'Main',
        count: 12,
        radio: true,
        similar: ['One', 'Two'],
        random: Random(9),
      );
      expect(
        result.map((t) => t.artist).toList(),
        List.generate(12, (i) => ['Main', 'One', 'Two'][i % 3]),
      );
      expect(result.map((t) => t.id).toSet().length, 12);
      expect(
        artistSelection(
          tracks,
          'Main',
          count: 12,
          radio: true,
          similar: ['One', 'Two'],
          random: Random(9),
        ),
        result,
      );
    },
  );
  test('offline eligibility and saved settings are independent of existing selections', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(prefs);
    final snapshot = artistSelection([main, other], 'Main');
    expect(settings.artistSelectionSize(), 40);
    expect(settings.artistSelectionSize(radio: true), 40);
    await settings.setArtistSelectionSize(120, radio: true);
    expect(AppSettings(prefs).artistSelectionSize(radio: true), 120);
    expect(
      AppData.validPreferenceType('visual.artist_radio_size', 120.0),
      isTrue,
    );
    expect(AppData.validPreferenceType('visual.artist_mix_size', 0.0), isFalse);
    expect(() => settings.setArtistSelectionSize(0), throwsRangeError);
    expect(eligibleArtistTracks([main, other], {'b'}, offlineOnly: true), [
      other,
    ]);
    expect(
      artistSelection(
        eligibleArtistTracks([main, other], {'b'}, offlineOnly: true),
        'Main',
      ),
      isEmpty,
    );
    expect(snapshot, [main]);
    settings.dispose();
  });
  test(
    'Last.fm read-only similarity is coalesced, cached and usable offline',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      var requests = 0;
      final client = MockClient((r) async {
        requests++;
        expect(r.url.queryParameters['method'], 'artist.getSimilar');
        expect(r.url.queryParameters['autocorrect'], '0');
        expect(r.url.queryParameters.containsKey('sk'), isFalse);
        return http.Response(
          '{"similarartists":{"artist":[{"name":"Related"}]}}',
          200,
        );
      });
      addTearDown(client.close);
      final similarity = ArtistSimilarity(
        store,
        () async => LastFmClient(client, apiKey: 'test', apiSecret: ''),
      );
      final result = await Future.wait([
        similarity.names('Main'),
        similarity.names('Main'),
      ]);
      expect(result, [
        ['Related'],
        ['Related'],
      ]);
      expect(requests, 1);
      expect(await similarity.names('Main', offline: true), ['Related']);
      await store.database.update('artist_similarity_cache', {
        'updated_at': '2000-01-01T00:00:00Z',
      });
      final unavailable = ArtistSimilarity(
        store,
        () async => throw StateError('network'),
      );
      expect(await unavailable.names('Main'), ['Related']);
      expect(await unavailable.names('Unknown'), isEmpty);
    },
  );
}
