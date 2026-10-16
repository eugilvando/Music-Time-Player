import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/catalog_query.dart';
import 'package:music_time/persistence/library_store.dart';

void main() {
  test(
    'migração v7 reconstrói índice sem perder catálogo ou favoritos',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'catalog_migration_',
      );
      final path = '${folder.path}/library.db';
      var store = await LibraryStore.open(path);
      try {
        await store.addTracks([
          const Track(
            id: 'old',
            title: 'Música antiga',
            artist: 'Artista',
            localPath: 'C:/old.mp3',
          ),
        ]);
        await store.setFavorite('old', true);
        await store.database.execute('DROP TABLE catalog_search');
        await store.database.execute('PRAGMA user_version=7');
        await store.database.close();
        store = await LibraryStore.open(path);
        final page = await store.catalogPage(
          CatalogSqlQuery(
            filters: CatalogFilters()..favorites = true,
            text: 'MUSICA',
          ),
        );
        expect(page.total, 1);
        expect(page.tracks.single.id, 'old');
        expect(
          await store.database.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
      } finally {
        await store.database.close();
        await folder.delete(recursive: true);
      }
    },
  );
  test(
    'páginas SQL têm ordem estável, busca literal e capas sob demanda',
    () async {
      final store = await LibraryStore.open(':memory:');
      try {
        await store.addTracks(
          List.generate(
            235,
            (i) => Track(
              id: 'id${i.toString().padLeft(3, '0')}',
              title: i == 0 ? 'Canção 100%_real' : 'Mesmo título',
              artist: 'Earth, Wind & Fire',
              artists: ['Earth, Wind & Fire', 'Convidado'],
              album: 'Álbum',
              genres: ['Jazz', 'Rock'],
              year: 1999,
              localPath: 'C:/music/sub/$i.mp3',
              duration: Duration(seconds: i),
              cover: i == 0 ? Uint8List.fromList([1, 2, 3]) : null,
            ),
          ),
        );
        final tracks = await store.loadTracks(includeCovers: false);
        final index = CatalogIndex(
          tracks: tracks,
          favorites: {},
          offline: {},
          stats: {},
          sources: {},
        );
        for (final sort in [
          'title',
          'artist',
          'album',
          'duration',
          'added',
          'last',
          'plays',
        ]) {
          for (final descending in [false, true]) {
            final query = CatalogSqlQuery(
              filters: CatalogFilters(),
              sort: sort,
              descending: descending,
            );
            final ids = <String>[];
            for (final offset in [0, 100, 200]) {
              final page = await store.catalogPage(
                query,
                offset: offset,
                includeCovers: false,
              );
              expect(page.total, 235);
              expect(page.tracks.every((t) => t.cover == null), isTrue);
              ids.addAll(page.tracks.map((t) => t.id));
            }
            expect(
              ids,
              index
                  .query(CatalogFilters(), sort: sort, descending: descending)
                  .map((t) => t.id),
            );
            expect(ids.toSet().length, 235);
          }
        }
        final result = await store.catalogResult(
          CatalogSqlQuery(filters: CatalogFilters(), text: 'CANCAO 100%_'),
        );
        expect(result.single.id, 'id000');
        expect(result.single.hasArtwork, isTrue);
        expect(await store.trackCover('id000'), [1, 2, 3]);
        final combined = CatalogFilters()
          ..artist = 'Convidado'
          ..genre = 'Jazz'
          ..year = '1999'
          ..folder = 'C:/music'
          ..format = 'MP3';
        expect(
          (await store.catalogPage(CatalogSqlQuery(filters: combined))).total,
          235,
        );
        await store.setFavorite('id001', true);
        expect(
          (await store.catalogResult(
            CatalogSqlQuery(filters: CatalogFilters()..favorites = true),
          )).single.id,
          'id001',
        );
        expect(
          (await store.catalogResult(
            CatalogSqlQuery(
              filters: CatalogFilters()..offline = true,
              offline: {'id002'},
            ),
          )).single.id,
          'id002',
        );
        await store.registerLocalSource('folder', 'Pasta', ['id000']);
        await store.database.update(
          'local_sources',
          {'active': 0},
          where: 'id=?',
          whereArgs: ['folder'],
        );
        expect(
          (await store.catalogPage(CatalogSqlQuery(filters: CatalogFilters())))
              .total,
          234,
        );
        await store.rebuildCatalogIndex();
        expect(
          (await store.catalogPage(
            CatalogSqlQuery(filters: CatalogFilters(), text: 'cancao'),
          )).total,
          0,
        );
      } finally {
        await store.database.close();
      }
    },
  );
}
