import '../domain/track.dart';
import 'catalog.dart';

typedef FavoriteCatalog = ({
  List<Track> tracks,
  List<CatalogGroup> artists,
  List<CatalogGroup> albums,
});
FavoriteCatalog prepareFavoriteCatalog(
  ({CatalogIndex index, List<Track> tracks}) work,
) {
  final index = work.index;
  final collections = index.collectionFavorites;
  final names = collections
      .where((k) => k.startsWith('artist:'))
      .map((k) => artistNameKey(k.substring(7)))
      .toSet();
  // Include both artist roles without creating duplicate artist cards.
  final artists = <String, CatalogGroup>{};
  for (final role in ['artists', 'albumArtists']) {
    for (final g in index.groups(role, work.tracks)) {
      final key = artistNameKey(g.name);
      if (!names.contains(key)) continue;
      final existing = artists[key];
      if (existing == null) {
        artists[key] = g;
      } else {
        final ids = existing.tracks.map((t) => t.id).toSet();
        existing.tracks.addAll(g.tracks.where((t) => ids.add(t.id)));
      }
    }
  }
  return (
    tracks: work.tracks.where((t) => index.favorites.contains(t.id)).toList(),
    artists: artists.values.toList()
      ..sort((a, b) => searchKey(a.name).compareTo(searchKey(b.name))),
    albums: index
        .groups('albums', work.tracks)
        .where((g) => g.tracks.any(index.isAlbumFavorite))
        .toList(),
  );
}
