import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/domain/onedrive_identity.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/offline/media_cache.dart';
import 'package:music_time/domain/ports.dart';
import 'package:music_time/sources/additional_sources.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;
import 'microsoft_sources_test.dart' show session, clientId, transport;

Track cloud(String id, String folder) => Track(
  id: id,
  title: id,
  artist: 'Artist',
  driveId: 'drive',
  itemId: id,
  sourcePath: folder,
);

class _Remote implements MediaSourceResolver {
  @override
  Future<Uri> resolve(Track track) async =>
      Uri.parse('https://fixture.test/audio');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'microsoft.client_id': clientId,
    }),
  );

  test('removing a source deletes exclusive tracks and preserves overlapping sources and playlist repair references', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([
      cloud('exclusive', '/music/a'),
      cloud('shared', '/music/b'),
      cloud('other', '/elsewhere'),
    ]);
    await store.saveCloudSource('root', 'drive', '/music', 'Root', true);
    await store.saveCloudSource('child', 'drive', '/music/b', 'Child', false);
    await store.setFavorites(['exclusive', 'shared'], true);
    final playlist = await store.importPlaylist('Keep playlist', [
      'exclusive',
      'shared',
      'exclusive',
    ]);
    for (final (i, id) in [
      'other',
      'exclusive',
      'shared',
      'exclusive',
    ].indexed) {
      await store.database.insert('queue', {'ordinal': i, 'track_id': id});
    }
    await store.database.insert('playback', {
      'id': 1,
      'current_index': 2,
      'position_ms': 500,
    });
    await store.removeCloudSource('root');
    expect(
      (await store.database.query('tracks')).map((r) => r['id']),
      unorderedEquals(['shared', 'other']),
    );
    final entries = await store.playlistOccurrences(playlist);
    expect(entries.map((r) => r['track_id']), [null, 'shared', null]);
    expect(entries.first['original_reference'], '/music/a/exclusive');
    expect(
      (await store.database.query(
        'queue',
        orderBy: 'ordinal',
      )).map((r) => r['track_id']),
      ['other', 'shared'],
    );
    expect((await store.database.query('playback')).single['current_index'], 1);
    expect((await store.database.query('playback')).single['position_ms'], 500);
    expect(await store.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
    'removal aborts before deleting metadata when managed audio cleanup fails',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      await store.addTracks([cloud('one', '/music')]);
      await store.saveCloudSource('source', 'drive', '/music', 'Music', true);
      store.beforeSourceRemoval = (_) async =>
          throw const FileSystemException('fixture failure');
      await expectLater(
        store.removeCloudSource('source'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.database.query('tracks'), hasLength(1));
      expect(await store.database.query('cloud_sources'), hasLength(1));
    },
  );

  test('source removal deletes managed permanent audio and cache while preserving originals', () async {
    final store = await LibraryStore.open(':memory:');
    final temp = await Directory.systemTemp.createTemp('music-source-removal-');
    addTearDown(() async {
      await store.close();
      await temp.delete(recursive: true);
    });
    final original = File('${temp.path}/original.mp3');
    await original.writeAsBytes([1, 2, 3]);
    final cache = MediaCache(store, _Remote(), directory: () async => temp);
    final downloads = DownloadManager(
      store,
      _Remote(),
      cache: cache,
      directory: () async => temp,
    );
    addTearDown(downloads.dispose);
    addTearDown(cache.dispose);
    await store.addTracks([
      cloud('song', '/music'),
      cloud('cached', '/music'),
      Track(
        id: 'local',
        title: 'Local',
        artist: 'Artist',
        localPath: original.path,
      ),
    ]);
    await store.saveCloudSource('source', 'drive', '/music', 'Music', true);
    final permanent = File('${temp.path}/${cache.key('song')}.audio');
    await permanent.writeAsBytes([4, 5, 6]);
    final cached = File('${temp.path}/${cache.key('cached')}.audio');
    await cached.writeAsBytes([7, 8, 9]);
    await store.database.insert('media_cache', {
      'track_id': 'cached',
      'revision': '',
      'path': cached.path,
      'bytes': 3,
      'cached_at': '2026-10-23T00:00:00Z',
    });
    await store.database.insert('downloads', {
      'track_id': 'song',
      'path': permanent.path,
      'status': 'complete',
    });
    store.beforeSourceRemoval = downloads.removeSourceTracks;
    await store.removeCloudSource('source');
    expect(await permanent.exists(), false);
    expect(await cached.exists(), false);
    expect(await original.exists(), true);
    expect(await store.database.query('downloads'), isEmpty);
    expect(await store.database.query('media_cache'), isEmpty);
    expect(await store.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('disconnected additional sources can be removed and do not return after restart', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final prefs = await SharedPreferences.getInstance();
    final vault = MemoryVault();
    final client = MockClient((_) async => http.Response('{}', 200));
    final sources = AdditionalSources(prefs, store, vault, client);
    addTearDown(sources.dispose);
    final source = SourceConnection(
      id: 'source',
      type: 'google',
      label: 'Google',
      connected: false,
    );
    sources.connections.add(source);
    await sources.persist();
    await sources.remove(source);
    expect(sources.connections, isEmpty);
    expect(jsonDecode(prefs.getString('additional_sources')!), isEmpty);
    expect(await store.database.query('cloud_sources'), isEmpty);
  });

  test('Google folder navigation paginates and selection preserves source identity', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final prefs = await SharedPreferences.getInstance();
    final vault = MemoryVault();
    final source = SourceConnection(
      id: 'google-source',
      type: 'google',
      label: 'Music',
    );
    final client = MockClient((r) async {
      expect(r.headers['Authorization'], 'Bearer fixture');
      if (r.url.path.endsWith('/music')) {
        return http.Response(
          jsonEncode({
            'id': 'music',
            'name': 'Music',
            'mimeType': 'application/vnd.google-apps.folder',
          }),
          200,
        );
      }
      expect(r.url.queryParameters['q'], contains("'root' in parents"));
      expect(
        r.url.queryParameters['q'],
        contains("mimeType='application/vnd.google-apps.folder'"),
      );
      return http.Response(
        jsonEncode({
          'files': [
            {
              'id': r.url.queryParameters.containsKey('pageToken')
                  ? 'other'
                  : 'music',
              'name': 'Music',
            },
          ],
          if (!r.url.queryParameters.containsKey('pageToken'))
            'nextPageToken': 'next',
        }),
        200,
      );
    });
    final sources = AdditionalSources(prefs, store, vault, client)
      ..connections.add(source);
    addTearDown(sources.dispose);
    await vault.write(
      sources.secretKey(source.id),
      jsonEncode({
        'access_token': 'fixture',
        'expires_at': '2099-01-01T00:00:00Z',
      }),
    );
    expect(await sources.googleFolders(source, 'root'), hasLength(2));
    final oldId = sources.trackId(source, 'file');
    await sources.selectGoogleFolder(source, 'music', 'Music');
    expect(source.folder, 'music');
    expect(source.folderName, 'Music');
    expect(sources.trackId(source, 'file'), oldId);
    expect(
      SourceConnection.fromJson(
        jsonDecode(prefs.getString('additional_sources')!)[0],
      ).folder,
      'music',
    );
  });

  test(
    'OneDrive CID case changes preserve routing and scan track identity',
    () async {
      const lower = '23e384308662abce', upper = '23E384308662ABCE';
      expect(sameOneDrive(lower, upper), true);
      expect(sameOneDrive('opaque-id', 'OPAQUE-ID'), false);
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final prefs = await SharedPreferences.getInstance();
      final vault = MemoryVault();
      await vault.write('microsoft.session', session(lower));
      final root = ProviderConnections(
        prefs,
        store,
        vault: vault,
        client: transport(),
      );
      addTearDown(root.dispose);
      await store.addTracks([
        const Track(
          id: 'onedrive:$lower:song',
          title: 'Existing',
          artist: 'Artist',
          driveId: lower,
          itemId: 'song',
          sourceAccount: lower,
          sourcePath: '/drive/root:/Music',
        ),
      ]);
      await root.selectFolder({
        'id': 'music',
        'name': 'Music',
        'catalogPath': '/drive/root:/Music',
        'parentReference': {'driveId': lower},
      });
      expect(await store.loadTracks(includeCovers: false), hasLength(1));
      await root.importMicrosoft();
      expect(root.error, isNull);
      final first = (await store.loadTracks(includeCovers: false)).single;
      expect(first.id, 'onedrive:$lower:song');
      expect(first.driveId, upper);
      await vault.write('microsoft.session', session(upper));
      await root.importMicrosoft();
      expect(root.error, isNull);
      final second = (await store.loadTracks(includeCovers: false)).single;
      expect(second.id, first.id);
      expect((await root.resolve(first)).scheme, 'https');
    },
  );
}
