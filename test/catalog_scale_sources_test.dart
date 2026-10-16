import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/catalog_query.dart';
import 'package:music_time/library/m3u8.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/infrastructure/onedrive.dart';
import 'package:music_time/domain/ports.dart';

import 'microsoft_sources_test.dart' show session, clientId;
import 'provider_auth_test.dart' show MemoryVault;

class FixtureTokens implements AccessTokenProvider {
  @override
  Future<String> accessToken() async => 'fixture';
}

void main() {
  test(
    '30 mil faixas: lotes, fontes sobrepostas, busca e importação',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final tracks = List.generate(
        30000,
        (i) => Track(
          id: 'onedrive:A:$i',
          title: 'Faixa $i',
          artist: 'Artista ${i % 500}',
          album: 'Álbum ${i % 3000}',
          sourceProvider: 'onedrive',
          sourceAccount: 'A',
          driveId: 'A',
          itemId: '$i',
          sourcePath: i.isEven
              ? '/drive/root:/Nacionais'
              : '/drive/root:/Internacionais',
          fileName: '$i.mp3',
        ),
      );
      final timer = Stopwatch()..start();
      await store.addTracks(tracks);
      final writeMs = timer.elapsedMilliseconds;
      await store.saveCloudSource(
        'n',
        'A',
        '/drive/root:/Nacionais',
        'Nacionais',
        true,
      );
      await store.saveCloudSource(
        'i',
        'A',
        '/drive/root:/Internacionais',
        'Internacionais',
        true,
      );
      timer.reset();
      final loaded = await store.loadTracks(includeCovers: false);
      final loadMs = timer.elapsedMilliseconds;
      expect(loaded.length, 30000);
      expect(loaded.every((t) => t.cover == null), true);
      await store.saveCloudSource(
        'n',
        'A',
        '/drive/root:/Nacionais',
        'Nacionais',
        false,
      );
      expect((await store.loadTracks(includeCovers: false)).length, 15000);
      final filters = CatalogFilters()..source = 'i';
      expect(
        (await store.catalogPage(
          CatalogSqlQuery(filters: filters),
          offset: 0,
          limit: 50,
        )).total,
        15000,
      );
      await store.saveCloudSource('root', 'A', '/drive/root:', 'Tudo', true);
      expect((await store.loadTracks(includeCovers: false)).length, 30000);
      await store.finishOneDriveFolder(
        'A',
        '/drive/root:/Nacionais',
        tracks
            .where((t) => t.id.split(':').last.endsWith('0'))
            .map((t) => t.id)
            .toSet(),
      );
      expect(
        (await store.loadTracks(
          includeCovers: false,
          includeHidden: true,
        )).length,
        30000,
      );
      expect(
        (await store.loadTracks(includeCovers: false))
            .singleWhere((t) => t.itemId == '1')
            .available,
        true,
      );
      timer.reset();
      final content = [for (final t in tracks) oneDrivePlaylistPath(t)!]
          .join('\n');
      final report = reviewM3u8(content, 'fixture.m3u8', loaded);
      expect(report.unresolved, 0);
      expect(report.ids.length, 30000);
      final importMs = timer.elapsedMilliseconds;
      debugPrint(
        'FIXTURE_30000 write_ms=$writeMs load_ms=$loadMs import_ms=$importMs',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('Graph honra Retry-After e recupera falha transitória', () async {
    var calls = 0;
    final waits = <Duration>[];
    final graph = OneDriveClient(
      MockClient((_) async {
        calls++;
        if (calls == 1) {
          return http.Response('{}', 429, headers: {'retry-after': '90'});
        }
        if (calls == 2) throw http.ClientException('fixture network');
        return http.Response('{"id":"A"}', 200);
      }),
      FixtureTokens(),
      wait: (duration) async {
        waits.add(duration);
      },
    );
    expect((await graph.drive())['id'], 'A');
    expect(waits.first, const Duration(seconds: 90));
    expect(calls, 3);
  });

  test(
    'falha entre páginas retoma pelo checkpoint sem repetir a primeira',
    () async {
      SharedPreferences.setMockInitialValues({
        'microsoft.client_id': clientId,
        'microsoft.folder_selected': true,
        'microsoft.folder_drive_id': 'A',
        'microsoft.folder_id': 'music',
        'microsoft.folder_path': '/drive/root:/Música',
      });
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final vault = MemoryVault();
      await vault.write('microsoft.session', session('A'));
      var failure = true, firstPages = 0;
      final client = MockClient((r) async {
        if (r.url.path == '/v1.0/me/drive') {
          return http.Response('{"id":"A"}', 200);
        }
        if (r.url.path == '/v1.0/page2' && failure) {
          return http.Response('{}', 403);
        }
        if (r.url.path.endsWith('/children')) firstPages++;
        final first = r.url.path.endsWith('/children');
        return http.Response(
          jsonEncode({
            'value': [
              {
                'id': first ? '1' : '2',
                'name': first ? '1.wav' : '2.wav',
                'audio': {'artist': 'Fixture'},
                'eTag': 'v1',
              },
            ],
            if (first)
              '@odata.nextLink': 'https://graph.microsoft.com/v1.0/page2',
          }),
          200,
        );
      });
      final root = ProviderConnections(
        await SharedPreferences.getInstance(),
        store,
        vault: vault,
        client: client,
      );
      addTearDown(root.dispose);
      await root.importMicrosoft();
      expect(root.syncStatus, 'failed');
      expect(await store.cloudCheckpoint(root.microsoftSessionKey), isNotNull);
      expect((await store.loadTracks()).length, 1);
      failure = false;
      await root.importMicrosoft();
      expect(root.syncStatus, 'completed');
      expect(firstPages, 1);
      expect((await store.loadTracks()).length, 2);
      expect(await store.cloudCheckpoint(root.microsoftSessionKey), isNull);
    },
  );
}
