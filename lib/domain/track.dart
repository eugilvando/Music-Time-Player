import 'dart:typed_data';

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.sourcePath = '',
    this.fileName = '',
    this.cloudTagsVersion = 0,
    this.cloudCoverEmbedded = false,
    this.revision = '',
    this.available = true,
    this.albumArtist = '',
    this.genre = '',
    this.year,
    this.trackNumber,
    this.discNumber,
    this.cover,
    this.duration = Duration.zero,
    this.localPath,
    this.driveId,
    this.itemId,
    this.artists = const [],
    this.albumArtists = const [],
    this.genres = const [],
    this.albumId = '',
    this.edition = '',
    this.sourceProvider = '',
    this.sourceAccount = '',
    this.format = '',
    this.addedAt,
    this.coverAvailable = false,
  });
  final String id, title, artist, album;
  final Duration duration;
  final String albumArtist, genre, sourcePath, revision, fileName;
  final bool available;
  final int? year, trackNumber, discNumber;
  final Uint8List? cover;
  final String? localPath, driveId, itemId;
  final List<String> artists, albumArtists, genres;
  final String albumId, edition, sourceProvider, sourceAccount, format;
  final DateTime? addedAt;
  final bool coverAvailable;
  final int cloudTagsVersion;
  final bool cloudCoverEmbedded;
  bool get hasArtwork => cover != null || coverAvailable;
  Track withCover(Uint8List? value) => Track(
    id: id,
    title: title,
    artist: artist,
    album: album,
    sourcePath: sourcePath,
    fileName: fileName,
    cloudTagsVersion: cloudTagsVersion,
    cloudCoverEmbedded: cloudCoverEmbedded,
    revision: revision,
    available: available,
    albumArtist: albumArtist,
    genre: genre,
    year: year,
    trackNumber: trackNumber,
    discNumber: discNumber,
    cover: value,
    duration: duration,
    localPath: localPath,
    driveId: driveId,
    itemId: itemId,
    artists: artists,
    albumArtists: albumArtists,
    genres: genres,
    albumId: albumId,
    edition: edition,
    sourceProvider: sourceProvider,
    sourceAccount: sourceAccount,
    format: format,
    addedAt: addedAt,
    coverAvailable: value != null,
  );
  List<String> get artistNames =>
      separateArtistNames(artists.isEmpty ? [artist] : artists);
  List<String> get albumArtistNames => separateArtistNames(
    albumArtists.isEmpty
        ? [albumArtist.isEmpty ? artist : albumArtist]
        : albumArtists,
  );
  List<String> get genreNames => genres.isEmpty
      ? (genre.isEmpty
            ? []
            : genre
                  .split(';')
                  .map((v) => v.trim())
                  .where((v) => v.isNotEmpty)
                  .toList())
      : genres;
  String get provider => sourceProvider.isNotEmpty
      ? sourceProvider
      : localPath != null
      ? 'local'
      : 'onedrive';
  String get account =>
      sourceAccount.isNotEmpty ? sourceAccount : driveId ?? 'Este computador';
  bool get hasScrobbleMetadata =>
      title.trim().isNotEmpty &&
      artist.trim().isNotEmpty &&
      !{
        'artista desconhecido',
        'unknown artist',
      }.contains(artist.trim().toLowerCase());
}

/// Explicit separator policy requested for both track and album artists.
List<String> separateArtistNames(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    for (final part in value.split(_artistSeparator)) {
      final name = part.trim();
      if (name.isNotEmpty && seen.add(name.toLowerCase())) result.add(name);
    }
  }
  return result.isEmpty ? [''] : result;
}

final _artistSeparator = RegExp(
  r'\s*(?:[;,:&]|\b(?:feat|ft)(?:\.(?=\s|$)|(?=\s|$)))\s*',
  caseSensitive: false,
);
