import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/microsoft_auth.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;

void main() {
  const id = '00000000-0000-0000-0000-000000000001';
  setUp(
    () => SharedPreferences.setMockInitialValues({'microsoft.client_id': id}),
  );
  test('provider mantém um autenticador e uma renovação concorrente', () async {
    final vault = MemoryVault();
    await vault.write(
      'microsoft.session',
      jsonEncode({
        'client_id': id,
        'access_token': 'old',
        'refresh_token': 'refresh',
        'expires_at': '2000-01-01T00:00:00Z',
      }),
    );
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return http.Response('{"access_token":"new","expires_in":3600}', 200);
    });
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final p = ProviderConnections(
      await SharedPreferences.getInstance(),
      store,
      vault: vault,
      client: client,
    );
    addTearDown(p.dispose);
    expect(identical(p.microsoft, p.microsoft), isTrue);
    expect(
      await Future.wait([p.microsoft.accessToken(), p.microsoft.accessToken()]),
      ['new', 'new'],
    );
    expect(calls, 1);
    final restarted = MicrosoftAuth(client, vault, clientId: id);
    expect(await restarted.accessToken(), 'new');
    expect(
      jsonDecode(vault.values['microsoft.session']!)['refresh_token'],
      'refresh',
    );
  });
  test('revogação remove sessão e não deixa loop de renovação', () async {
    final vault = MemoryVault();
    await vault.write(
      'microsoft.session',
      jsonEncode({
        'client_id': id,
        'access_token': 'old',
        'refresh_token': 'revoked',
        'expires_at': '2000-01-01T00:00:00Z',
      }),
    );
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      return http.Response('{"error":"invalid_grant"}', 400);
    });
    addTearDown(client.close);
    final auth = MicrosoftAuth(client, vault, clientId: id);
    await expectLater(auth.accessToken(), throwsA(isA<MicrosoftAuthFailure>()));
    expect(vault.values, isEmpty);
    await expectLater(auth.accessToken(), throwsA(isA<MicrosoftAuthFailure>()));
    expect(calls, 1);
  });
  test('Graph sem drive é separado de OAuth e preserva Last.fm', () async {
    final vault = MemoryVault();
    await vault.write(
      'microsoft.session',
      jsonEncode({
        'client_id': id,
        'access_token': 'token',
        'expires_at': '2099-01-01T00:00:00Z',
      }),
    );
    await vault.write('lastfm.session', 'lastfm');
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final p = ProviderConnections(
      await SharedPreferences.getInstance(),
      store,
      vault: vault,
      client: MockClient((r) async => http.Response('{}', 404)),
    );
    addTearDown(p.dispose);
    await p.checkMicrosoftDrive();
    expect(p.errorStage, 'graph_drive');
    expect(p.error, contains('drive'));
    expect(vault.values['lastfm.session'], 'lastfm');
    await p.disconnectMicrosoft();
    expect(vault.values.containsKey('microsoft.session'), isFalse);
    expect(vault.values['lastfm.session'], 'lastfm');
  });
  test('erros Microsoft não exibem descrição remota nem credenciais', () {
    final auth = MicrosoftAuth(http.Client(), MemoryVault(), clientId: id);
    addTearDown(auth.client.close);
    final error = auth.responseFailure({
      'error': 'invalid_request',
      'error_codes': [50011],
      'error_description': 'token secret code',
    });
    expect(error.code, 'AADSTS50011');
    expect(error.message, contains('localhost:42813/oauth'));
    expect(error.message, isNot(contains('token secret')));
  });
  test(
    'recusa no navegador libera callback e permite nova tentativa',
    () async {
      final client = MockClient(
        (r) async => throw StateError('não trocar token'),
      );
      addTearDown(client.close);
      final vault = MemoryVault();
      final auth = MicrosoftAuth(
        client,
        vault,
        clientId: id,
        browser: (uri) async {
          await http.get(
            MicrosoftAuth.redirect.replace(
              queryParameters: {
                'state': uri.queryParameters['state']!,
                'error': 'access_denied',
              },
            ),
          );
          return true;
        },
      );
      await expectLater(auth.login(), throwsA(isA<MicrosoftAuthFailure>()));
      expect(vault.values, isEmpty);
      final retry = MicrosoftAuth(
        client,
        vault,
        clientId: id,
        browser: (_) async => false,
      );
      await expectLater(retry.login(), throwsA(isA<MicrosoftAuthFailure>()));
    },
  );
}
