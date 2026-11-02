import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/insight_artist_templates.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/persistence/library_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('genre and mood match Last.fm tags, cache offline and keep only playable catalog matches', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    var calls = 0;
    final api = LastFmClient(
      MockClient((r) async {
        calls++;
        expect(r.url.queryParameters['method'], 'tag.getTopTracks');
        return http.Response(
          jsonEncode({
            'tracks': {
              'track': [
                {
                  'name': 'Song',
                  'artist': {'name': 'Band'},
                },
                {
                  'name': 'Missing',
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
    const tracks = [
      Track(id: 'hit', title: 'Song', artist: 'Band'),
      Track(id: 'local', title: 'Local', artist: 'Other', genre: 'Rock'),
    ];
    expect(
      (await service.tagPlaylist(
        'rock',
        tracks,
        10,
        genre: true,
        offline: false,
      )).ids,
      ['hit', 'local'],
    );
    expect(
      (await service.tagPlaylist(
        'calm',
        tracks,
        10,
        genre: false,
        offline: false,
      )).ids,
      ['hit'],
    );
    expect(
      (await service.tagPlaylist(
        'calm',
        tracks,
        10,
        genre: false,
        offline: true,
      )).ids,
      ['hit'],
    );
    expect(calls, 2);
  });
}
