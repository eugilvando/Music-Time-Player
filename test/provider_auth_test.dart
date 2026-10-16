import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/microsoft_auth.dart';
import 'package:music_time/sources/provider_connections.dart';

class MemoryVault implements SecretVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  const clientId = '00000000-0000-0000-0000-000000000001';
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'microsoft.client_id': clientId,
    }),
  );
  test(
    'Client ID inválido não substitui o identificador público salvo',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = await LibraryStore.open(':memory:');
      final providers = ProviderConnections(prefs, store, vault: MemoryVault());
      try {
        await expectLater(
          providers.configure('not-a-client-id', '', ''),
          throwsA(isA<MicrosoftAuthFailure>()),
        );
        expect(prefs.getString('microsoft.client_id'), clientId);
      } finally {
        providers.dispose();
        await store.close();
      }
    },
  );
  test('PKCE usa o vetor conhecido do RFC 7636', () {
    expect(
      pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
    expect(secureRandomString().length, 43);
  });
  test('callback rejeita state inválido e troca código com PKCE', () async {
    final vault = MemoryVault();
    Uri? authorization;
    final client = MockClient((request) async {
      expect(request.url.host, 'login.microsoftonline.com');
      expect(request.bodyFields['client_id'], clientId);
      expect(
        pkceChallenge(request.bodyFields['code_verifier']!),
        authorization!.queryParameters['code_challenge'],
      );
      return http.Response(
        '{"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600}',
        200,
      );
    });
    addTearDown(client.close);
    final auth = MicrosoftAuth(
      client,
      vault,
      clientId: clientId,
      browser: (uri) async {
        authorization = uri;
        final bad = await http.get(
          MicrosoftAuth.redirect.replace(
            queryParameters: {'state': 'bad', 'code': 'test-code'},
          ),
        );
        expect(bad.statusCode, 400);
        final good = await http.get(
          MicrosoftAuth.redirect.replace(
            queryParameters: {
              'state': uri.queryParameters['state']!,
              'code': 'test-code',
            },
          ),
        );
        expect(good.statusCode, 200);
        return true;
      },
    );
    await auth.login();
    expect(await auth.accessToken(), 'test-access');
    expect(vault.values.containsKey('microsoft.session'), isTrue);
    await auth.disconnect();
    expect(vault.values.containsKey('microsoft.session'), isFalse);
  });
  test('cancelar login web libera callback e não salva sessão', () async {
    final vault = MemoryVault();
    final client = MockClient(
      (_) async => throw StateError('Sem troca de token'),
    );
    addTearDown(client.close);
    late MicrosoftAuth auth;
    auth = MicrosoftAuth(
      client,
      vault,
      clientId: clientId,
      browser: (_) async {
        auth.cancel();
        return true;
      },
    );
    await expectLater(auth.login(), throwsA(isA<MicrosoftAuthFailure>()));
    expect(vault.values, isEmpty);
    final retry = MicrosoftAuth(
      client,
      vault,
      clientId: clientId,
      browser: (_) async => false,
    );
    await expectLater(retry.login(), throwsA(isA<MicrosoftAuthFailure>()));
    expect(vault.values, isEmpty);
  });
  test('renova sessão uma única vez para chamadas concorrentes', () async {
    final vault = MemoryVault();
    await vault.write(
      'microsoft.session',
      jsonEncode({
        'client_id': clientId,
        'access_token': 'old',
        'refresh_token': 'refresh',
        'expires_at': '2000-01-01T00:00:00Z',
      }),
    );
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.bodyFields['grant_type'], 'refresh_token');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return http.Response('{"access_token":"new","expires_in":3600}', 200);
    });
    addTearDown(client.close);
    final auth = MicrosoftAuth(client, vault, clientId: clientId);
    expect(
      await Future.wait([
        auth.accessToken(),
        auth.accessToken(),
        auth.accessToken(),
      ]),
      ['new', 'new', 'new'],
    );
    expect(calls, 1);
  });
  test(
    'outbox distingue sucesso, rejeição, reconexão e resposta ambígua',
    () async {
      SharedPreferences.setMockInitialValues({'lastfm.scrobbling': true});
      final preferences = await SharedPreferences.getInstance();
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      const track = Track(
        id: 'a',
        title: 'Faixa',
        artist: 'Artista',
        localPath: 'C:/a.mp3',
      );
      await store.addTracks([track]);
      final vault = MemoryVault();
      await vault.write('lastfm.api_key', 'test');
      await vault.write('lastfm.api_secret', 'test');
      await vault.write('lastfm.session', 'test');
      var mode = 'accepted';
      final client = MockClient((request) async {
        if (mode == 'timeout') {
          throw const FormatException('Resposta simulada inválida');
        }
        if (mode == 'auth') return http.Response('{"error":9}', 200);
        if (mode == 'ignored') {
          return http.Response('{"scrobbles":{"@attr":{"accepted":"0"}}}', 200);
        }
        return http.Response('{"scrobbles":{"@attr":{"accepted":"1"}}}', 200);
      });
      final providers = ProviderConnections(
        preferences,
        store,
        vault: vault,
        client: client,
      );
      addTearDown(providers.dispose);
      for (final setting in ['accepted', 'ignored', 'timeout', 'auth']) {
        mode = setting;
        final time = DateTime.utc(
          2026,
          1,
          1,
          0,
          ['accepted', 'ignored', 'timeout', 'auth'].indexOf(setting),
        );
        await store.enqueueScrobble(track, time, const Duration(minutes: 3));
        await providers.flushScrobbles();
      }
      final states = (await store.scrobbleStatus())
          .map((row) => row['status'])
          .toSet();
      expect(states, {'sent', 'rejected', 'ambiguous', 'auth_required'});
      expect(await store.pendingScrobbles(), isEmpty);
      await store.reconnectScrobbles();
      expect((await store.pendingScrobbles()).length, 1);
    },
  );
}
