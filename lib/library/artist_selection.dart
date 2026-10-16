import 'dart:math';

import '../domain/track.dart';
import 'catalog.dart';

const artistSelectionMaximum = 500;

List<Track> eligibleArtistTracks(
  List<Track> tracks,
  Set<String> offline, {
  bool offlineOnly = false,
}) => tracks
    .where(
      (t) => offlineOnly
          ? offline.contains(t.id)
          : t.available || offline.contains(t.id),
    )
    .toList();

bool trackByArtist(Track t, String name) => [
  ...t.artistNames,
  ...t.albumArtistNames,
].any((n) => artistNameKey(n) == artistNameKey(name));

/// Exact normalized artist names only. Guests and album-artist credits count.
/// Radio round-robins one main-artist slot and one slot per known similar artist.
/// Each track ID occurs at most once; small pools are never padded.
List<Track> artistSelection(
  List<Track> eligible,
  String artist, {
  int count = 40,
  bool radio = false,
  List<String> similar = const [],
  Random? random,
}) {
  if (count < 1 || count > artistSelectionMaximum) {
    throw RangeError.range(count, 1, artistSelectionMaximum);
  }
  final names = <String, Set<String>>{};
  for (final t in eligible) {
    for (final n in [...t.artistNames, ...t.albumArtistNames]) {
      (names[artistNameKey(n)] ??= {}).add(n.trim());
    }
  }
  // Casing/spacing variants are already the catalog's identity; accents and
  // punctuation are never discarded. No fuzzy homonym merge is attempted.
  final main = artistNameKey(artist);
  final keys = <String>{main};
  if (radio) {
    keys.addAll(
      similar.map(artistNameKey).where((key) => names[key]?.length == 1),
    );
  }
  final groups = <String, List<Track>>{
    for (final key in keys)
      key: eligible.where((t) => trackByArtist(t, key)).toList()
        ..sort((a, b) => a.id.compareTo(b.id)),
  };
  if (groups[main]!.isEmpty || radio && groups.length == 1) return [];
  final rng = random ?? Random();
  for (final g in groups.values) {
    g.shuffle(rng);
  }
  final used = <String>{}, result = <Track>[];
  var hasMore = true;
  while (hasMore && result.length < count) {
    hasMore = false;
    for (final group in groups.values) {
      while (group.isNotEmpty) {
        final t = group.removeLast();
        if (!used.add(t.id)) continue;
        result.add(t);
        hasMore = true;
        break;
      }
      if (result.length == count) break;
    }
  }
  return result;
}

typedef ArtistSelectionWork = ({
  List<Track> tracks,
  String artist,
  int count,
  bool radio,
  List<String> similar,
});
List<Track> prepareArtistSelection(ArtistSelectionWork w) => artistSelection(
  w.tracks,
  w.artist,
  count: w.count,
  radio: w.radio,
  similar: w.similar,
);

/// Favorites and actual listening data first. Catalog fallback is explicitly
/// labelled by the caller. Deduplication follows catalog artist identity.
List<String> suggestedMixArtists(CatalogIndex index, List<Track> tracks) {
  final groups = index.groups('artists', tracks);
  int score(CatalogGroup g) =>
      g.tracks.fold(0, (n, t) => n + index.plays(t)) +
      (index.collectionFavorites.any(
            (k) =>
                k.startsWith('artist:') &&
                artistNameKey(k.substring(7)) == artistNameKey(g.name),
          )
          ? 1000000
          : 0) +
      g.tracks.where(index.isFavorite).length * 1000;
  groups.sort((a, b) {
    final rank = score(b).compareTo(score(a));
    return rank == 0
        ? artistNameKey(a.name).compareTo(artistNameKey(b.name))
        : rank;
  });
  return groups.map((g) => g.name).toList();
}
