import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/local_metadata.dart';
import 'package:music_time/persistence/library_store.dart';

void main() {
  const a = Track(
    id: 'a',
    title: 'Canção',
    artist: 'Earth, Wind & Fire',
    album: 'Mesmo nome',
    albumArtist: 'Various Artists',
    genres: ['Rock', 'Jazz'],
    year: 1998,
    localPath: 'C:/a/song.mp3',
    artists: ['Earth, Wind & Fire', 'Convidado'],
  );
  const b = Track(
    id: 'b',
    title: 'Outra',
    artist: 'Outro',
    album: 'Mesmo nome',
    albumArtist: 'Various Artists',
    localPath: 'C:/b/song.mp3',
  );
  CatalogIndex index() => CatalogIndex(
    tracks: [a, b],
    favorites: {'a'},
    offline: {'a'},
    stats: {
      'a': {'play_count': 2, 'last_played': '2026-10-12T10:00:00Z'},
    },
    sources: {
      'a': [
        {'id': 'folder', 'label': 'Pasta A'},
      ],
    },
  );
  test(
    'busca sem acentos e filtros combinados preservam nomes e identidade',
    () {
      final filters = CatalogFilters()
        ..favorites = true
        ..offline = true
        ..genre = 'Jazz'
        ..source = 'folder'
        ..heard = 'heard';
      expect(index().query(filters, text: 'CANCAO').map((t) => t.id), ['a']);
      expect(a.artist, 'Earth, Wind & Fire');
      expect(a.artistNames, ['Earth', 'Wind', 'Fire', 'Convidado']);
      expect(
        index().groups('artists', [a]).map((g) => g.name),
        containsAll(['Earth', 'Wind', 'Fire', 'Convidado']),
      );
      expect(
        index().groups('albumArtists', [a]).single.name,
        'Various Artists',
      );
    },
  );
  test('álbuns homônimos e datas desconhecidas não são mesclados', () {
    expect(albumKey(a), isNot(albumKey(b)));
    expect(index().groups('genres', [a]).length, 2);
    expect(index().groups('years', [b]).single.name, 'Ano não informado');
    expect(index().groups('decades', [a]).single.name, '1990–1999');
  });
  test('mix pequeno termina sem deduplicar títulos de fontes diferentes', () {
    final mix = index().mix([a, a, b], 50, Random(1));
    expect(mix.length, 2);
    expect(mix.map((t) => t.id).toSet(), {'a', 'b'});
  });
  test(
    'inclusão não muda em reindexação e relações sobrevivem ao banco',
    () async {
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      await store.addTracks([a]);
      final first = (await store.loadTracks()).single;
      await store.addTracks([a]);
      final restored = (await store.loadTracks()).single;
      expect(restored.addedAt, first.addedAt);
      expect(restored.artists, a.artists);
      expect(restored.genres, a.genres);
      await store.recordHistory(
        a.id,
        DateTime.utc(2026, 10, 12),
        const Duration(seconds: 40),
      );
      expect((await store.listeningStats())[a.id]!['play_count'], 1);
    },
  );
}
