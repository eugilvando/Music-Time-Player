import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/library/lastfm_favorite_sync.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/platform/linux_tray_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore store;
  late LastFmFavoriteSync sync;
  var session = 'account-a';
  var online = true, enabled = true, fail = false;
  final requests = <Map<String, String>>[];
  const track = Track(
    id: 'one',
    title: 'Song & More',
    artist: 'AC/DC',
    localPath: 'fixture.mp3',
  );
  late LastFmClient Function() api;
  setUp(() async {
    store = await LibraryStore.open(':memory:');
    await store.addTracks([track]);
    await store.setFavorite(track.id, true);
    session = 'account-a';
    online = true;
    enabled = true;
    fail = false;
    requests.clear();
    api = () => LastFmClient(
      MockClient((request) async {
        final fields = Uri.splitQueryString(request.body);
        requests.add(fields);
        expect(fields['api_sig'], LastFmClient.signature(fields, 'secret'));
        return http.Response(jsonEncode(fail ? {'error': 16} : {}), 200);
      }),
      apiKey: 'key',
      apiSecret: 'secret',
      sessionKey: session,
    );
    sync = LastFmFavoriteSync(
      store,
      api: () async => api(),
      allowed: () => enabled,
      online: () => online,
      changed: () {},
    );
  });
  tearDown(() async => store.close());
  test('favorite exports signed love without scrobbling or album', () async {
    await sync.enqueue([track]);
    await sync.flush();
    await sync.flush();
    expect(requests, hasLength(1));
    expect(requests.single['method'], 'track.love');
    expect(requests.single['artist'], 'AC/DC');
    expect(requests.single['track'], track.title);
    expect(requests.single.containsKey('album'), false);
  });
  test(
    'offline pending survives service restart and retries failure',
    () async {
      online = false;
      await sync.enqueue([track]);
      await sync.flush();
      expect(requests, isEmpty);
      sync = LastFmFavoriteSync(
        store,
        api: () async => api(),
        allowed: () => enabled,
        online: () => online,
        changed: () {},
      );
      online = true;
      fail = true;
      await sync.flush();
      fail = false;
      await sync.flush();
      await sync.flush();
      expect(requests, hasLength(2));
    },
  );
  test('pending favorites are never sent to another account', () async {
    await sync.enqueue([track]);
    session = 'account-b';
    await sync.flush();
    expect(requests, isEmpty);
    session = 'account-a';
    await sync.flush();
    expect(requests, hasLength(1));
  });
  test('unfavorited pending item is dropped without unlove', () async {
    await sync.enqueue([track]);
    await store.setFavorite(track.id, false);
    await sync.flush();
    expect(requests, isEmpty);
    expect(await store.database.query('lastfm_favorite_outbox'), isEmpty);
  });
  test('disabled export and missing authorization do not queue', () async {
    enabled = false;
    await sync.enqueue([track]);
    await sync.flush();
    enabled = true;
    session = '';
    await sync.enqueue([track]);
    await sync.flush();
    expect(requests, isEmpty);
  });
  test('Linux tray requires an active host', () async {
    expect(
      await linuxTrayHostAvailable(
        run: (cmd, args) async => ProcessResult(1, 0, '(<true>,)', ''),
      ),
      true,
    );
    expect(
      await linuxTrayHostAvailable(
        run: (cmd, args) async => ProcessResult(1, 0, '(<false>,)', ''),
      ),
      false,
    );
    expect(
      await linuxTrayHostAvailable(
        run: (cmd, args) async => ProcessResult(1, 1, '', 'no bus'),
      ),
      false,
    );
  });
}
