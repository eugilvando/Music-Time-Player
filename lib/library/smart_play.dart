import 'dart:math';

import '../domain/track.dart';
import 'catalog.dart';

class ItemMixWork {
  const ItemMixWork(
    this.library,
    this.seeds,
    this.similar,
    this.offline,
    this.offlineOnly,
  );
  final List<Track> library, seeds;
  final Set<String> similar, offline;
  final bool offlineOnly;
}

List<Track> prepareItemMix(ItemMixWork work) => itemMix(
  work.library,
  work.seeds,
  similarArtists: work.similar,
  offline: work.offline,
  offlineOnly: work.offlineOnly,
);

/// An item mix only contains accessible library tracks, never remote guesses.
List<Track> itemMix(
  List<Track> library,
  List<Track> seeds, {
  Set<String> similarArtists = const {},
  Set<String> offline = const {},
  bool offlineOnly = false,
  int count = 30,
  Random? random,
}) {
  if (seeds.isEmpty || count < 2) return [];
  bool allowed(Track t) => offlineOnly
      ? offline.contains(t.id)
      : t.available || offline.contains(t.id);
  final availableSeeds = seeds.where(allowed).toList();
  if (availableSeeds.isEmpty) return [];
  final ids = {availableSeeds.first.id};
  final artists = seeds
      .expand((t) => [...t.artistNames, ...t.albumArtistNames])
      .map(artistNameKey)
      .where(
        (name) =>
            name.isNotEmpty &&
            name != 'unknown artist' &&
            name != 'artista desconhecido',
      )
      .toSet();
  final genres = seeds
      .expand((t) => t.genreNames)
      .map(searchKey)
      .where((v) => v.isNotEmpty)
      .toSet();
  final similar = similarArtists.map(artistNameKey).toSet();
  int score(Track t) {
    final names = [...t.artistNames, ...t.albumArtistNames].map(artistNameKey);
    return (names.any(similar.contains) ? 6 : 0) +
        (names.any(artists.contains) ? 4 : 0) +
        t.genreNames.map(searchKey).where(genres.contains).length * 2;
  }

  final used = <String>{};
  final candidates =
      library
          .where(
            (t) =>
                !ids.contains(t.id) &&
                allowed(t) &&
                used.add(t.id) &&
                score(t) > 0,
          )
          .toList()
        ..shuffle(random ?? Random());
  final ranks = {for (final t in candidates) t.id: score(t)};
  candidates.sort((a, b) => ranks[b.id]!.compareTo(ranks[a.id]!));
  if (candidates.isEmpty) return [];
  return [availableSeeds.first, ...candidates.take(count - 1)];
}

List<Track> smartTracks(
  List<Track> library,
  Track current,
  List<Track> recent, {
  int count = 5,
  bool offlineOnly = false,
  Set<String> offline = const {},
  Random? random,
}) {
  final genres = current.genreNames.map(searchKey).toSet();
  final related = library
      .where(
        (t) =>
            t.id != current.id &&
            (offlineOnly
                ? offline.contains(t.id)
                : t.available || offline.contains(t.id)) &&
            (genres.isNotEmpty
                ? t.genreNames.map(searchKey).any(genres.contains)
                : t.artistNames.any(current.artistNames.contains)),
      )
      .toList();
  final exclude = recent.reversed
      .take(min(20, max(1, related.length ~/ 2)))
      .map((t) => t.id)
      .toSet();
  final candidates = related.where((t) => !exclude.contains(t.id)).toList()
    ..shuffle(random ?? Random());
  final used = <String>{};
  return candidates.where((t) => used.add(t.id)).take(count).toList();
}
