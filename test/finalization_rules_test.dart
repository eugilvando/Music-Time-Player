import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/domain/ports.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/catalog_query.dart';
import 'package:music_time/library/smart_play.dart';
import 'package:music_time/library/local_source_sync.dart';
import 'package:music_time/offline/media_cache.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/infrastructure/lastfm.dart';

class Remote implements MediaSourceResolver {
  int calls = 0;
  @override
  Future<Uri> resolve(Track track) async {
    calls++;
    return Uri.parse('https://fixture.invalid/audio');
  }
}

class WaitingRemote implements MediaSourceResolver {
  final started = Completer<void>();
  final result = Completer<Uri>();
  @override
  Future<Uri> resolve(Track track) {
    started.complete();
    return result.future;
  }
}

class SlowCacheClient extends http.BaseClient {
  final started = Completer<void>();
  final stream = StreamController<List<int>>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    started.complete();
    return http.StreamedResponse(
      stream.stream,
      200,
      contentLength: 4,
      headers: {'content-type': 'audio/mpeg'},
    );
  }
}

class LateCacheClient extends http.BaseClient {
  final started = Completer<void>();
  final response = Completer<http.StreamedResponse>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    started.complete();
    return response.future;
  }
}

const a = Track(
  id: 'a',
  title: 'A',
  artist: 'Artista',
  genre: 'Rock',
  driveId: 'drive',
  itemId: 'a',
  revision: 'r1',
);
const b = Track(
  id: 'b',
  title: 'B',
  artist: 'Artista',
  genre: 'Rock',
  driveId: 'drive',
  itemId: 'b',
  revision: 'r1',
);
const c = Track(
  id: 'c',
  title: 'C',
  artist: 'Outro',
  genre: 'Jazz',
  driveId: 'drive',
  itemId: 'c',
  revision: 'r1',
);

void main() {
  test('reindexação local com tags ilegíveis não converte edição manual em tag original', () async {
    final dir = await Directory.systemTemp.createTemp(
      'music-time-local-override-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = await File(dir.uri.resolve('untagged.mp3').toFilePath())
        .writeAsBytes([1, 2, 3]);
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([
      Track(
        id: file.path,
        title: 'untagged',
        artist: 'Artista desconhecido',
        localPath: file.path,
      ),
    ]);
    await store.registerLocalSource(dir.path, 'Originais', [file.path]);
    await store.setUserMetadata(
      [file.path],
      {
        'title': 'Título manual',
        'artist': 'Autor',
        'artists': ['Autor'],
      },
    );
    final sync = LocalSourceSync(store);
    addTearDown(sync.dispose);
    await sync.sync(dir.path);
    expect(sync.error, isNull);
    expect((await store.loadTracks()).single.title, 'Título manual');
    await store.setUserMetadata([file.path], {}, clear: true);
    expect((await store.loadTracks()).single.title, 'untagged');
    expect((await store.loadTracks()).single.artist, 'Artista desconhecido');
    expect(await file.readAsBytes(), [1, 2, 3]);
  });
  test('limpeza cancela cache mesmo enquanto a fonte resolve acesso', () async {
    final dir = await Directory.systemTemp.createTemp(
      'music-time-cache-resolving-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([a]);
    final remote = WaitingRemote();
    var requests = 0;
    final cache = MediaCache(
      store,
      remote,
      directory: () async => dir,
      client: MockClient((_) async {
        requests++;
        return http.Response.bytes([1], 200);
      }),
    );
    addTearDown(cache.dispose);
    cache.request(a);
    await remote.started.future;
    await cache.clear().timeout(const Duration(seconds: 2));
    remote.result.complete(Uri.parse('https://fixture.invalid/audio'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(requests, 0);
    expect(await cache.rows(), isEmpty);
  });
  test('tags internas sobrevivem à sincronização, backup e restauração sem alterar originais', () async {
    final dir = await Directory.systemTemp.createTemp(
      'music-time-tags-override-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final original = await File('${dir.path}/original.mp3')
        .writeAsBytes([1, 2, 3]);
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final track = Track(
      id: 'local',
      title: 'Sem tags',
      artist: 'Desconhecido',
      localPath: original.path,
    );
    await store.addTracks([track]);
    await store.setFavorite(track.id, true);
    await store.importPlaylist('Preservada', [track.id, track.id]);
    await store.savePlayback([track, track], 1, const Duration(seconds: 2));
    await store.setUserMetadata(
      [track.id],
      {
        'title': 'Título manual',
        'artist': 'Autor',
        'artists': ['Autor'],
        'album': 'Álbum manual',
        'year': 2024,
        'trackNumber': 1,
      },
    );
    await store.addTracks([
      Track(
        id: track.id,
        title: 'Título da fonte atualizado',
        artist: 'Artista da fonte',
        localPath: original.path,
      ),
    ]);
    expect((await store.loadTracks()).single.title, 'Título manual');
    expect(
      (await store.database.query('tracks')).single['title'],
      'Título da fonte atualizado',
    );
    expect(
      (await store.catalogPage(
        CatalogSqlQuery(
          filters: CatalogFilters()..artist = 'AUTOR',
          text: 'titulo manual',
        ),
      )).total,
      1,
    );
    SharedPreferences.setMockInitialValues({});
    final backup = await AppData.backup(
      store,
      await SharedPreferences.getInstance(),
    );
    final restored = await LibraryStore.open(':memory:');
    addTearDown(restored.close);
    await AppData.restore(
      restored,
      await SharedPreferences.getInstance(),
      backup,
    );
    expect((await restored.loadTracks()).single.album, 'Álbum manual');
    expect(await restored.favoriteIds(), {'local'});
    expect((await restored.loadPlayback()).queue.length, 2);
    await store.setUserMetadata(['local'], {}, clear: true);
    expect(
      (await store.loadTracks()).single.title,
      'Título da fonte atualizado',
    );
    expect(await original.readAsBytes(), [1, 2, 3]);
    await expectLater(
      store.setUserMetadata(['local'], {'path': 'forbidden'}),
      throwsArgumentError,
    );
  });
  test(
    'agrupamento conservador não divide pontuação e preserva versões de álbuns',
    () {
      Track song(
        String id,
        String folder, {
        String artist = 'Autor',
        String edition = '',
      }) => Track(
        id: id,
        title: 'Canção',
        artist: artist,
        album: 'Mesmo título',
        albumArtist: artist,
        localPath: '$folder/1.mp3',
        duration: const Duration(minutes: 3),
        trackNumber: 1,
        year: 2020,
        format: 'MP3',
        edition: edition,
      );
      final tracks = [
        song('1', 'A'),
        song('2', 'B', artist: ' AUTOR '),
        song('3', 'C', artist: 'AC, DC'),
        song('4', 'D', artist: 'AC'),
      ];
      final index = CatalogIndex(
        tracks: tracks,
        favorites: {},
        offline: {'2'},
        stats: {},
        sources: {},
        mergeArtists: true,
        mergeAlbums: true,
      );
      expect(index.groups('artists', tracks).length, 3);
      expect(index.groups('albums', tracks).length, 3);
      expect(
        index
            .groups('albums', tracks)
            .where(
              (g) =>
                  g.name == 'Mesmo título' &&
                  g.tracks.first.artist.trim().toLowerCase() == 'autor',
            )
            .single
            .tracks
            .single
            .id,
        '2',
      );
      final versions = [song('x', 'A'), song('y', 'B', edition: 'Remaster')];
      expect(index.groups('albums', versions).length, 2);
      expect(tracks.length, 4);
    },
  );
  test(
    'smart play mantém gênero e disponibilidade e não busca músicas externas',
    () {
      final tracks = [
        a,
        b,
        c,
        const Track(
          id: 'missing',
          title: 'Ausente',
          artist: 'Artista',
          genre: 'Rock',
          driveId: 'd',
          itemId: 'x',
          available: false,
        ),
      ];
      expect(smartTracks(tracks, a, [a]).map((t) => t.id), ['b']);
      expect(
        smartTracks(tracks, a, [a], offlineOnly: true, offline: {'c'}),
        isEmpty,
      );
      expect(
        smartTracks(
          tracks,
          a,
          [a],
          offlineOnly: true,
          offline: {'b'},
        ).map((t) => t.id),
        ['b'],
      );
    },
  );
  test('cache completo é reutilizado offline e expira sem apagar downloads explícitos', () async {
    final dir = await Directory.systemTemp.createTemp(
      'music-time-cache-policy-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([a, b]);
    final remote = Remote();
    var now = DateTime.utc(2026, 10, 14);
    final cache = MediaCache(
      store,
      remote,
      directory: () => Future.value(Directory('${dir.path}/cache')),
      now: () => now,
      client: MockClient((r) async {
        expect(r.headers.containsKey('Authorization'), false);
        return http.Response.bytes(
          [1, 2, 3, 4],
          200,
          headers: {'content-type': 'audio/mpeg'},
        );
      }),
    );
    addTearDown(cache.dispose);
    expect(cache.maxBytes, 10000000000);
    expect(cache.prefetchCount, 5);
    cache.request(a);
    await cache.idle;
    expect(await cache.valid(a), isNotNull);
    expect((await cache.rows()).single['last_played'], isNull);
    final manager = DownloadManager(store, remote, cache: cache);
    addTearDown(manager.dispose);
    manager.offlineOnly = true;
    expect((await manager.resolve(a)).scheme, 'file');
    expect(remote.calls, 1);
    await expectLater(manager.resolve(b), throwsA(isA<MediaSourceFailure>()));
    expect(remote.calls, 1);
    final original = await File('${dir.path}/permanent.audio')
        .writeAsBytes([8, 9]);
    await store.selectOffline('keep', [b]);
    await store.updateDownload(
      b.id,
      'complete',
      path: original.path,
      received: 2,
      total: 2,
    );
    cache.pinned = null;
    now = now.add(const Duration(days: 31));
    await cache.cleanup();
    expect(await cache.rows(), isEmpty);
    expect(await original.exists(), true);
  });
  test(
    'limite de cache remove menos recente e preserva a faixa em reprodução',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'music-time-cache-limit-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      await store.addTracks([a, b, c]);
      var now = DateTime.utc(2026, 10, 14);
      final cache = MediaCache(
        store,
        Remote(),
        directory: () => Future.value(dir),
        now: () => now,
        client: MockClient(
          (_) async => http.Response.bytes(
            [1, 2, 3, 4],
            200,
            headers: {'content-type': 'audio/mpeg'},
          ),
        ),
      );
      addTearDown(cache.dispose);
      cache.maxBytes = 8;
      cache.request(a);
      await cache.idle;
      cache.pinned = a.id;
      now = now.add(const Duration(hours: 1));
      cache.request(b);
      await cache.idle;
      now = now.add(const Duration(hours: 1));
      cache.request(c);
      await cache.idle;
      expect((await cache.rows()).map((r) => r['track_id']).toSet(), {
        'a',
        'c',
      });
      await expectLater(cache.remove('a'), throwsStateError);
      expect(await cache.valid(a), isNotNull);
      cache.pinned = null;
      await cache.clear();
      expect(await cache.rows(), isEmpty);
    },
  );
  test(
    'limpar durante transferência cancela prontamente e não promove parcial',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'music-time-cache-cancel-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      await store.addTracks([a]);
      final client = SlowCacheClient();
      final cache = MediaCache(
        store,
        Remote(),
        directory: () => Future.value(dir),
        client: client,
      );
      addTearDown(cache.dispose);
      cache.request(a);
      await client.started.future;
      client.stream.add([1, 2]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await cache.clear().timeout(const Duration(seconds: 2));
      await client.stream.close();
      expect(await cache.rows(), isEmpty);
      expect(await dir.list().toList(), isEmpty);
    },
  );
  test('retorno tardio de HTTP após limpar cache não grava arquivo', () async {
    final dir = await Directory.systemTemp.createTemp('music-time-cache-late-');
    addTearDown(() => dir.delete(recursive: true));
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([a]);
    final client = LateCacheClient();
    final cache = MediaCache(
      store,
      Remote(),
      directory: () => Future.value(dir),
      client: client,
    );
    addTearDown(cache.dispose);
    cache.request(a);
    await client.started.future;
    await cache.clear().timeout(const Duration(seconds: 2));
    client.response.complete(
      http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200, contentLength: 4),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(await cache.rows(), isEmpty);
    expect(await dir.list().toList(), isEmpty);
  });
  test('cache rejeita HTML', () async {
    final dir = await Directory.systemTemp.createTemp(
      'music-time-cache-invalid-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([a]);
    final cache = MediaCache(
      store,
      Remote(),
      directory: () => Future.value(dir),
      client: MockClient(
        (_) async => http.Response(
          'expired',
          200,
          headers: {'content-type': 'text/html'},
        ),
      ),
    );
    addTearDown(cache.dispose);
    cache.request(a);
    await cache.idle;
    expect(await cache.rows(), isEmpty);
  });
  test('revisão alterada invalida cache e migração v9 conserva catálogo e favoritos', () async {
    final dir = await Directory.systemTemp.createTemp('music-time-schema10-');
    addTearDown(() => dir.delete(recursive: true));
    final dbPath = '${dir.path}/library.db';
    var store = await LibraryStore.open(dbPath);
    await store.addTracks([a]);
    await store.setFavorite(a.id, true);
    final cache = MediaCache(
      store,
      Remote(),
      directory: () async => Directory('${dir.path}/cache'),
      client: MockClient(
        (_) async => http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'audio/mpeg'},
        ),
      ),
    );
    cache.request(a);
    await cache.idle;
    await store.addTracks([
      const Track(
        id: 'a',
        title: 'A',
        artist: 'Artista',
        driveId: 'drive',
        itemId: 'a',
        revision: 'r2',
      ),
    ]);
    expect(await cache.rows(validOnly: true), isEmpty);
    expect(await cache.valid((await store.loadTracks()).single), isNull);
    cache.dispose();
    await store.database.execute('DROP TABLE media_cache');
    await store.database.execute(
      "UPDATE catalog_search SET artists='[\"ARTISTA\"]'",
    );
    await store.database.execute('PRAGMA user_version=9');
    await store.close();
    store = await LibraryStore.open(dbPath);
    try {
      expect(
        (await store.database.rawQuery('PRAGMA user_version'))
            .single['user_version'],
        16,
      );
      expect(
        (await store.catalogPage(
          CatalogSqlQuery(filters: CatalogFilters()..artist = 'artista'),
        )).total,
        1,
      );
      expect(await store.favoriteIds(), {'a'});
      expect(
        await store.database.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
    } finally {
      await store.close();
    }
  });
  test(
    'backup aceita novas preferências tipadas e edição em lote é atômica',
    () async {
      SharedPreferences.setMockInitialValues({
        'visual.cache_enabled': true,
        'visual.cache_gb': 10.0,
        'visual.prefetch_count': 5.0,
        'visual.offline_only': true,
        'visual.smart_play': true,
        'visual.bar_fields': ['artist', 'album'],
        'visual.home_count_recent': 17.0,
      });
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      await store.addTracks([a, b]);
      await store.setUserMetadataBatch({
        'a': {
          'artist': 'Autor A',
          'artists': ['Autor A'],
        },
        'b': {
          'artist': 'Autor B',
          'artists': ['Autor B'],
        },
      });
      expect((await store.loadTracks()).map((t) => t.artist), [
        'Autor A',
        'Autor B',
      ]);
      await expectLater(
        store.setUserMetadataBatch({
          'a': {'title': 'Não salvar'},
          'b': {'path': 'proibido'},
        }),
        throwsArgumentError,
      );
      expect((await store.loadTracks()).first.title, 'A');
      expect(
        AppData.parse(
          await AppData.backup(store, await SharedPreferences.getInstance()),
        )['schema'],
        16,
      );
    },
  );
  test(
    'Last.fm top do mês usa leitura pública e preserva somente metadados reais',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.queryParameters['period'], '1month');
        expect(request.url.queryParameters.containsKey('api_sig'), false);
        return http.Response(
          jsonEncode({
            'toptracks': {
              'track': [
                {
                  'name': 'A',
                  'artist': {'name': 'Artista'},
                  'playcount': '12',
                },
              ],
            },
          }),
          200,
        );
      });
      addTearDown(client.close);
      final result = await LastFmClient(
        client,
        apiKey: 'fixture',
        apiSecret: '',
      ).topTracks('fixture', '1month');
      expect(result.single.title, 'A');
    },
  );
  test('configuração ao vivo serializa alterações rápidas sem perder o último valor', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    addTearDown(settings.dispose);
    final first = settings.updateVisual('home_count_recent', 6.0),
        second = settings.updateVisual('home_count_recent', 9.0),
        third = settings.updateVisual('home_count_recent', 9.0);
    expect(settings.visualNumber('home_count_recent', 0), 9);
    await Future.wait([first, second, third]);
    expect(settings.visualNumber('home_count_recent', 0), 9);
    expect(settings.saving, false);
  });
}
