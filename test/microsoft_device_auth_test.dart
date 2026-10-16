import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/sources/microsoft_auth.dart';

class DeviceVault implements SecretVault {
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

const deviceClientId = '00000000-0000-0000-0000-000000000001';
void main() {
  test(
    'código Microsoft respeita pending e slow_down antes de salvar a sessão',
    () async {
      final vault = DeviceVault();
      var polls = 0;
      final waits = <Duration>[];
      final client = MockClient((request) async {
        expect(request.url.host, 'login.microsoftonline.com');
        if (request.url.path.endsWith('/devicecode')) {
          expect(request.bodyFields['client_id'], deviceClientId);
          expect(request.bodyFields.containsKey('client_secret'), isFalse);
          return http.Response(
            jsonEncode({
              'device_code': 'private-device',
              'user_code': 'ABCD-EFGH',
              'verification_uri': 'https://microsoft.com/devicelogin',
              'expires_in': 900,
              'interval': 5,
            }),
            200,
          );
        }
        expect(
          request.bodyFields['grant_type'],
          'urn:ietf:params:oauth:grant-type:device_code',
        );
        expect(request.bodyFields['device_code'], 'private-device');
        polls++;
        return polls < 3
            ? http.Response(
                jsonEncode({
                  'error': polls == 1 ? 'authorization_pending' : 'slow_down',
                }),
                400,
              )
            : http.Response(
                '{"access_token":"access","refresh_token":"refresh","expires_in":3600}',
                200,
              );
      });
      final auth = MicrosoftAuth(
        client,
        vault,
        clientId: deviceClientId,
        wait: (duration) async {
          waits.add(duration);
        },
      );
      final code = await auth.requestDeviceCode();
      expect(code.userCode, 'ABCD-EFGH');
      expect(vault.values, isEmpty);
      await auth.completeDeviceLogin(code);
      expect(waits.map((value) => value.inSeconds), [5, 5, 10]);
      expect(await auth.accessToken(), 'access');
      client.close();
    },
  );
  test('cancelamento interrompe polling e não grava credenciais', () async {
    final vault = DeviceVault();
    var polls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/token')) polls++;
      return http.Response(
        '{"device_code":"private","user_code":"ABCD","verification_uri":"https://microsoft.com/devicelogin","expires_in":900}',
        200,
      );
    });
    final auth = MicrosoftAuth(client, vault, clientId: deviceClientId);
    final code = await auth.requestDeviceCode();
    auth.cancel();
    await expectLater(
      auth.completeDeviceLogin(code),
      throwsA(
        isA<MicrosoftAuthFailure>().having(
          (error) => error.message,
          'message',
          'Conexão cancelada.',
        ),
      ),
    );
    expect(polls, 0);
    expect(vault.values, isEmpty);
    client.close();
  });
  test(
    'erros do registro ficam claros e não exibem descrições sensíveis',
    () async {
      final client = MockClient(
        (request) async => http.Response(
          '{"error":"unauthorized_client","error_description":"private-sensitive-description"}',
          400,
        ),
      );
      final auth = MicrosoftAuth(
        client,
        DeviceVault(),
        clientId: deviceClientId,
      );
      await expectLater(
        auth.requestDeviceCode(),
        throwsA(
          isA<MicrosoftAuthFailure>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('cliente público'),
              isNot(contains('private-sensitive')),
            ),
          ),
        ),
      );
      client.close();
    },
  );
  test('recusa e expiração encerram a tentativa sem sessão', () async {
    for (final error in ['authorization_declined', 'expired_token']) {
      final vault = DeviceVault();
      final client = MockClient(
        (request) async => request.url.path.endsWith('/devicecode')
            ? http.Response(
                '{"device_code":"private","user_code":"ABCD","verification_uri":"https://microsoft.com/devicelogin","expires_in":900}',
                200,
              )
            : http.Response(jsonEncode({'error': error}), 400),
      );
      final auth = MicrosoftAuth(
        client,
        vault,
        clientId: deviceClientId,
        wait: (_) async {},
      );
      await expectLater(
        auth.completeDeviceLogin(await auth.requestDeviceCode()),
        throwsA(isA<MicrosoftAuthFailure>()),
      );
      expect(vault.values, isEmpty);
      client.close();
    }
  });
}
