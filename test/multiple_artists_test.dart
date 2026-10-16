import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/catalog_query.dart';
import 'package:music_time/library/home_catalog.dart';
import 'package:music_time/persistence/library_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'requested separators split artists and album artists without duplicates',
    () {
      const track = Track(
        id: 'duet',
        title: 'Song',
        artist: 'Siba; Chico Cesar',
        artists: ['Siba; Chico Cesar, Maria: Ana feat. João ft. Rita & SIBA'],
        albumArtists: ['Siba & Chico Cesar'],
      );
      expect(track.artistNames, [
        'Siba',
        'Chico Cesar',
        'Maria',
        'Ana',
        'João',
        'Rita',
      ]);
      expect(track.albumArtistNames, ['Siba', 'Chico Cesar']);
      expect(separateArtistNames(['AC/DC & Siba']), ['AC/DC', 'Siba']);
      expect(separateArtistNames(['Feature', 'Leftfield', 'Daft Punk']), [
        'Feature',
        'Leftfield',
        'Daft Punk',
      ]);
    },
  );

  test('shared song appears under each artist, recent artists and SQL filter after upgrade', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final track = Track(
      id: 'duet',
      title: 'Song',
      artist: 'Siba; Chico Cesar',
      localPath: 'C:/duet.mp3',
      addedAt: DateTime.utc(2026),
    );
    await store.addTracks([track]);
    final index = CatalogIndex(
      tracks: [track],
      favorites: {},
      offline: {},
      stats: {},
      sources: {},
    );
    final groups = index.groups('artists', [track]);
    expect(groups.map((g) => g.name).toSet(), {'Siba', 'Chico Cesar'});
    expect(groups.every((g) => g.tracks.single.id == 'duet'), true);
    final home = prepareHome((
      index: index,
      tracks: [track],
      quick: 'all',
      limit: 12,
      lastfm: false,
    ));
    expect(home.collections['recent_artists']!.map((g) => g.name).toSet(), {
      'Siba',
      'Chico Cesar',
    });
    for (final artist in ['Siba', 'Chico Cesar']) {
      final page = await store.catalogPage(
        CatalogSqlQuery(filters: CatalogFilters()..artist = artist),
      );
      expect(page.tracks.single.id, 'duet');
    }
  });
}
