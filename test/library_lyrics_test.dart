import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/lyrics/library_lyrics.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/offline/media_cache.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/provider_connections.dart';

class Sources extends Fake implements ProviderConnections {
  Sources(this.preferences, this.client);
  @override
  final SharedPreferences preferences;
  @override
  final http.Client client;
  int calls = 0;
  @override
  Future<String?> lyrics(Track track) async {
    calls++;
    return null;
  }
}

class Store extends Fake implements LibraryStore {
  Map<String, Object?>? row;
  @override
  Future<Map<String, Object?>?> offlineFile(String id) async => row;
}

class Downloads extends Fake implements DownloadManager {
  Downloads(this.store, this.remote);
  @override
  final Store store;
  @override
  final Sources remote;
  @override
  bool offlineOnly = false;
  @override
  MediaCache? get cache => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Downloads downloads;
  late LibraryLyrics lyrics;
  var requests = 0;
  const track = Track(
    id: 'test',
    title: 'Song',
    artist: 'Artist',
    duration: Duration(seconds: 180),
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mt-lyrics-pipeline-');
    SharedPreferences.setMockInitialValues({});
    requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response(
        jsonEncode({
          'trackName': 'Song',
          'artistName': 'Artist',
          'duration': 180,
          'plainLyrics': 'Synthetic online',
        }),
        200,
      );
    });
    downloads = Downloads(
      Store(),
      Sources(await SharedPreferences.getInstance(), client),
    );
    lyrics = LibraryLyrics(downloads, cacheDirectory: () async => dir);
  });
  tearDown(() async {
    lyrics.dispose();
    downloads.remote.client.close();
    await dir.delete(recursive: true);
  });
  test('local sidecar wins without any cloud or public request', () async {
    await File('${dir.path}/song.lrc').writeAsString('[00:01.00]Local');
    final local = Track(
      id: 'local',
      title: 'Song',
      artist: 'Artist',
      localPath: '${dir.path}/song.mp3',
    );
    expect((await lyrics.load(local, false))!.lines.single.text, 'Local');
    expect(downloads.remote.calls, 0);
    expect(requests, 0);
  });
  test('downloaded embedded lyrics win before cloud lookup', () async {
    final payload = [3, ...ascii.encode('eng'), 0, ...utf8.encode('Embedded')];
    final body = [
      ...ascii.encode('USLT'),
      0,
      0,
      0,
      payload.length,
      0,
      0,
      ...payload,
    ];
    final file = await File('${dir.path}/offline.mp3').writeAsBytes([
      ...ascii.encode('ID3'),
      3,
      0,
      0,
      0,
      0,
      0,
      body.length,
      ...body,
    ]);
    downloads.store.row = {'path': file.path};
    expect((await lyrics.load(track, false))!.lines.single.text, 'Embedded');
    expect(downloads.remote.calls, 0);
    expect(requests, 0);
  });
  test(
    'disk cache survives sessions and offline mode without remote access',
    () async {
      expect(await lyrics.load(track, false), isNotNull);
      expect(requests, 1);
      lyrics.dispose();
      downloads.offlineOnly = true;
      lyrics = LibraryLyrics(downloads, cacheDirectory: () async => dir);
      expect(
        (await lyrics.load(track, false))!.lines.single.text,
        'Synthetic online',
      );
      expect(requests, 1);
      expect(downloads.remote.calls, 1);
    },
  );
  test(
    'offline misses and disabled online setting never query public APIs',
    () async {
      downloads.offlineOnly = true;
      expect(await lyrics.load(track, false), null);
      expect(downloads.remote.calls, 0);
      downloads.offlineOnly = false;
      await downloads.remote.preferences.setBool('visual.online_lyrics', false);
      expect(await lyrics.load(track, false), null);
      expect(requests, 0);
    },
  );
  test(
    'previous versions retain their cached lyrics in offline mode',
    () async {
      final hash = sha256.convert(utf8.encode('${track.id}|${track.revision}'));
      await File('${dir.path}/$hash.txt').writeAsString('Legacy synthetic');
      downloads.offlineOnly = true;
      expect(
        (await lyrics.load(track, false))!.lines.single.text,
        'Legacy synthetic',
      );
      expect(requests, 0);
    },
  );
}
