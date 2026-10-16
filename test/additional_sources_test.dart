import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/ports.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/additional_sources.dart';

import 'provider_auth_test.dart' show MemoryVault;

import 'package:music_time/sources/microsoft_auth.dart' show pkceChallenge;

class _LoopbackHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Google desktop OAuth validates state and PKCE before saving the session',
    () async {
      final store = await LibraryStore.open(':memory:');
      final vault = MemoryVault();
      Uri? authorization;
      final client = MockClient((request) async {
        expect(request.url.host, 'oauth2.googleapis.com');
        final fields = Uri.splitQueryString(request.body);
        expect(fields['code'], 'fixture-code');
        expect(
          pkceChallenge(fields['code_verifier']!),
          authorization!.queryParameters['code_challenge'],
        );
        expect(fields['client_secret'], 'desktop-fixture-secret');
        return http.Response(
          jsonEncode({
            'access_token': 'access-fixture',
            'refresh_token': 'refresh-fixture',
            'expires_in': 3600,
          }),
          200,
        );
      });
      final prefs = await SharedPreferences.getInstance();
      final sources = AdditionalSources(
        prefs,
        store,
        vault,
        client,
        browser: (uri) async {
          authorization = uri;
          expect(uri.queryParameters['code_challenge_method'], 'S256');
          final callback = Uri.parse(uri.queryParameters['redirect_uri']!);
          final browser = HttpOverrides.runWithHttpOverrides(
            () => HttpClient(),
            _LoopbackHttp(),
          );
          try {
            final bad = await (await browser.getUrl(
              callback.replace(
                queryParameters: {'state': 'wrong', 'code': 'wrong'},
              ),
            )).close();
            expect(bad.statusCode, 400);
            await bad.drain<void>();
            final valid = await (await browser.getUrl(
              callback.replace(
                queryParameters: {
                  'state': uri.queryParameters['state']!,
                  'code': 'fixture-code',
                },
              ),
            )).close();
            expect(valid.statusCode, 200);
            await valid.drain<void>();
          } finally {
            browser.close(force: true);
          }
          return true;
        },
      );
      try {
        await sources.add(
          SourceConnection(
            id: 'oauth',
            type: 'google',
            label: 'Drive',
            clientId: 'desktop.apps.googleusercontent.com',
          ),
          clientSecret: 'desktop-fixture-secret',
        );
        expect(
          prefs.getString('additional_sources'),
          isNot(contains('fixture-secret')),
        );
        expect(vault.values.values.single, contains('refresh-fixture'));
      } finally {
        sources.dispose();
        client.close();
        await store.close();
      }
    },
  );
  test(
    'Jellyfin and Emby isolate account headers and preserve stable references',
    () async {
      for (final type in ['jellyfin', 'emby']) {
        final store = await LibraryStore.open(':memory:');
        final vault = MemoryVault();
        final calls = <String>[];
        final client = MockClient((request) async {
          calls.add(request.url.path);
          expect(request.url.queryParameters.keys, isNot(contains('api_key')));
          if (request.url.path.endsWith('AuthenticateByName')) {
            expect(jsonDecode(request.body)['Pw'], 'private-password');
            return http.Response(
              jsonEncode({
                'AccessToken': 'private-token',
                'User': {'Id': 'u1'},
              }),
              200,
            );
          }
          expect(
            request.headers[type == 'emby' ? 'X-Emby-Token' : 'Authorization'],
            contains('private-token'),
          );
          return http.Response(
            jsonEncode({
              'Items': [
                {
                  'Id': 'song1',
                  'Name': 'Song',
                  'Artists': ['Artist'],
                  'Album': 'Album',
                  'RunTimeTicks': 1800000000,
                },
              ],
              'TotalRecordCount': 1,
            }),
            200,
          );
        });
        final prefs = await SharedPreferences.getInstance();
        final sources = AdditionalSources(prefs, store, vault, client);
        final source = SourceConnection(
          id: type,
          type: type,
          label: type,
          address: 'https://music.example/base',
          username: 'listener',
        );
        try {
          await sources.add(source, password: 'private-password');
          expect(
            prefs.getString('additional_sources'),
            isNot(contains('private-password')),
          );
          expect(
            prefs.getString('additional_sources'),
            isNot(contains('private-token')),
          );
          await sources.sync(source);
          final tracks = await store.loadTracks();
          expect(tracks, hasLength(1));
          final t = tracks.single;
          expect(t.provider, type);
          expect(t.account, type);
          expect(t.duration.inSeconds, 180);
          final uri = await sources.resolve(t);
          expect(uri.path, '/base/Audio/song1/stream');
          expect(uri.toString(), isNot(contains('private-token')));
          expect(await sources.mediaHeaders(t, uri), isNotEmpty);
          await expectLater(
            sources.mediaHeaders(t, Uri.parse('https://other.example/stream')),
            throwsA(isA<MediaSourceFailure>()),
          );
          await sources.sync(source);
          expect(await store.loadTracks(), hasLength(1));
          await sources.setVisible(source, false);
          expect(await store.loadTracks(), isEmpty);
          await sources.disconnect(source);
          await expectLater(
            sources.resolve(t),
            throwsA(isA<MediaSourceFailure>()),
          );
          await sources.add(
            source,
            password: 'private-password',
            reconnect: true,
          );
          expect((await sources.resolve(t)).path, '/base/Audio/song1/stream');
          await sources.disconnect(source);
          expect(vault.values, isEmpty);
        } finally {
          sources.dispose();
          client.close();
          await store.close();
        }
      }
    },
  );
  test('WebDAV parses namespaces and encoded hrefs; rejects external and failed properties', () async {
    final store = await LibraryStore.open(':memory:');
    final client = MockClient((r) async {
      expect(r.headers['Authorization'], startsWith('Basic '));
      if (r.method != 'PROPFIND') return http.Response('', 416);
      expect(r.headers['Depth'], '1');
      return http.Response('''<multistatus xmlns="DAV:">
        <response><href>/music/</href><propstat><status>HTTP/1.1 200 OK</status><prop><resourcetype><collection/></resourcetype></prop></propstat></response>
        <response><href>/music/A%20Song.mp3</href><propstat><status>HTTP/1.1 200 OK</status><prop><getetag>rev1</getetag></prop></propstat></response>
        <response><href>https://evil.example/song.mp3</href><propstat><status>HTTP/1.1 200 OK</status><prop/></propstat></response>
        <response><href>/music/denied.mp3</href><propstat><status>HTTP/1.1 403 Forbidden</status><prop/></propstat></response>
      </multistatus>''', 207);
    });
    final sources = AdditionalSources(
      await SharedPreferences.getInstance(),
      store,
      MemoryVault(),
      client,
    );
    final s = SourceConnection(
      id: 'dav',
      type: 'webdav',
      label: 'DAV',
      address: 'https://dav.example/music/',
      username: 'u',
    );
    try {
      await sources.add(s, password: 'p');
      await sources.sync(s);
      final t = (await store.loadTracks()).single;
      expect(t.title, 'A Song');
      expect(t.revision, 'rev1');
      expect(
        (await sources.resolve(t)).toString(),
        'https://dav.example/music/A%20Song.mp3',
      );
    } finally {
      sources.dispose();
      client.close();
      await store.close();
    }
  });
  test('Google listing pages and access token stay separate from catalog; cancelled sync preserves missing items', () async {
    final store = await LibraryStore.open(':memory:');
    final vault = MemoryVault();
    var pages = 0;
    final client = MockClient((r) async {
      expect(r.headers['Authorization'], 'Bearer google-token');
      if (r.url.queryParameters['alt'] == 'media') {
        return http.Response('', 416);
      }
      pages++;
      return http.Response(
        jsonEncode({
          'files': pages.isOdd
              ? [
                  {'id': 'id1', 'name': 'One.mp3'},
                ]
              : [],
          if (pages.isOdd) 'nextPageToken': 'next',
        }),
        200,
      );
    });
    final prefs = await SharedPreferences.getInstance();
    final sources = AdditionalSources(prefs, store, vault, client);
    final s = SourceConnection(
      id: 'g',
      type: 'google',
      label: 'Drive',
      clientId: 'desktop.apps.googleusercontent.com',
    );
    sources.connections.add(s);
    await vault.write(
      sources.secretKey(s.id),
      jsonEncode({
        'access_token': 'google-token',
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      }),
    );
    try {
      await sources.persist();
      await sources.sync(s);
      expect(pages, 2);
      final t = (await store.loadTracks()).single;
      expect(t.itemId, 'id1');
      expect(t.provider, 'google');
      expect((await sources.resolve(t)).queryParameters, {'alt': 'media'});
      await prefs.setBool('visual.offline_only', true);
      await expectLater(sources.resolve(t), throwsA(isA<MediaSourceFailure>()));
      expect(await store.loadTracks(), hasLength(1));
    } finally {
      sources.dispose();
      client.close();
      await store.close();
    }
  });
  test(
    'HTTP is opt in per source and SMB cannot resolve outside its share',
    () async {
      final store = await LibraryStore.open(':memory:');
      final client = MockClient((r) async => http.Response('', 200));
      final sources = AdditionalSources(
        await SharedPreferences.getInstance(),
        store,
        MemoryVault(),
        client,
      );
      final s = SourceConnection(
        id: 's',
        type: 'smb',
        label: 'Share',
        address: r'\\server\share\Music',
      );
      sources.connections.add(s);
      try {
        expect(
          () => SourceConnection(
            id: 'd',
            type: 'webdav',
            label: 'DAV',
            address: 'http://server/music',
          ).base,
          throwsA(isA<MediaSourceFailure>()),
        );
        expect(
          await sources.resolve(
            const Track(
              id: 's1',
              title: 'a',
              artist: 'b',
              sourceProvider: 'smb',
              sourceAccount: 's',
              itemId: r'album\a.mp3',
            ),
          ),
          Uri.file(r'\\server\share\Music\album\a.mp3', windows: true),
        );
        await expectLater(
          sources.resolve(
            const Track(
              id: 's2',
              title: 'a',
              artist: 'b',
              sourceProvider: 'smb',
              sourceAccount: 's',
              itemId: r'..\private.mp3',
            ),
          ),
          throwsA(isA<MediaSourceFailure>()),
        );
      } finally {
        sources.dispose();
        client.close();
        await store.close();
      }
    },
  );
}
