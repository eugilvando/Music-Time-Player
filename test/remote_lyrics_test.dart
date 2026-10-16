import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/domain/ports.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/infrastructure/onedrive.dart';
import 'package:music_time/lyrics/id3_lyrics.dart';
import 'package:music_time/lyrics/lyrics_loader.dart';

class _Tokens implements AccessTokenProvider {
  @override
  Future<String> accessToken() async => 'test-token';
}

List<int> _safe(int n) => [
  for (final shift in [21, 14, 7, 0]) n >> shift & 127,
];
Uint8List _tag(List<int> payload, {int version = 3, String frame = 'USLT'}) {
  final length = version == 4
      ? _safe(payload.length)
      : (ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List();
  final body = [...ascii.encode(frame), ...length, 0, 0, ...payload];
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    version,
    0,
    0,
    ..._safe(body.length),
    ...body,
  ]);
}

void main() {
  test('ID3 v2.3 and v2.4 read UTF8 USLT and skip description', () {
    for (final version in [3, 4]) {
      final bytes = _tag([
        3,
        ...ascii.encode('eng'),
        ...utf8.encode('Description'),
        0,
        ...utf8.encode('First line\nSecond line'),
      ], version: version);
      expect(embeddedId3Lyrics(bytes), 'First line\nSecond line');
    }
  });
  test('UTF16 sidecars and big endian embedded descriptions retain text', () {
    expect(decodeLyricsBytes([255, 254, 72, 0, 105, 0]), 'Hi');
    expect(decodeLyricsBytes([254, 255, 0, 72, 0, 105]), 'Hi');
    final bytes = _tag([
      1,
      ...ascii.encode('eng'),
      254,
      255,
      0,
      68,
      0,
      0,
      0,
      72,
      0,
      105,
    ]);
    expect(embeddedId3Lyrics(bytes), 'Hi');
    expect(decodeLyricsBytes([0x63, 0x61, 0x66, 0xe9]), 'caf\u00e9');
  });
  test('TXXX lyrics and malformed tags are handled without audio reads', () {
    expect(
      embeddedId3Lyrics(
        _tag([
          3,
          ...ascii.encode('LYRICS'),
          0,
          ...utf8.encode('[00:01.00]Line'),
        ], frame: 'TXXX'),
      ),
      '[00:01.00]Line',
    );
    expect(embeddedId3Lyrics(Uint8List(9)), isNull);
    final bad = _tag([3, ...ascii.encode('eng'), 0, 72]);
    bad[6] = 255;
    expect(embeddedId3Lyrics(bad), isNull);
    expect(
      embeddedId3Lyrics(
        Uint8List.fromList(
          _tag([3, ...ascii.encode('eng'), 0, 72]).take(16).toList(),
        ),
      ),
      isNull,
    );
  });
  test(
    'invalid sidecar falls back to embedded MP3, UTF16 sidecar wins',
    () async {
      final dir = await Directory.systemTemp.createTemp('music-time-lyrics-');
      try {
        final audio = File('${dir.path}/song.mp3');
        await audio.writeAsBytes(
          _tag([3, ...ascii.encode('eng'), 0, ...utf8.encode('Embedded')]),
        );
        final sidecar = File('${dir.path}/song.lrc');
        await sidecar.writeAsString('[00:99.00]Broken');
        final track = Track(
          id: 'local',
          title: 'Song',
          artist: 'Artist',
          localPath: audio.path,
        );
        expect((await loadLocalLyrics(track))!.lines.single.text, 'Embedded');
        const line = '[00:01.00]Sidecar';
        await sidecar.writeAsBytes([
          255,
          254,
          for (final unit in line.codeUnits) ...[unit & 255, unit >> 8],
        ]);
        expect((await loadLocalLyrics(track))!.lines.single.text, 'Sidecar');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  const track = Track(
    id: 'cloud',
    title: 'Song',
    artist: 'Artist',
    driveId: 'drive-a',
    itemId: 'audio-a',
    fileName: 'Song.mp3',
  );
  test('OneDrive same-name sidecar uses parent and never sends bearer to download host', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.host == 'graph.microsoft.com') {
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.url.path.endsWith('/audio-a')) {
          return http.Response(
            jsonEncode({
              'name': 'Song.mp3',
              'parentReference': {'id': 'folder-a'},
            }),
            200,
          );
        }
        expect(request.url.path, endsWith('/folder-a:/Song.lrc'));
        return http.Response(
          jsonEncode({
            'size': 20,
            '@microsoft.graph.downloadUrl': 'https://download.example/lyrics',
          }),
          200,
        );
      }
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response('[00:01.00]Remote', 200);
    });
    expect(
      await OneDriveClient(client, _Tokens()).lyrics(track),
      '[00:01.00]Remote',
    );
    expect(paths.length, 3);
    client.close();
  });
  test('missing OneDrive sidecars fall back to bounded MP3 ranges', () async {
    final tag = _tag([
      3,
      ...ascii.encode('eng'),
      0,
      ...utf8.encode('Embedded remote'),
    ]);
    final ranges = <String>[];
    final client = MockClient((request) async {
      if (request.url.host == 'graph.microsoft.com') {
        if (request.url.path.endsWith('/audio-a')) {
          return http.Response(
            jsonEncode({
              'name': 'Song.mp3',
              'parentReference': {'id': 'folder-a'},
              '@microsoft.graph.downloadUrl': 'https://download.example/audio',
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }
      expect(request.headers.containsKey('Authorization'), isFalse);
      final range = request.headers['Range']!;
      ranges.add(range);
      final numbers = RegExp(r'\d+')
          .allMatches(range)
          .map((m) => int.parse(m[0]!))
          .toList();
      return http.Response.bytes(
        tag.sublist(numbers[0], numbers[1] + 1),
        206,
        headers: {
          'content-range':
              'bytes ${numbers[0]}-${numbers[1]}/${tag.length + 1000}',
        },
      );
    });
    expect(
      await OneDriveClient(client, _Tokens()).lyrics(track),
      'Embedded remote',
    );
    expect(ranges, ['bytes=0-9', 'bytes=10-${tag.length - 1}']);
    client.close();
  });
}
