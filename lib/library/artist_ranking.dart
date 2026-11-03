import '../domain/track.dart';
import '../infrastructure/lastfm.dart';
import 'artist_selection.dart';
import 'catalog.dart';

typedef ArtistRankedTracks = ({List<Track> tracks, int remoteMatches});
typedef ArtistRankingLoader = Future<ArtistRankedTracks> Function(
  String artist,
  List<Track> eligible,
  int limit,
  bool refresh,
);

/// Rank only eligible credits for this artist. Never turn a missing remote
/// track into a different artist's recording or invent local play counts.
ArtistRankedTracks rankArtistTracks({
  required String artist,
  required List<Track> eligible,
  required Map<String, Map<String, Object?>> stats,
  List<LastFmTrack> ranking = const [],
  int limit = 20,
}) {
  final byId = <String, Track>{
    for (final t in eligible)
      if (t.available && !t.libraryHidden && trackByArtist(t, artist)) t.id: t,
  };
  final local = byId.values.toList()
    ..sort((a, b) {
      final plays = (stats[b.id]?['play_count'] as int? ?? 0).compareTo(
        stats[a.id]?['play_count'] as int? ?? 0,
      );
      if (plays != 0) return plays;
      final title = a.title.compareTo(b.title);
      return title != 0 ? title : a.id.compareTo(b.id);
    });
  final titles = <String, List<Track>>{};
  for (final t in local) {
    (titles[searchKey(t.title.trim())] ??= []).add(t);
  }
  final used = <String>{};
  final result = <Track>[];
  for (final remote in ranking) {
    if (artistNameKey(remote.artist) != artistNameKey(artist)) continue;
    final matches = titles[searchKey(remote.title.trim())];
    if (matches == null || matches.isEmpty) continue;
    // For duplicate editions choose the most played locally, deterministically.
    final t = matches.first;
    if (used.add(t.id)) result.add(t);
    if (result.length >= limit) break;
  }
  final matched = result.length;
  for (final t in local) {
    if (result.length >= limit) break;
    if (used.add(t.id)) result.add(t);
  }
  return (
    tracks: limit <= 0 ? [] : result.take(limit).toList(),
    remoteMatches: matched,
  );
}

/// Empty means that the user should choose an artist for this compilation.
String mixSeedArtist(List<Track> seeds) {
  if (seeds.isEmpty) return '';
  if (seeds.length == 1) return seeds.first.artistNames.firstOrNull ?? '';
  final album = seeds.first.albumArtistNames;
  const compilations = {'various artists', 'various', 'vários artistas', 'va'};
  if (album.length == 1 &&
      !compilations.contains(artistNameKey(album.first)) &&
      seeds.every(
        (t) => t.albumArtistNames.any(
          (a) => artistNameKey(a) == artistNameKey(album.first),
        ),
      )) {
    return album.first;
  }
  final names = seeds.expand((t) => t.artistNames).toSet();
  return names.length == 1 ? names.single : '';
}
