import '../domain/track.dart';
import '../infrastructure/lastfm.dart';
import 'catalog.dart';
import 'lastfm_profile.dart';
import 'listening_insights.dart';
import 'm3u8.dart';

typedef ListeningSelectionWork = ({
  ListeningReport report,
  List<Track> catalog,
  String criterion,
  int limit,
  int perArtist,
});

class ListeningCatalogMatches {
  ListeningCatalogMatches(this.matches, this.byId, this.artists, this.albums);
  final PlaylistImportReport matches;
  final Map<String, Track> byId;
  final Map<String, List<String>> artists, albums;
}

ListeningCatalogMatches resolveListeningCatalog(
  (ListeningReport, List<Track>) input,
) {
  final artists = <String, List<String>>{}, albums = <String, List<String>>{};
  final byId = <String, Track>{};
  for (final track in input.$2) {
    byId[track.id] = track;
    for (final artist in {...track.artistNames, track.artist}) {
      artists.putIfAbsent(searchKey(artist), () => []).add(track.id);
      albums
          .putIfAbsent(listeningTrackKey(artist, track.album), () => [])
          .add(track.id);
    }
  }
  return ListeningCatalogMatches(
    matchLastFmProfile((
      input.$1.tracks
          .map((r) => LastFmTrack(r.title, r.artist, r.album, null))
          .toList(),
      input.$2,
    )),
    byId,
    artists,
    albums,
  );
}

PlaylistImportReport prepareListeningPlaylist(ListeningSelectionWork work) {
  if (work.limit < 1 || work.perArtist < 1) {
    throw ArgumentError('Invalid selection size');
  }
  var ranks = List<ListeningRank>.of(work.report.tracks);
  if (work.criterion == 'rediscover') {
    if (!work.report.complete || work.report.invalid != 0) {
      throw StateError('Incomplete history');
    }
    final current = ranks.map((r) => r.key).toSet();
    ranks = [
      for (final row in work.report.previousTracks.entries)
        if (!current.contains(row.key))
          ListeningRank(
            row.key.split('\u0000').last,
            row.key.split('\u0000').first,
            '',
            row.value,
          ),
    ]..sort((a, b) => b.count.compareTo(a.count));
  } else if (work.criterion == 'balanced') {
    final byArtist = <String, List<ListeningRank>>{};
    for (final rank in ranks) {
      byArtist.putIfAbsent(searchKey(rank.artist), () => []).add(rank);
    }
    ranks = [];
    for (var round = 0; round < work.perArtist; round++) {
      for (final rows in byArtist.values) {
        if (round < rows.length) ranks.add(rows[round]);
      }
      if (ranks.length >= work.limit) break;
    }
  }
  final counts = <String, int>{};
  final selected = <LastFmTrack>[];
  for (final rank in ranks) {
    final artist = searchKey(rank.artist);
    if ((counts[artist] ?? 0) >= work.perArtist) continue;
    counts.update(artist, (v) => v + 1, ifAbsent: () => 1);
    selected.add(LastFmTrack(rank.title, rank.artist, rank.album, null));
    if (selected.length >= work.limit) break;
  }
  return matchLastFmProfile((selected, work.catalog));
}
