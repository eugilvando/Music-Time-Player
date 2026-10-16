import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';

void main() {
  const first = Track(
    id: 'a',
    title: 'Primeira',
    artist: 'Artista',
    localPath: 'C:/music/a.mp3',
  );
  const second = Track(
    id: 'b',
    title: 'Segunda',
    artist: 'Artista',
    localPath: 'C:/music/b.flac',
  );

  test('catálogo, ordem e posição sobrevivem ao fechamento do banco', () async {
    final directory = await Directory.systemTemp.createTemp('music-time-test-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/library.db';
    var store = await LibraryStore.open(path);
    await store.addTracks([first, second, first]);
    expect((await store.loadTracks()).length, 2);
    await store.savePlayback(
      [second, first, second],
      1,
      const Duration(seconds: 42),
    );
    await store.close();
    store = await LibraryStore.open(path);
    addTearDown(store.close);
    expect((await store.loadTracks()).map((track) => track.id), ['a', 'b']);
    final restored = await store.loadPlayback();
    expect(restored.queue.map((track) => track.id), ['b', 'a', 'b']);
    expect(restored.index, 1);
    expect(restored.position, const Duration(seconds: 42));
  });

  test('falha de integridade não destrói a fila anterior', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([first]);
    await store.savePlayback([first], 0, const Duration(seconds: 10));
    await expectLater(
      store.savePlayback([second], 0, Duration.zero),
      throwsA(isA<Exception>()),
    );
    final restored = await store.loadPlayback();
    expect(restored.queue.single.id, 'a');
    expect(restored.position, const Duration(seconds: 10));
  });

  test('importação inválida é revertida integralmente', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await expectLater(
      store.addTracks([
        first,
        const Track(id: 'remote', title: 'Remote', artist: 'Artist'),
      ]),
      throwsArgumentError,
    );
    expect(await store.loadTracks(), isEmpty);
    expect((await store.loadPlayback()).index, -1);
  });
}
