import '../domain/track.dart';
import '../infrastructure/lastfm.dart';
import 'catalog.dart';
import 'm3u8.dart';

PlaylistImportReport matchLastFmProfile(
  (List<LastFmTrack>, List<Track>) input,
) {
  String key(String artist, String title) =>
      '${searchKey(artist.trim())}\u0000${searchKey(title.trim())}';
  final index = <String, List<Track>>{};
  for (final track in input.$2) {
    for (final artist in track.artistNames.toSet()) {
      index.putIfAbsent(key(artist, track.title), () => []).add(track);
    }
  }
  return PlaylistImportReport([
    for (var i = 0; i < input.$1.length; i++)
      (() {
        final remote = input.$1[i];
        var matches = index[key(remote.artist, remote.title)] ?? <Track>[];
        if (matches.length > 1 && remote.album.trim().isNotEmpty) {
          final album = matches
              .where(
                (t) =>
                    searchKey(t.album.trim()) == searchKey(remote.album.trim()),
              )
              .toList();
          if (album.isNotEmpty) matches = album;
        }
        return PlaylistImportEntry(
          i + 1,
          '${remote.artist} — ${remote.title}${remote.playedAt == null ? '' : ' • ${remote.playedAt!.toLocal()}'}',
          matches.map((t) => t.id).toSet().toList(),
          const [],
        );
      })(),
  ]);
}
