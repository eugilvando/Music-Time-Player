import 'package:crypto/crypto.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/ports.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/sources/microsoft_auth.dart';
import 'package:music_time/sources/microsoft_sources.dart';

import 'provider_auth_test.dart' show MemoryVault;

const clientId = '00000000-0000-0000-0000-000000000001';
String session(String drive) => jsonEncode({
  'client_id': clientId,
  'access_token': 'fixture-$drive',
  'refresh_token': 'refresh-$drive',
  'session_id': 'generation-$drive',
  'drive_id': drive,
  'expires_at': '2099-01-01T00:00:00Z',
});
http.Client transport({
  String Function()? loginDrive,
  Completer<void>? entered,
  Completer<void>? release,
}) => MockClient((r) async {
  if (r.url.path.endsWith('/devicecode')) {
    return http.Response(
      jsonEncode({
        'device_code': 'fixture-code',
        'user_code': 'fixture',
        'verification_uri': 'https://microsoft.com/devicelogin',
        'expires_in': 60,
        'interval': 1,
      }),
      200,
    );
  }
  if (r.url.path.endsWith('/token')) {
    if (entered != null && !entered.isCompleted) entered.complete();
    if (release != null) await release.future;
    return http.Response(
      jsonEncode({
        'access_token': 'fixture-${loginDrive?.call() ?? 'B'}',
        'refresh_token': 'fixture-refresh',
        'expires_in': 3600,
      }),
      200,
    );
  }
  final drive = (r.headers['Authorization'] ?? '').split('-').last;
  final body = switch (r.url.path) {
    '/v1.0/me/drive' => {'id': drive, 'name': 'Drive $drive'},
    '/v1.0/me/drive/items/music/children' => {
      'value': [
        {
          'id': 'song',
          'name': 'song.wav',
          'eTag': 'revision',
          'parentReference': {'driveId': drive},
          'audio': {
            'title': 'Song $drive',
            'artist': 'Artist $drive',
            'album': 'Album $drive',
          },
        },
      ],
    },
    _ => {'@microsoft.graph.downloadUrl': 'https://content.test/$drive/song'},
  };
  return http.Response(jsonEncode(body), 200);
});

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'microsoft.client_id': clientId,
    }),
  );
  test('duas fontes isolam pastas/sync, roteiam reprodução e preservam sessão legada ao reiniciar', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = MemoryVault();
    await vault.write('microsoft.session', session('A'));
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final root = ProviderConnections(
      prefs,
      store,
      vault: vault,
      client: transport(),
    );
    final second = await root.createMicrosoftSource();
    await vault.write(second.microsoftSessionKey, session('B'));
    await root.refreshStatus();
    for (final source in [root, second]) {
      final drive = source == root ? 'A' : 'B';
      await source.selectFolder({
        'id': 'music',
        'name': 'Música',
        'catalogPath': '/drive/root:/Música',
        'parentReference': {'driveId': drive},
      });
      await source.importMicrosoft();
      expect(source.error, isNull);
      expect(source.syncSummary?['total'], 1);
    }
    final tracks = await store.loadTracks();
    expect(tracks.map((t) => t.account).toSet(), {'A', 'B'});
    expect(
      (await root.resolve(tracks.singleWhere((t) => t.account == 'B'))).path,
      '/B/song',
    );
    final sourceId = second.sourceId;
    root.dispose();
    final restored = ProviderConnections(
      prefs,
      store,
      vault: vault,
      client: transport(),
    );
    addTearDown(restored.dispose);
    await restored.refreshStatus();
    final restoredSecond = restored.microsoftSources.singleWhere(
      (s) => s.sourceId == sourceId,
    );
    expect(restored.microsoftConnected, true);
    expect(restoredSecond.microsoftConnected, true);
    expect(restoredSecond.microsoftFolderSelected, true);
    expect(restoredSecond.syncSummary?['total'], 1);
    expect(
      (await restored.resolve(tracks.singleWhere((t) => t.account == 'A')))
          .path,
      '/A/song',
    );
    expect(
      (await restored.resolve(tracks.singleWhere((t) => t.account == 'B')))
          .path,
      '/B/song',
    );
  });
  test('remover fonte apaga seu download e preserva sessões de outra conta e Last.fm', () async {
    final vault = MemoryVault();
    await vault.write('microsoft.session', session('A'));
    await vault.write('lastfm.session', 'fixture-lastfm');
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final root = ProviderConnections(
      await SharedPreferences.getInstance(),
      store,
      vault: vault,
      client: transport(),
    );
    addTearDown(root.dispose);
    final second = await root.createMicrosoftSource();
    await vault.write(second.microsoftSessionKey, session('B'));
    await second.selectFolder({
      'id': 'music',
      'name': 'Música',
      'catalogPath': '/drive/root:/Música',
      'parentReference': {'driveId': 'B'},
    });
    await second.importMicrosoft();
    final track = (await store.loadTracks()).single;
    final dir = await Directory.systemTemp.createTemp(
      'music-time-source-offline-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = await File(
      '${dir.path}/${sha256.convert(utf8.encode(track.id))}.audio',
    ).writeAsBytes([1, 2, 3]);
    await store.selectOffline('track:fixture', [track]);
    await store.updateDownload(
      track.id,
      'complete',
      path: file.path,
      received: 3,
      total: 3,
    );
    final downloads = DownloadManager(store, root, directory: () async => dir);
    store.beforeSourceRemoval = downloads.removeSourceTracks;
    addTearDown(downloads.dispose);
    await second.removeMicrosoftSource();
    expect(await vault.read('microsoft.session'), session('A'));
    expect(await vault.read('lastfm.session'), 'fixture-lastfm');
    expect(await vault.read(second.microsoftSessionKey), isNull);
    expect(await store.loadTracks(), isEmpty);
    expect(await file.exists(), false);
    expect(await store.database.query('cloud_sources'), isEmpty);
    await expectLater(root.resolve(track), throwsA(isA<MediaSourceFailure>()));
    expect(root.microsoftSources, hasLength(1));
  });
  for (final mode in ['wrong-account', 'duplicate', 'success']) {
    test('login em staging: $mode não sobrescreve outra sessão', () async {
      final vault = MemoryVault();
      await vault.write('microsoft.session', session('A'));
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final root = ProviderConnections(
        await SharedPreferences.getInstance(),
        store,
        vault: vault,
        client: transport(loginDrive: () => mode == 'duplicate' ? 'A' : 'B'),
      );
      addTearDown(root.dispose);
      final target = mode == 'wrong-account'
          ? root
          : await root.createMicrosoftSource();
      // Legacy device protocol only supplies controlled tokens without opening
      // a real browser. Production UI continues to use PKCE/browser exclusively.
      await target.connectMicrosoft(useCode: true);
      expect(await vault.read('microsoft.session'), session('A'));
      if (mode == 'success' || mode == 'duplicate') {
        expect(target.error, isNull);
        expect(
          await target.microsoft.boundDriveId(),
          mode == 'duplicate' ? 'A' : 'B',
        );
      } else {
        expect(
          target.errorCode,
          mode == 'duplicate' ? 'duplicate_account' : 'account_mismatch',
        );
        if (target != root) {
          expect(await vault.read(target.microsoftSessionKey), isNull);
        }
      }
      expect(root.anyMicrosoftLoginPending, false);
    });
  }
  test(
    'login simultâneo entre fontes é bloqueado e liberado ao finalizar',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final root = ProviderConnections(
        await SharedPreferences.getInstance(),
        store,
        vault: MemoryVault(),
        client: transport(entered: entered, release: release),
      );
      addTearDown(root.dispose);
      final first = await root.createMicrosoftSource(),
          second = await root.createMicrosoftSource();
      final login = first.connectMicrosoft(useCode: true);
      await entered.future;
      await second.connectMicrosoft(useCode: true);
      expect(second.errorCode, 'login_in_progress');
      expect(first.microsoftConnected, false);
      release.complete();
      await login;
      expect(first.error, isNull);
      expect(root.anyMicrosoftLoginPending, false);
    },
  );
  test('adoptSession rejeita commit tardio após desconexão/troca', () async {
    final vault = MemoryVault();
    final key = microsoftSourceSessionKey('abcdefghijklmnop');
    await vault.write(key, session('A'));
    final auth = MicrosoftAuth(
      transport(),
      vault,
      clientId: clientId,
      sessionKey: key,
    );
    addTearDown(auth.client.close);
    final snapshot = await vault.read(key);
    await auth.disconnect();
    await expectLater(
      auth.adoptSession(session('B'), expectedSnapshot: snapshot),
      throwsA(isA<MicrosoftAuthFailure>()),
    );
    expect(await vault.read(key), isNull);
  });
}
