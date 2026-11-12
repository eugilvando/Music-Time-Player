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
        if (request.url.host == 'api.lyrics.ovh') return http.Response('', 404);
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
  test(
    'failure falls back to plain lyrics with attribution and encoded metadata',
    () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        expect(request.headers.containsKey('Authorization'), false);
        if (request.url.host == 'lrclib.net') {
          return http.Response('unavailable', 503);
        }
        expect(request.url.pathSegments, ['v1', 'Artist', 'Song']);
        return http.Response(
          jsonEncode({'lyrics': '[Chorus]\nSynthetic line'}),
          200,
        );
      });
      final result = parseLyrics((await OnlineLyrics(client).load(track))!);
      expect(hosts, ['lrclib.net', 'api.lyrics.ovh']);
      expect(result.source, 'lyrics.ovh');
      expect(result.synchronized, false);
      client.close();
    },
  );
  test('malformed synced lyrics fall back to valid plain lyrics', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'trackName': 'Song',
          'artistName': 'Artist',
          'duration': 180,
          'syncedLyrics': '[00:99.00]Invalid',
          'plainLyrics': 'Synthetic',
        }),
        200,
      ),
    );
    expect(
      parseLyrics((await OnlineLyrics(client).load(track))!).synchronized,
      false,
    );
    client.close();
  });
  test(
    'instrumental exact match does not fetch unrelated plain lyrics',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'trackName': 'Song',
            'artistName': 'Artist',
            'duration': 180,
            'instrumental': true,
          }),
          200,
        );
      });
      expect(await OnlineLyrics(client).load(track), null);
      expect(calls, 1);
      client.close();
    },
  );
  test('unknown duration still supports plain lookup', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.lyrics.ovh');
      return http.Response(jsonEncode({'lyrics': 'Synthetic'}), 200);
    });
    expect(
      await OnlineLyrics(client)
          .load(const Track(id: 'u', title: 'Song', artist: 'Artist')),
      isNotNull,
    );
    client.close();
  });
  test(
    'stalled primary request has a deadline and does not block fallback',
    () async {
      final client = MockClient((request) async {
        if (request.url.host == 'lrclib.net') {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return http.Response('', 404);
        }
        return http.Response(jsonEncode({'lyrics': 'Synthetic'}), 200);
      });
      expect(
        await OnlineLyrics(
          client,
          timeout: const Duration(milliseconds: 20),
        ).load(track),
        contains('lyrics.ovh'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 110));
      client.close();
    },
  );
}
