import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/playlists_dialog.dart';

void main() {
  const a = Track(
    id: 'a',
    title: 'A',
    artist: 'Artista',
    localPath: 'C:/a.mp3',
  );
  const b = Track(
    id: 'b',
    title: 'B',
    artist: 'Artista',
    localPath: 'C:/b.mp3',
  );
  test('favoritos e playlists preservam ocorrências e originais', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([a, b]);
    await store.setFavorite('a', true);
    await store.setFavorite('a', true);
    expect(await store.favoriteIds(), {'a'});
    await store.setFavorite('a', false);
    expect(await store.favoriteIds(), isEmpty);
    final id = await store.createPlaylist('  Coleção  ');
    await store.appendToPlaylist(id, 'a');
    await store.appendToPlaylist(id, 'a');
    await store.appendToPlaylist(id, 'b');
    final entries = await store.playlistEntries(id);
    expect(entries.map((row) => row['id']), ['a', 'a', 'b']);
    await store.reorderPlaylist(
      id,
      entries.map((row) => row['entry_id'] as int).toList().reversed.toList(),
    );
    expect((await store.playlistEntries(id)).map((row) => row['id']), [
      'b',
      'a',
      'a',
    ]);
    await expectLater(
      store.reorderPlaylist(id, [entries.first['entry_id'] as int]),
      throwsArgumentError,
    );
    await store.removePlaylistEntry(entries.first['entry_id'] as int);
    expect((await store.playlistEntries(id)).length, 2);
    await store.renamePlaylist(id, 'Nova');
    expect((await store.playlists()).single['name'], 'Nova');
    await store.deletePlaylist(id);
    expect(await store.playlistEntries(id), isEmpty);
    expect((await store.loadTracks()).length, 2);
  });

  test('migração da versão 1 mantém catálogo e fila', () async {
    final dir = await Directory.systemTemp.createTemp('music-time-upgrade-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/legacy.db';
    sqfliteFfiInit();
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE tracks (id TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT NOT NULL, path TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE queue (ordinal INTEGER PRIMARY KEY, track_id TEXT NOT NULL REFERENCES tracks(id))',
          );
          await db.execute(
            'CREATE TABLE playback (id INTEGER PRIMARY KEY CHECK(id=1), current_index INTEGER NOT NULL, position_ms INTEGER NOT NULL)',
          );
        },
      ),
    );
    await old.insert('tracks', {
      'id': 'a',
      'title': 'A',
      'artist': 'Artista',
      'album': '',
      'path': 'C:/a.mp3',
    });
    await old.insert('queue', {'ordinal': 0, 'track_id': 'a'});
    await old.insert('playback', {
      'id': 1,
      'current_index': 0,
      'position_ms': 5000,
    });
    await old.close();
    final store = await LibraryStore.open(path);
    addTearDown(store.close);
    expect((await store.loadTracks()).single.id, 'a');
    expect((await store.loadPlayback()).position.inSeconds, 5);
    await store.setFavorite('a', true);
    expect(await store.favoriteIds(), {'a'});
    expect(await store.createPlaylist('Migrada'), greaterThan(0));
  });

  testWidgets('editor cria playlist em janela pequena', (tester) async {
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    tester.view.physicalSize = const Size(480, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistsPage(
            store: store,
            tracks: const [],
            onPlay: (_, __) {},
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Criar playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Minha playlist');
    await tester.tap(find.text('Salvar'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Minha playlist'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(store.close);
  });
}
