import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/playlists_dialog.dart';

import 'catalog_widget_test.dart' show waitForCatalog;

void main() {
  const a = Track(
    id: 'a',
    title: 'Faixa persistida',
    artist: 'Artista',
    localPath: 'C:/fixture/a.mp3',
  );
  test(
    'playlist persiste após reabrir e ressincronizar preservando repetições',
    () async {
      final dir = await Directory.systemTemp.createTemp('music-time-playlist-');
      final file = '${dir.path}/test.db';
      var store = await LibraryStore.open(file);
      await store.addTracks([a]);
      final id = await store.importPlaylist('Persistida', ['a', 'a']);
      await store.close();
      store = await LibraryStore.open(file);
      try {
        await store.addTracks([a]);
        expect((await store.playlists()).single['track_count'], 2);
        expect((await store.playlistEntries(id)).map((row) => row['id']), [
          'a',
          'a',
        ]);
        final plan = await store.database.rawQuery(
          'EXPLAIN QUERY PLAN SELECT e.id,t.title,t.metadata,(t.cover IS NOT NULL OR t.cover_hash IS NOT NULL) AS has_cover FROM playlist_entries e INDEXED BY playlist_entries_order_idx JOIN tracks t INDEXED BY tracks_catalog_read_idx ON t.id=e.track_id WHERE playlist_id=? ORDER BY e.ordinal,e.id',
          [id],
        );
        expect(plan.toString(), contains('tracks_catalog_read_idx'));
        expect(plan.toString(), contains('playlist_entries_order_idx'));
        expect(plan.toString(), isNot(contains('TEMP B-TREE')));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets('busca não oculta metadados da playlist aberta ao renomear', (
    tester,
  ) async {
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final id = (await tester.runAsync(() async {
      await store.addTracks([a]);
      return store.importPlaylist('Minha lista', ['a']);
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistsPage(
            store: store,
            tracks: const [a],
            initialPlaylist: id,
            query: 'Outra busca',
            onPlay: (_, _) {},
          ),
        ),
      ),
    );
    await waitForCatalog(
      tester,
      () => find.text('Minha lista').evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('Ações da playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renomeada');
    await tester.tap(find.text('Salvar'));
    await waitForCatalog(
      tester,
      () => find.text('Renomeada').evaluate().isNotEmpty,
    );
    expect(
      (await tester.runAsync(store.playlists))!.single['name'],
      'Renomeada',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.close);
  });
}
