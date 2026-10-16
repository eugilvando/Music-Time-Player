import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/ports.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/microsoft_auth.dart';
import 'package:music_time/sources/onedrive_verification.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;

const registration = '00000000-0000-0000-0000-000000000001';
Future<void> seed(MemoryVault vault, {bool expired = false}) => vault.write(
  'microsoft.session',
  jsonEncode({
    'client_id': registration,
    'access_token': 'old',
    'refresh_token': 'refresh',
    'expires_at': expired ? '2000-01-01T00:00:00Z' : '2099-01-01T00:00:00Z',
  }),
);
Future<ProviderConnections> provider(
  MemoryVault vault,
  http.Client client,
) async {
  final store = await LibraryStore.open(':memory:');
  addTearDown(store.close);
  final p = ProviderConnections(
    await SharedPreferences.getInstance(),
    store,
    vault: vault,
    client: client,
  );
  addTearDown(p.dispose);
  return p;
}

void main() {
  test(
    'respostas de pastas e áudio do login anterior são descartadas',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      final vault = MemoryVault();
      await seed(vault);
      var requests = 0;
      final p = await provider(
        vault,
        MockClient((r) async {
          if (r.url.path == '/v1.0/me/drive') {
            return http.Response('{"id":"drive"}', 200);
          }
          if (++requests == 2) started.complete();
          await release.future;
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/children')
                  ? {
                      'value': [
                        {'id': 'folder', 'name': 'Music', 'folder': {}},
                      ],
                    }
                  : {
                      '@microsoft.graph.downloadUrl':
                          'https://audio.example.test/old',
                    },
            ),
            200,
          );
        }),
      );
      await p.checkMicrosoftDrive();
      final audio = expectLater(
        p.resolve(
          const Track(
            id: 'old',
            title: '',
            artist: '',
            driveId: 'drive',
            itemId: 'item',
          ),
        ),
        throwsA(isA<MediaSourceFailure>()),
      );
      final folders = expectLater(
        p.folders(),
        throwsA(isA<MicrosoftAuthFailure>()),
      );
      await started.future;
      await p.microsoft.storeToken({
        'access_token': 'replacement',
        'expires_in': 3600,
      });
      release.complete();
      await Future.wait([audio, folders]);
      expect(
        jsonDecode(vault.values['microsoft.session']!)['access_token'],
        'replacement',
      );
    },
  );
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'microsoft.client_id': registration,
    }),
  );
  for (final action in ['disconnect', 'replace', 'rejected-old-refresh']) {
    test('renovação tardia não altera sessão após $action', () async {
      final started = Completer<void>(), release = Completer<void>();
      final vault = MemoryVault();
      await seed(vault, expired: true);
      await vault.write('lastfm.session', 'preserved');
      final client = MockClient((request) async {
        started.complete();
        await release.future;
        return action == 'rejected-old-refresh'
            ? http.Response('{"error":"invalid_grant"}', 400)
            : http.Response(
                '{"access_token":"late","refresh_token":"late-refresh","expires_in":3600}',
                200,
              );
      });
      addTearDown(client.close);
      final auth = MicrosoftAuth(client, vault, clientId: registration);
      final result = expectLater(
        auth.accessToken(),
        throwsA(isA<MicrosoftAuthFailure>()),
      );
      await started.future;
      if (action == 'disconnect') {
        await auth.disconnect();
      } else {
        final next = MicrosoftAuth(client, vault, clientId: registration);
        await next.storeToken({
          'access_token': 'replacement',
          'refresh_token': 'new-refresh',
          'expires_in': 3600,
        });
        await next.bindDrive('new-drive', await next.sessionIdentity());
      }
      release.complete();
      await result;
      expect(vault.values['lastfm.session'], 'preserved');
      if (action == 'disconnect') {
        expect(vault.values.containsKey('microsoft.session'), isFalse);
      } else {
        final saved = jsonDecode(vault.values['microsoft.session']!);
        expect(saved['access_token'], 'replacement');
        expect(saved['drive_id'], 'new-drive');
      }
    });
  }
  test('sessão legada mantém identidade e drive após renovar sem refresh token novo', () async {
    final vault = MemoryVault();
    await seed(vault, expired: true);
    final client = MockClient(
      (_) async =>
          http.Response('{"access_token":"renewed","expires_in":3600}', 200),
    );
    addTearDown(client.close);
    final auth = MicrosoftAuth(client, vault, clientId: registration);
    final identity = await auth.sessionIdentity();
    await auth.bindDrive('drive', identity);
    final scoped = MicrosoftSessionTokens(auth, identity);
    expect(await scoped.accessToken(), 'renewed');
    final restarted = MicrosoftAuth(client, vault, clientId: registration);
    expect(await restarted.sessionIdentity(), identity);
    final saved = jsonDecode(vault.values['microsoft.session']!);
    expect(saved['drive_id'], 'drive');
    expect(saved['refresh_token'], 'refresh');
    await restarted.storeToken({
      'access_token': 'other-login',
      'expires_in': 3600,
    });
    await expectLater(
      scoped.accessToken(),
      throwsA(isA<MicrosoftAuthFailure>()),
    );
    expect(
      jsonDecode(vault.values['microsoft.session']!)['refresh_token'],
      isNull,
    );
  });
  test('pasta de outra conta não é sincronizada nem reconciliada', () async {
    final vault = MemoryVault();
    await seed(vault);
    final requests = <String>[];
    final p = await provider(
      vault,
      MockClient((r) async {
        requests.add(r.url.path);
        return http.Response('{"id":"current-drive","name":"OneDrive"}', 200);
      }),
    );
    await p.preferences.setBool('microsoft.folder_selected', true);
    await p.preferences.setString('microsoft.folder_drive_id', 'other-drive');
    await p.store.addTracks([
      const Track(
        id: 'kept',
        title: 'Original',
        artist: '',
        driveId: 'other-drive',
        itemId: 'item',
      ),
    ]);
    await p.importMicrosoft();
    expect(p.errorStage, 'account');
    expect(p.errorCode, 'folder_account_mismatch');
    expect(requests, ['/v1.0/me/drive']);
    // Preservation checks include tracks outside the registered folder scope.
    expect(
      (await p.store.loadTracks(includeHidden: true)).single.available,
      isTrue,
    );
    expect(p.microsoftConnected, isTrue);
  });
  test(
    'faixa de outra conta é bloqueada; arquivo local não depende de login',
    () async {
      final vault = MemoryVault();
      await seed(vault);
      final requests = <String>[];
      final p = await provider(
        vault,
        MockClient((r) async {
          requests.add(r.url.path);
          return http.Response('{"id":"current-drive"}', 200);
        }),
      );
      await expectLater(
        p.resolve(
          const Track(
            id: 'foreign',
            title: '',
            artist: '',
            driveId: 'other-drive',
            itemId: 'item',
          ),
        ),
        throwsA(
          isA<MediaSourceFailure>().having(
            (e) => e.message,
            'recovery',
            contains('outra conta'),
          ),
        ),
      );
      expect(requests, ['/v1.0/me/drive']);
      await p.disconnectMicrosoft();
      expect(
        (await p.resolve(
          const Track(
            id: 'local',
            title: '',
            artist: '',
            localPath: 'C:/local.mp3',
          ),
        )).scheme,
        'file',
      );
    },
  );
  test('verificação confirma conta/pasta e lê só amostra do áudio sem bearer no CDN', () async {
    final vault = MemoryVault();
    await seed(vault);
    final requests = <String>[];
    final p = await provider(
      vault,
      MockClient((r) async {
        requests.add(r.url.path);
        if (r.url.host == 'audio.example.test') {
          expect(r.headers['Authorization'], isNull);
          expect(r.headers['Range'], 'bytes=0-4095');
          return http.Response.bytes(
            [1, 2, 3, 4],
            206,
            headers: {
              'content-range': 'bytes 0-3/999999',
              'content-type': 'application/octet-stream',
            },
          );
        }
        final value = switch (r.url.path) {
          '/v1.0/me/drive' => {'id': 'drive', 'name': 'OneDrive'},
          '/v1.0/me/drive/items/music' => {
            'id': 'music',
            'folder': {},
            'parentReference': {'driveId': 'drive'},
          },
          '/v1.0/drives/drive/items/track' => {
            '@microsoft.graph.downloadUrl':
                'https://audio.example.test/sample?secret=signed-only',
          },
          _ => throw StateError('Unexpected metadata request'),
        };
        return http.Response(jsonEncode(value), 200);
      }),
    );
    await p.preferences.setBool('microsoft.folder_selected', true);
    await p.preferences.setString('microsoft.folder_id', 'music');
    await p.preferences.setString(
      'microsoft.folder_path',
      '/drive/root:/Music',
    );
    await p.store.addTracks([
      const Track(
        id: 'outside',
        title: 'A',
        artist: '',
        driveId: 'drive',
        itemId: 'outside',
        sourcePath: '/drive/root:/Other',
      ),
      const Track(
        id: 'inside',
        title: 'Z',
        artist: '',
        driveId: 'drive',
        itemId: 'track',
        sourcePath: '/drive/root:/Music/sub',
      ),
    ]);
    await p.checkMicrosoftConnection();
    expect(p.error, isNull);
    expect(p.microsoftCheckedAt, isNotNull);
    expect(p.microsoftChecks.join(' '), contains('4 bytes'));
    expect(p.preferences.getString('microsoft.folder_drive_id'), 'drive');
    expect(requests, contains('/v1.0/drives/drive/items/track'));
    expect(requests, isNot(contains('/v1.0/drives/drive/items/outside')));
    expect(vault.values.toString(), isNot(contains('signed-only')));
    expect(
      p.preferences.getKeys().map((k) => p.preferences.get(k)).join(' '),
      isNot(contains('signed-only')),
    );
    expect(await p.store.downloadTasks(), isEmpty);
  });
  test(
    'Range ignorado cancela stream sem consumir o arquivo completo',
    () async {
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      addTearDown(stream.close);
      final client = StreamResponseClient(
        http.StreamedResponse(stream.stream, 200, contentLength: 999999),
      );
      await expectLater(
        verifyOneDriveContent(
          client,
          Uri.parse('https://audio.example.test/file'),
        ),
        throwsA(
          isA<MicrosoftAuthFailure>().having(
            (e) => e.code,
            'code',
            'range_unsupported',
          ),
        ),
      );
      expect(cancelled, isTrue);
    },
  );
  test('redirect inseguro não recebe segunda requisição', () async {
    var requests = 0;
    final client = MockClient((r) async {
      requests++;
      return http.Response(
        '',
        302,
        headers: {'location': 'http://audio.example.test/file'},
      );
    });
    addTearDown(client.close);
    await expectLater(
      verifyOneDriveContent(
        client,
        Uri.parse('https://audio.example.test/file'),
      ),
      throwsA(
        isA<MicrosoftAuthFailure>().having((e) => e.stage, 'stage', 'content'),
      ),
    );
    expect(requests, 1);
  });
}

class StreamResponseClient extends http.BaseClient {
  StreamResponseClient(this.response);
  final http.StreamedResponse response;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      response;
}
