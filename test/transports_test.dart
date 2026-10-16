import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/domain/ports.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/infrastructure/onedrive.dart';

class _Tokens implements AccessTokenProvider {
  @override
  Future<String> accessToken() async => 'test-token';
}

void main() {
  test('Graph rejeita cursores externos antes de enviar credenciais', () async {
    var requests = 0;
    final httpClient = MockClient((request) async {
      requests++;
      return http.Response('{}', 200);
    });
    addTearDown(httpClient.close);
    final drive = OneDriveClient(httpClient, _Tokens());
    for (final url in [
      'https://example.com/v1.0/me/drive/root/delta',
      'http://graph.microsoft.com/v1.0/me/drive/root/delta',
      'https://graph.microsoft.com:444/v1.0/me/drive/root/delta',
      'https://user@graph.microsoft.com/v1.0/me/drive/root/delta',
    ]) {
      await expectLater(
        drive.delta(cursor: Uri.parse(url)),
        throwsArgumentError,
      );
    }
    expect(requests, 0);
  });

  test(
    'Graph lê páginas e mantém autenticação somente no transporte',
    () async {
      final httpClient = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode({
            'value': <Object>[],
            '@odata.deltaLink': 'https://graph.microsoft.com/v1.0/delta',
          }),
          200,
        );
      });
      addTearDown(httpClient.close);
      final page = await OneDriveClient(httpClient, _Tokens()).delta();
      expect(page.items, isEmpty);
      expect(page.nextLink, isNull);
      expect(page.deltaLink!.host, 'graph.microsoft.com');
    },
  );

  test('Last.fm não trata scrobble ignorado como sucesso', () async {
    final httpClient = MockClient(
      (request) async => http.Response(
        '{"scrobbles":{"@attr":{"accepted":"0","ignored":"1"}}}',
        200,
      ),
    );
    addTearDown(httpClient.close);
    final lastfm = LastFmClient(
      httpClient,
      apiKey: 'test',
      apiSecret: 'test',
      sessionKey: 'test',
    );
    await expectLater(
      lastfm.submit(
        const Track(id: '1', title: 'Faixa', artist: 'Artista'),
        DateTime.utc(2026),
        const Duration(minutes: 3),
      ),
      throwsA(isA<LastFmIgnoredException>()),
    );
  });
}
