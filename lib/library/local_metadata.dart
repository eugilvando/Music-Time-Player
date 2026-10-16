import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as path;

import '../domain/track.dart';
import 'artwork.dart';
import 'file_availability.dart';

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
      discNumber: metadata.discNumber,
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

String albumKey(Track track) {
  if (track.albumId.isNotEmpty) {
    return 'id:${track.albumId}${track.edition.isEmpty ? '' : '|edition:${track.edition.trim().toLowerCase()}'}';
  }
  final folder = track.localPath != null
      ? path.dirname(track.localPath!)
      : track.sourcePath;
  return '${legacyAlbumKey(track)}|${track.edition}|${track.provider}|${track.account}|$folder';
}
