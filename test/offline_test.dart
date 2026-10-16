import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/domain/ports.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/offline/download_manager.dart';

class Resolver implements MediaSourceResolver {
  bool offline = false;
  @override
  Future<Uri> resolve(Track track) async {
    if (offline) throw StateError('Rede indisponível');
    return Uri.parse('https://example.com/audio');
  }
}

class WaitingResolver implements MediaSourceResolver {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<Uri> resolve(Track track) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return Uri.parse('https://example.com/audio');
  }
}

void main() {
  test(
    'limpeza de incompletos preserva áudio concluído, originais e subpastas',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'music-time-cache-clean-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final manager = DownloadManager(
        store,
        Resolver(),
        directory: () async => dir,
      );
      addTearDown(manager.dispose);
      final key = List.filled(64, 'a').join();
      final part = await File('${dir.path}/$key.audio.part')
          .writeAsBytes([1, 2]);
      final complete = await File('${dir.path}/$key.audio').writeAsBytes([3]);
      final original = await File('${dir.path}/original.mp3').writeAsBytes([4]);
      final sub = await Directory('${dir.path}/music').create();
      final nested = await File('${sub.path}/$key.audio.part')
          .writeAsBytes([5]);
      manager.running = true;
      await expectLater(manager.clearIncomplete(), throwsStateError);
      expect(await part.exists(), true);
      manager.running = false;
      await manager.clearIncomplete();
      expect(await part.exists(), false);
      expect(await complete.exists(), true);
      expect(await original.exists(), true);
      expect(await nested.exists(), true);
    },
  );
  for (final operation in ['remove', 'pause', 'add']) {
    test(
      'download concorrente: $operation preserva o estado solicitado',
      () async {
        final dir = await Directory.systemTemp.createTemp('music-time-race-');
        addTearDown(() => dir.delete(recursive: true));
        final store = await LibraryStore.open(':memory:');
        addTearDown(store.close);
        const first = Track(
          id: 'onedrive:d:1',
          title: 'A',
          artist: 'Artista',
          driveId: 'd',
          itemId: '1',
        );
        const second = Track(
          id: 'onedrive:d:2',
          title: 'B',
          artist: 'Artista',
          driveId: 'd',
          itemId: '2',
        );
        await store.addTracks([first, second]);
        final resolver = WaitingResolver();
        var requests = 0;
        final manager = DownloadManager(
          store,
          resolver,
          directory: () async => dir,
          client: MockClient((request) async {
            requests++;
            return http.Response.bytes([1, 2, 3], 200);
          }),
        );
        addTearDown(manager.dispose);
        final processing = manager.select('track:1', [first]);
        await resolver.entered.future;
        if (operation == 'remove') await manager.unselect('track:1');
        if (operation == 'pause') await manager.pause(first.id);
        if (operation == 'add') await manager.select('track:2', [second]);
        resolver.release.complete();
        await processing;
        final tasks = await store.downloadTasks();
        final task = tasks.firstWhere((row) => row['id'] == first.id);
        expect(
          task['status'],
          operation == 'add'
              ? 'complete'
              : operation == 'remove'
              ? 'removed'
              : 'paused',
        );
        expect(requests, operation == 'add' ? 2 : 0);
        if (operation == 'remove') {
          expect(await dir.list().toList(), isEmpty);
          await manager.select('track:1', [first]);
          expect((await store.offlineFile(first.id))?['status'], 'complete');
        }
        if (operation == 'add') {
          expect((await store.offlineFile(second.id))?['status'], 'complete');
        }
      },
    );
  }
  test('download concluído funciona sem rede e preserva referências compartilhadas', () async {
    final dir = await Directory.systemTemp.createTemp('music-time-offline-');
    addTearDown(() => dir.delete(recursive: true));
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    const track = Track(
      id: 'onedrive:d:i',
      title: 'A',
      artist: 'Artista',
      driveId: 'd',
      itemId: 'i',
    );
    await store.addTracks([track]);
    var requests = 0;
    final resolver = Resolver();
    final manager = DownloadManager(
      store,
      resolver,
      directory: () async => dir,
      client: MockClient((request) async {
        requests++;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-length': '3'},
        );
      }),
    );
    addTearDown(manager.dispose);
    await manager.select('playlist:1', [track]);
    await manager.select('album:1', [track]);
    expect(requests, 1);
    resolver.offline = true;
    final uri = await manager.resolve(track);
    expect(await File.fromUri(uri).readAsBytes(), [1, 2, 3]);
    await manager.unselect('playlist:1');
    expect(await File.fromUri(uri).exists(), isTrue);
    await manager.unselect('album:1');
    expect(await File.fromUri(uri).exists(), isFalse);
    expect((await store.downloadTasks()).single['status'], 'removed');
  });
  test('arquivo vazio não é promovido como download válido', () async {
    final dir = await Directory.systemTemp.createTemp('music-time-partial-');
    addTearDown(() => dir.delete(recursive: true));
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    const track = Track(
      id: 'onedrive:d:i',
      title: 'A',
      artist: 'Artista',
      driveId: 'd',
      itemId: 'i',
    );
    await store.addTracks([track]);
    final manager = DownloadManager(
      store,
      Resolver(),
      directory: () async => dir,
      client: MockClient((request) async => http.Response.bytes([], 200)),
    );
    addTearDown(manager.dispose);
    await manager.select('track:a', [track]);
    expect((await store.downloadTasks()).single['status'], 'failed');
    expect(await store.offlineFile(track.id), isNull);
    expect(await dir.list().toList(), isEmpty);
  });
}
