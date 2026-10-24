import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as path;

import '../domain/track.dart';
import 'artwork.dart';
import 'file_availability.dart';

int? metadataPosition(Object? value) {
  if (value is int) return value > 0 ? value : null;
  final match = RegExp(r'^\s*(\d+)\s*(?:/\s*\d+\s*)?$')
      .firstMatch(value?.toString() ?? '');
  final number = match == null ? null : int.tryParse(match[1]!);
  return number != null && number > 0 ? number : null;
}

String _trackAlbumFolder(Track track) =>
    track.localPath != null ? path.dirname(track.localPath!) : track.sourcePath;

int? discFolderNumber(String folder) {
  final name = folder.replaceAll('\\', '/').split('/').last;
  final match = RegExp(
    r'^(?:cd|disc|disk|disco)[ _.\-]*0*([1-9]\d{0,2})$',
    caseSensitive: false,
  ).firstMatch(name);
  return match == null ? null : int.tryParse(match[1]!);
}

int? effectiveDiscNumber(Track track) =>
    metadataPosition(track.discNumber) ??
    discFolderNumber(_trackAlbumFolder(track));

int compareAlbumTracks(Track a, Track b) {
  final disc = (effectiveDiscNumber(a) ?? 0x7fffffff).compareTo(
    effectiveDiscNumber(b) ?? 0x7fffffff,
  );
  if (disc != 0) return disc;
  final number = (metadataPosition(a.trackNumber) ?? 0x7fffffff).compareTo(
    metadataPosition(b.trackNumber) ?? 0x7fffffff,
  );
  if (number != 0) return number;
  final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  return title != 0 ? title : a.id.compareTo(b.id);
}

Set<String> albumFavoriteAliases(Track track) => {
  'album:${albumKey(track)}',
  'album:${albumKey(track, combineDiscs: false)}',
  'album:${legacyAlbumKey(track)}',
  if (track.albumId.isNotEmpty) 'album:id:${track.albumId}',
};

Set<String> canonicalAlbumFavorites(
  List<Track> tracks,
  Set<String> favorites,
) => !favorites.any((key) => key.startsWith('album:'))
    ? <String>{}
    : {
        for (final track in tracks)
          if (albumFavoriteAliases(track).any(favorites.contains))
            'album:${albumKey(track)}',
      };

Uint8List? folderArtwork(String value) {
  for (final name in [
    'cover.jpg',
    'folder.jpg',
    'front.jpg',
    'cover.png',
    'folder.png',
    'front.png',
  ]) {
    final file = File(path.join(path.dirname(value), name));
    try {
      if (!fileHasLocalData(file) || file.lengthSync() > maxArtworkBytes) {
        continue;
      }
      final bytes = validatedArtwork(file.readAsBytesSync());
      if (bytes != null) return bytes;
    } catch (_) {
      /* Optional artwork must not break metadata indexing. */
    }
  }
  return null;
}

Uint8List? embeddedArtwork(List<Picture> pictures) {
  for (final picture in [
    ...pictures.where((p) => p.pictureType == PictureType.coverFront),
    ...pictures.where((p) => p.pictureType != PictureType.coverFront),
  ]) {
    final bytes = validatedArtwork(picture.bytes);
    if (bytes != null) return bytes;
  }
  return null;
}

List<Track> readLocalSyncTracks(Map<String, Object> arguments) {
  final failed = <String>{};
  final previous = arguments['previous'] as Map<String, Track>;
  return readLocalTracks(
        arguments['paths'] as List<String>,
        onFailure: failed.add,
      )
      .map(
        (t) => failed.contains(t.id) && previous.containsKey(t.id)
            ? previous[t.id]!.withCover(t.cover ?? previous[t.id]!.cover)
            : t,
      )
      .toList();
}

List<Track> readLocalTracks(
  List<String> paths, {
  void Function(String)? onFailure,
}) => paths.map((value) {
  final fallback = path.basenameWithoutExtension(value);
  try {
    final metadata = readMetadata(File(value), getImage: true);
    VorbisMetadata? vorbis;
    Mp3Metadata? mp3;
    try {
      final raw = readAllMetadata(File(value), getImage: false);
      if (raw is VorbisMetadata) vorbis = raw;
      if (raw is Mp3Metadata) mp3 = raw;
    } catch (_) {
      /* Preserve common tags even if advanced parsing fails. */
    }
    final title = metadata.title?.trim();
    final artist = (mp3 == null ? metadata.artist : mp3.leadPerformer)?.trim();
    return Track(
      id: value,
      localPath: value,
      title: title == null || title.isEmpty ? fallback : title,
      artist: artist == null || artist.isEmpty
          ? 'Artista desconhecido'
          : artist,
      album: metadata.album?.trim() ?? '',
      albumArtist: (mp3?.bandOrOrchestra ?? metadata.albumArtist)?.trim() ?? '',
      genre: metadata.genres.join('; '),
      genres: metadata.genres,
      artists: vorbis?.artist ?? const [],
      albumArtists: vorbis?.albumArtist ?? const [],
      albumId: vorbis?.unknowns['MUSICBRAINZ_ALBUMID'] ?? '',
      edition: vorbis?.unknowns['EDITION'] ?? '',
      format: path.extension(value).replaceFirst('.', '').toUpperCase(),
      year: metadata.year != null && metadata.year!.year > 0
          ? metadata.year!.year
          : null,
      trackNumber: metadata.trackNumber,
      discNumber:
          metadataPosition(metadata.discNumber) ??
          metadataPosition(mp3?.partOfSet) ??
          metadataPosition(vorbis?.unknowns['DISC']),
      duration: metadata.duration ?? Duration.zero,
      cover: embeddedArtwork(metadata.pictures) ?? folderArtwork(value),
    );
  } catch (_) {
    onFailure?.call(value);
    return Track(
      id: value,
      localPath: value,
      title: fallback,
      artist: 'Artista desconhecido',
      format: path.extension(value).replaceFirst('.', '').toUpperCase(),
      cover: folderArtwork(value),
    );
  }
}).toList();

String legacyAlbumKey(Track track) {
  if (track.album.trim().isEmpty) {
    return 'sem-album:${path.dirname(track.localPath ?? track.id)}';
  }
  final artist = track.albumArtist.isEmpty ? track.artist : track.albumArtist;
  return '${track.album.trim().toLowerCase()}|${artist.trim().toLowerCase()}|${track.year ?? ''}';
}

String albumKey(Track track, {bool combineDiscs = true}) {
  if (track.albumId.isNotEmpty) {
    return 'id:${track.albumId}${track.edition.isEmpty ? '' : '|edition:${track.edition.trim().toLowerCase()}'}';
  }
  var folder = _trackAlbumFolder(track);
  final disc = discFolderNumber(folder);
  if (combineDiscs &&
      track.album.trim().isNotEmpty &&
      disc != null &&
      disc == effectiveDiscNumber(track)) {
    folder = track.localPath != null
        ? path.dirname(folder)
        : folder.contains('\\')
        ? path.windows.dirname(folder)
        : path.posix.dirname(folder);
  }
  return '${legacyAlbumKey(track)}|${track.edition}|${track.provider}|${track.account}|$folder';
}
