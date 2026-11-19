import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:music_time/presentation/brainz_settings.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/library/local_similarity.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/domain/scrobble_policy.dart';
import 'package:music_time/infrastructure/brainz.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/library/artist_similarity.dart';
import 'package:music_time/library/listenbrainz_sync.dart';
import 'package:music_time/library/musicbrainz_metadata.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/microsoft_auth.dart';

class MemoryVault implements SecretVault {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore store;
  late SharedPreferences prefs;
  const song = Track(
    id: 'a',
    title: 'Song',
    artist: 'Artist A',
    genre: 'Rock',
    year: 1995,
    localPath: 'a.mp3',
    duration: Duration(minutes: 3),
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = await LibraryStore.open(':memory:');
    await store.addTracks([song]);
  });
  tearDown(() async => store.close());
  test('local similarity works without credentials or HTTP, era alone is insufficient', () async {
    await store.addTracks([
      const Track(
        id: 'b',
        title: 'Related',
        artist: 'Artist B',
        genre: 'rock',
        year: 1996,
        localPath: 'b.mp3',
      ),
      const Track(
        id: 'c',
        title: 'Other',
        artist: 'Artist C',
        genre: 'Jazz',
        year: 1996,
        localPath: 'c.mp3',
      ),
    ]);
    final engine = ArtistSimilarity(
      store,
      () async => throw StateError('No external connection'),
    );
    expect((await engine.lookup('Artist A', offline: true)).names, [
      'artist b',
    ]);
    expect((await engine.lookup('Artist A')).names, ['artist b']);
    expect((await engine.lookup('Unknown', offline: true)).names, isEmpty);
  });
  test(
    'read policy blocks Last.fm queries but preserves signed scrobbles',
    () async {
      final requests = <http.Request>[];
      final api = LastFmClient(
        MockClient((r) async {
          requests.add(r);
          return http.Response('{"scrobbles":{"@attr":{"accepted":"1"}}}', 200);
        }),
        apiKey: 'fake',
        apiSecret: 'fake',
        sessionKey: 'fake',
        allowReads: () => false,
      );
      await expectLater(
        api.readProfile('artist.getSimilar', {'artist': 'A'}),
        throwsA(isA<LastFmException>()),
      );
      await expectLater(
        api.profileTracks('user', loved: true),
        throwsA(isA<LastFmException>()),
      );
      await api.submit(song, DateTime.utc(2026, 1, 1), song.duration);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
    },
  );
  test('ListenBrainz keeps offline listens account-bound and deduplicated across restart', () async {
    final vault = MemoryVault();
    await vault.write(
      'listenbrainz.session',
      jsonEncode({'user': 'alice', 'token': 'fake-alice'}),
    );
    await prefs.setBool('listenbrainz.scrobbling', true);
    var online = false;
    final requests = <http.Request>[];
    final transport = BrainzTransport(
      MockClient((r) async {
        requests.add(r);
        return http.Response('{"status":"ok"}', 200);
      }),
      'api.listenbrainz.org',
      allowed: () => online,
    );
    ListenBrainzSync service() => ListenBrainzSync(
      store,
      prefs,
      vault,
      transport,
      allowed: () => online,
      changed: () {},
    );
    var sync = service();
    final session = ListeningSession(song, DateTime.utc(2026, 1, 1))
      ..addListening(const Duration(seconds: 90));
    await sync.observe(session);
    await sync.flush();
    expect(requests, isEmpty);
    expect((await sync.outbox()).single['status'], 'pending');
    sync.dispose();
    await vault.write(
      'listenbrainz.session',
      jsonEncode({'user': 'bob', 'token': 'fake-bob'}),
    );
    sync = service();
    online = true;
    await sync.flush();
    expect(requests, isEmpty);
    sync.dispose();
    await vault.write(
      'listenbrainz.session',
      jsonEncode({'user': 'alice', 'token': 'fake-alice'}),
    );
    sync = service();
    await sync.flush();
    expect(requests, hasLength(1));
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['listen_type'], 'single');
    expect(body['payload'][0]['listened_at'], 1767225600);
    expect(requests.single.headers['Authorization'], 'Token fake-alice');
    await sync.observe(session);
    await sync.flush();
    expect(requests, hasLength(1));
    expect((await sync.outbox()).single['status'], 'sent');
    sync.dispose();
  });
  test(
    'connection does not enable uploads and token stays out of preferences',
    () async {
      final vault = MemoryVault();
      final transport = BrainzTransport(
        MockClient((r) async {
          expect(r.url.queryParameters.containsKey('token'), false);
          return http.Response('{"valid":true,"user_name":"alice"}', 200);
        }),
        'api.listenbrainz.org',
      );
      final sync = ListenBrainzSync(
        store,
        prefs,
        vault,
        transport,
        allowed: () => true,
        changed: () {},
      );
      await sync.connect('fake-token');
      expect(prefs.getBool('listenbrainz.scrobbling'), false);
      expect(
        prefs.getKeys().any(
          (k) => k.contains('token') || k.contains('session'),
        ),
        false,
      );
      expect(vault.data['listenbrainz.session'], contains('fake-token'));
      sync.dispose();
    },
  );
  test(
    'unauthorized submission is retained for reconnect instead of discarded',
    () async {
      final vault = MemoryVault();
      await vault.write(
        'listenbrainz.session',
        jsonEncode({'user': 'alice', 'token': 'fake'}),
      );
      await prefs.setBool('listenbrainz.scrobbling', true);
      var online = false;
      final transport = BrainzTransport(
        MockClient((r) async => http.Response('{}', 401)),
        'api.listenbrainz.org',
      );
      final sync = ListenBrainzSync(
        store,
        prefs,
        vault,
        transport,
        allowed: () => online,
        changed: () {},
      );
      await sync.observe(
        ListeningSession(song, DateTime.utc(2026, 1, 1))
          ..addListening(const Duration(seconds: 90)),
      );
      await sync.flush();
      online = true;
      await sync.flush();
      expect((await sync.outbox()).single['status'], 'auth_required');
      sync.dispose();
    },
  );
  test(
    'MusicBrainz caches identity and genres without modifying tracks',
    () async {
      var calls = 0, enabled = false;
      final transport = BrainzTransport(
        MockClient((r) async {
          calls++;
          expect(r.headers['User-Agent'], contains('MusicTime'));
          return http.Response(
            r.url.queryParameters.containsKey('query')
                ? '{"artists":[{"id":"fake-id","name":"Artist A","score":100}]}'
                : '{"genres":[{"name":"alternative rock"}]}',
            200,
          );
        }),
        'musicbrainz.org',
        allowed: () => enabled,
      );
      final metadata = MusicBrainzMetadata(store, transport, () => enabled);
      expect(await metadata.artistGenres('Artist A'), isEmpty);
      expect(calls, 0);
      enabled = true;
      expect(await metadata.artistGenres('Artist A'), ['alternative rock']);
      enabled = false;
      expect(await metadata.artistGenres('Artist A'), ['alternative rock']);
      expect(calls, 2);
      expect((await store.loadTracks()).single.genre, 'Rock');
    },
  );
  test(
    'local cache is invalidated after metadata edits and playlist changes',
    () async {
      const related = Track(
        id: 'b',
        title: 'B',
        artist: 'Artist B',
        genre: 'Rock',
        localPath: 'b.mp3',
      );
      await store.addTracks([related]);
      expect(await localSimilarArtists(store, 'Artist A'), ['artist b']);
      await store.addTracks([
        const Track(
          id: 'b',
          title: 'B',
          artist: 'Artist B',
          genre: 'Jazz',
          localPath: 'b.mp3',
        ),
      ]);
      expect(await localSimilarArtists(store, 'Artist A'), isEmpty);
      final playlist = await store.createPlaylist('Synthetic');
      await store.appendTracksToPlaylist(playlist, ['a', 'b']);
      expect(await localSimilarArtists(store, 'Artist A'), ['artist b']);
    },
  );
  test(
    'MusicBrainz refuses ambiguous artists and caches the negative result',
    () async {
      var calls = 0;
      final metadata = MusicBrainzMetadata(
        store,
        BrainzTransport(
          MockClient((r) async {
            calls++;
            return http.Response(
              '{"artists":[{"id":"a","name":"Artist A","score":100},{"id":"b","name":"Artist A","score":100}]}',
              200,
            );
          }),
          'musicbrainz.org',
        ),
        () => true,
      );
      expect(await metadata.artistGenres('Artist A'), isEmpty);
      expect(await metadata.artistGenres('Artist A'), isEmpty);
      expect(calls, 1);
    },
  );
  testWidgets(
    'integration panels fit a narrow window and do not send anything on open',
    (tester) async {
      tester.view.physicalSize = const Size(420, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      late ProviderConnections providers;
      await tester.runAsync(() async {
        providers = ProviderConnections(
          prefs,
          store,
          vault: MemoryVault(),
          client: MockClient((r) async {
            calls++;
            throw StateError('Unexpected network');
          }),
        );
        await providers.listenBrainz.initialize();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  BrainzSettings(providers: providers, policyOnly: true),
                  BrainzSettings(providers: providers),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ListenBrainz'), findsOneWidget);
      expect(find.text('MusicBrainz'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(calls, 0);
      await tester.pumpWidget(const SizedBox());
      providers.dispose();
    },
  );
  test('playing now never includes timestamp', () {
    final payload = ListenBrainzClient.payload(song, null, song.duration);
    expect(payload.containsKey('listened_at'), false);
    expect(payload['track_metadata']['additional_info']['duration_ms'], 180000);
  });
}
