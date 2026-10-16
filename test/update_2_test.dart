import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';

void main() {
  const track = Track(
    id: 'local',
    title: 'Local',
    artist: 'Artista',
    localPath: 'C:/music/track.mp3',
  );
  test('migração v4 mantém catálogo e referências como fonte local', () async {
    final root = await Directory.systemTemp.createTemp('music-time-migration');
    addTearDown(() => root.delete(recursive: true));
    final file = '${root.path}/library.db';
    var store = await LibraryStore.open(file);
    await store.addTracks([track]);
    final playlist = await store.importPlaylist('Anterior', [track.id]);
    await store.database.execute('DROP TABLE local_source_tracks');
    await store.database.execute('DROP TABLE local_sources');
    await store.database.execute('PRAGMA user_version=4');
    await store.close();
    store = await LibraryStore.open(file);
    addTearDown(store.close);
    expect((await store.loadTracks()).single.id, track.id);
    expect((await store.localSources()).single['id'], 'legacy');
    await store.removeLocalSource('legacy');
    expect(await store.loadTracks(), isEmpty);
    expect((await store.playlistEntries(playlist)).single['id'], track.id);
  });
  test('remoção de fonte preserva playlist e fonte sobreposta', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([track]);
    await store.registerLocalSource('a', 'A', [track.id]);
    await store.registerLocalSource('b', 'B', [track.id]);
    final playlist = await store.importPlaylist('Lista', [track.id, track.id]);
    await store.removeLocalSource('a');
    expect((await store.loadTracks()).length, 1);
    await store.removeLocalSource('b');
    expect(await store.loadTracks(), isEmpty);
    expect((await store.playlistEntries(playlist)).length, 2);
    await store.registerLocalSource('a', 'A', [track.id]);
    expect((await store.loadTracks()).single.id, track.id);
  });
  test('importação inválida é atômica e mantém ocorrências', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([track]);
    await expectLater(
      store.importPlaylist('Inválida', [track.id, 'missing']),
      throwsA(isA<Exception>()),
    );
    expect(await store.playlists(), isEmpty);
    final id = await store.importPlaylist('Válida', [track.id, track.id]);
    expect((await store.playlistEntries(id)).map((e) => e['id']), [
      track.id,
      track.id,
    ]);
  });
}
