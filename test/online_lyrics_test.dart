import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/lyrics/lyrics.dart';
import 'package:music_time/lyrics/online_lyrics.dart';

void main() {
  const track = Track(
    id: 't',
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    duration: Duration(seconds: 180),
  );
  test(
    'LRCLIB accepts only matching artist title and recording length',
    () async {
      var title = 'Song', artist = 'Artist', duration = 180;
      final client = MockClient((request) async {
        expect(request.url.host, 'lrclib.net');
        expect(request.headers.containsKey('Authorization'), false);
        expect(request.url.queryParameters['duration'], '180.0');
        return http.Response(
          jsonEncode({
            'trackName': title,
            'artistName': artist,
            'duration': duration,
            'syncedLyrics': '[00:01.00]Line',
          }),
          200,
        );
      });
      final api = OnlineLyrics(client);
      try {
        final result = await api.load(track);
        expect(result, isNotNull);
        expect(parseLyrics(result!).source, 'LRCLIB');
        title = 'Other';
        expect(await api.load(track), isNull);
        title = 'Song';
        artist = 'Other';
        expect(await api.load(track), isNull);
        artist = 'Artist';
        duration = 200;
        expect(await api.load(track), isNull);
      } finally {
        client.close();
      }
    },
  );
  test('Missing lyrics and failed provider are optional', () async {
    final client = MockClient((request) async => http.Response('', 404));
    try {
      expect(await OnlineLyrics(client).load(track), isNull);
    } finally {
      client.close();
    }
  });
}
