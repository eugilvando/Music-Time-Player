import 'dart:math';

import '../domain/track.dart';
import 'catalog.dart';
import 'smart_play.dart';

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

String navigationArtistName(Track track) {
  final hasAlbumArtist =
      track.albumArtists.any((n) => n.trim().isNotEmpty) ||
      track.albumArtist.trim().isNotEmpty;
  return (hasAlbumArtist ? track.albumArtistNames : track.artistNames)
          .firstOrNull ??
      '';
}

List<String> localSimilarArtists(List<Track> eligible, String artist) {
  final main = artistNameKey(artist);
  final seeds = eligible.where((t) => trackByArtist(t, artist)).toList();
  final seedIds = seeds.map((t) => t.id).toSet();
  final genres = seeds.expand((t) => t.genreNames).map(artistNameKey).toSet();
  final guests = seeds
      .expand((t) => [...t.artistNames, ...t.albumArtistNames])
      .map(artistNameKey)
      .where((n) => n != main)
      .toSet();
  final scores = <String, int>{}, names = <String, String>{};
  for (final track in eligible) {
    if (seedIds.contains(track.id)) continue;
    final common = track.genreNames
        .map(artistNameKey)
        .where(genres.contains)
        .toSet()
        .length;
    for (final name in {...track.artistNames, ...track.albumArtistNames}) {
      final key = artistNameKey(name);
      if (key.isEmpty ||
          key == main ||
          (common == 0 && !guests.contains(key))) {
        continue;
      }
      names.putIfAbsent(key, () => name);
      scores[key] =
          (scores[key] ?? 0) + common + (guests.contains(key) ? 4 : 0);
    }
  }
  final ranked = scores.keys.toList()
    ..sort((a, b) {
      final score = scores[b]!.compareTo(scores[a]!);
      return score == 0 ? a.compareTo(b) : score;
    });
  return ranked.take(12).map((key) => names[key]!).toList();
}

/// Exact normalized artist names only. Guests and album-artist credits count.
/// Radio round-robins one main-artist slot and one slot per known similar artist.
/// Each track ID occurs at most once; small pools are never padded.
List<Track> artistSelection(
  List<Track> eligible,
  String artist, {
  int count = 40,
  bool radio = false,
  bool focusMain = false,
  List<String> similar = const [],
  Random? random,
}) {
  if (count < 1 || count > artistSelectionMaximum) {
    throw RangeError.range(count, 1, artistSelectionMaximum);
  }
  final byArtist = <String, List<Track>>{};
  for (final t in eligible) {
    for (final key in {
      ...t.artistNames,
      ...t.albumArtistNames,
    }.map(artistNameKey).toSet()) {
      (byArtist[key] ??= []).add(t);
    }
  }
  // Casing/spacing variants are already the catalog's identity; accents and
  // punctuation are never discarded. No fuzzy homonym merge is attempted.
  final main = artistNameKey(artist);
  final keys = <String>{main};
  if (radio) {
    keys.addAll(similar.map(artistNameKey).where(byArtist.containsKey));
  }
  final groups = <String, List<Track>>{
    for (final key in keys)
      key: List<Track>.of(byArtist[key] ?? [])
        ..sort((a, b) => a.id.compareTo(b.id)),
  };
  if (groups[main]!.isEmpty || radio && groups.length == 1) return [];
  final rng = random ?? Random();
  for (final g in groups.values) {
    g.shuffle(rng);
  }
  final used = <String>{}, result = <Track>[];
  final rotation = focusMain && groups.length > 1
      ? [
          for (final entry in groups.entries.where((e) => e.key != main)) ...[
            groups[main]!,
            entry.value,
          ],
        ]
      : groups.values.toList();
  var hasMore = true;
  while (hasMore && result.length < count) {
    hasMore = false;
    for (final group in rotation) {
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

typedef ArtistPreviewWork = ({
  List<Track> tracks,
  String artist,
  int count,
  bool radio,
  bool local,
  List<String> similar,
});
typedef ArtistPreview = ({
  List<Track> tracks,
  int similar,
  int matched,
  bool local,
  bool fallbackMix,
});

ArtistPreview prepareArtistPreview(ArtistPreviewWork work) {
  final otherNames = work.tracks
      .where((t) => !trackByArtist(t, work.artist))
      .expand((t) => [...t.artistNames, ...t.albumArtistNames])
      .map(artistNameKey)
      .toSet();
  final remote = work.similar
      .where((n) => otherNames.contains(artistNameKey(n)))
      .toList();
  final local = work.local || remote.isEmpty;
  final similar = local
      ? localSimilarArtists(work.tracks, work.artist)
      : remote;
  final fallbackMix = work.radio && similar.isEmpty;
  final selected = artistSelection(
    work.tracks,
    work.artist,
    count: work.count,
    radio: similar.isNotEmpty,
    focusMain: !work.radio || fallbackMix,
    similar: similar,
  );
  return (
    tracks: selected,
    similar: local ? similar.length : work.similar.length,
    matched: similar.map(artistNameKey).toSet().length,
    local: local,
    fallbackMix: fallbackMix,
  );
}

ArtistPreview prepareItemPreview(
  ({ArtistPreviewWork work, List<Track> seeds}) input,
) {
  final work = input.work;
  final eligible = {for (final track in work.tracks) track.id: track};
  final seeds = input.seeds
      .where((t) => eligible.containsKey(t.id))
      .map((t) => eligible[t.id]!)
      .toList();
  final preview = prepareArtistPreview(work);
  if (seeds.isEmpty) {
    return (
      tracks: <Track>[],
      similar: preview.similar,
      matched: preview.matched,
      local: preview.local,
      fallbackMix: preview.fallbackMix,
    );
  }
  if (!work.radio) {
    final selected = itemMix(
      work.tracks,
      seeds,
      count: work.count,
      similarArtists: preview.local ? {} : work.similar.toSet(),
      offline: eligible.keys.toSet(),
    );
    final unique = <String>{};
    final result = selected.isEmpty
        ? seeds.where((t) => unique.add(t.id)).take(work.count).toList()
        : selected;
    return (
      tracks: result,
      similar: preview.similar,
      matched: preview.matched,
      local: preview.local,
      fallbackMix: false,
    );
  }
  if (preview.tracks.isEmpty) return preview;
  final rest = preview.tracks.where((t) => t.id != seeds.first.id).toList();
  if (!preview.tracks.any((t) => t.id == seeds.first.id)) {
    final replace = rest.indexWhere((t) => trackByArtist(t, work.artist));
    if (replace >= 0) rest.removeAt(replace);
  }
  final selected = [seeds.first, ...rest].take(work.count).toList();
  return (
    tracks: selected,
    similar: preview.similar,
    matched: preview.matched,
    local: preview.local,
    fallbackMix: preview.fallbackMix,
  );
}

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
