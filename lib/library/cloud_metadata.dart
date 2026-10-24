import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show compute;

import 'artwork.dart';
import 'local_metadata.dart';
import 'mp3_duration.dart';
import '../lyrics/id3_lyrics.dart';

const maxCloudMetadataBytes = 8 * 1024 * 1024;
const cloudMetadataVersion = 3;

class CloudTags {
  const CloudTags({
    this.title = '',
    this.artists = const [],
    this.album = '',
    this.albumArtists = const [],
    this.genres = const [],
    this.year,
    this.trackNumber,
    this.discNumber,
    this.duration,
    this.cover,
    this.albumId = '',
    this.edition = '',
  });
  final String title, album, albumId, edition;
  final List<String> artists, albumArtists, genres;
  final int? year, trackNumber, discNumber;
  final Duration? duration;
  final Uint8List? cover;
}

/// Only metadata ranges are read. URLs, bearer tokens and music are not saved.
class CloudMetadataReader {
  CloudMetadataReader(this.client, {this.cancelled, this.allowedUri});
  final bool Function(Uri)? allowedUri;
  final http.Client client;
  final bool Function()? cancelled;
  int received = 0;
  int? totalBytes;

  Future<String?> readEmbeddedLyrics(Uri uri) async {
    received = 0;
    final head = await _range(uri, 0, 10);
    if (head[0] != 73 || head[1] != 68 || head[2] != 51) return null;
    final size = syncSafe(head, 6);
    if (size < 1 || size > maxCloudMetadataBytes - 10) return null;
    return compute(
      embeddedId3Lyrics,
      Uint8List.fromList([...head, ...await _range(uri, 10, size)]),
    );
  }

  Future<String> readLyricText(Uri uri) async {
    for (var redirects = 0; redirects < 4; redirects++) {
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443) {
        throw const FormatException('Invalid lyrics source');
      }
      final response = await client
          .send(http.Request('GET', uri)..followRedirects = false)
          .timeout(const Duration(seconds: 20));
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        await response.stream.listen(null).cancel();
        final location = response.headers['location'];
        if (location == null) break;
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200 ||
          (response.headers['content-type'] ?? '').toLowerCase().contains(
            'text/html',
          ) ||
          (response.headers['content-type'] ?? '').toLowerCase().contains(
            'application/json',
          ) ||
          (response.contentLength ?? 0) > maxLyricsBytes) {
        await response.stream.listen(null).cancel();
        throw const FormatException('Lyrics unavailable');
      }
      final bytes = BytesBuilder(copy: false);
      final chunks = StreamIterator(
        response.stream.timeout(const Duration(seconds: 20)),
      );
      try {
        while (await chunks.moveNext()) {
          if (bytes.length + chunks.current.length > maxLyricsBytes) {
            throw const FormatException('Lyrics exceed size limit');
          }
          bytes.add(chunks.current);
        }
      } finally {
        await chunks.cancel();
      }
      return decodeLyricsBytes(bytes.takeBytes());
    }
    throw const FormatException('Invalid lyrics redirect');
  }

  Future<Uint8List> _range(Uri uri, int start, int length) async {
    if (length < 1 ||
        received + length > maxCloudMetadataBytes ||
        cancelled?.call() == true) {
      throw const FormatException('Limite de metadados');
    }
    for (var redirects = 0; redirects < 4; redirects++) {
      if (allowedUri != null
          ? !allowedUri!(uri)
          : (uri.scheme != 'https' ||
                uri.host.isEmpty ||
                uri.port != 443 ||
                uri.userInfo.isNotEmpty)) {
        throw const FormatException('Origem inválida');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['Range'] = 'bytes=$start-${start + length - 1}';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        await response.stream.listen(null).cancel();
        final location = response.headers['location'];
        if (location == null) break;
        uri = uri.resolve(location);
        continue;
      }
      final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
          .firstMatch(response.headers['content-range'] ?? '');
      final type = (response.headers['content-type'] ?? '').toLowerCase();
      if (response.statusCode != 206 ||
          range == null ||
          int.parse(range.group(1)!) != start ||
          int.parse(range.group(2)!) != start + length - 1 ||
          int.parse(range.group(3)!) <= start + length - 1 ||
          (response.contentLength != null &&
              response.contentLength != length) ||
          type.startsWith('text/') ||
          type.contains('json')) {
        await response.stream.listen(null).cancel();
        throw const FormatException('Leitura parcial indisponível');
      }
      final bytes = BytesBuilder(copy: false);
      final chunks = StreamIterator(
        response.stream.timeout(const Duration(seconds: 20)),
      );
      try {
        while (await chunks.moveNext()) {
          if (cancelled?.call() == true ||
              bytes.length + chunks.current.length > length) {
            throw const FormatException('Leitura interrompida');
          }
          bytes.add(chunks.current);
        }
      } finally {
        await chunks.cancel();
      }
      if (bytes.length != length) {
        throw const FormatException('Metadados incompletos');
      }
      received += bytes.length;
      totalBytes = int.parse(range.group(3)!);
      return bytes.takeBytes();
    }
    throw const FormatException('Redirecionamento inválido');
  }

  Future<CloudTags?> read(Uri uri, String name, {int? fileSize}) async {
    received = 0;
    totalBytes = null;
    if (!RegExp(r'\.(mp3|flac)$', caseSensitive: false).hasMatch(name)) {
      return null;
    }
    final head = await _range(uri, 0, 10);
    Uint8List data;
    var mp3 = ascii.decode(head.sublist(0, 3), allowInvalid: true) == 'ID3';
    var id3v1 = false;
    Duration? duration;
    Future<Duration?> audioDuration(int offset) async {
      final available = (fileSize ?? totalBytes ?? 0) - offset;
      if (available < 64 || received > maxCloudMetadataBytes - 4096) {
        return null;
      }
      try {
        return mp3FrameDuration(
          await _range(uri, offset, available.clamp(0, 256)),
        );
      } catch (_) {
        // Optional duration must not discard valid tags or Graph metadata.
        return null;
      }
    }

    if (mp3) {
      if (!{3, 4}.contains(head[3]) ||
          (head[3] == 3 ? head[5] & 0x1f != 0 : head[5] & 0x8f != 0) ||
          head.sublist(6).any((b) => b > 127)) {
        return null;
      }
      final size = (head[6] << 21) | (head[7] << 14) | (head[8] << 7) | head[9];
      if (size == 0 || size + 10 > maxCloudMetadataBytes) return null;
      var body = await _range(uri, 10, size);
      duration = await audioDuration(
        size + 10 + (head[3] == 4 && head[5] & 0x10 != 0 ? 10 : 0),
      );
      if (head[3] == 3 && head[5] & 0x80 != 0) {
        final restored = BytesBuilder(copy: false);
        for (var i = 0; i < body.length; i++) {
          restored.addByte(body[i]);
          if (body[i] == 255 && i + 1 < body.length && body[i + 1] == 0) i++;
        }
        body = restored.takeBytes();
      }
      if (head[5] & 0x40 != 0) {
        if (body.length < 4) return null;
        final extended = head[3] == 3
            ? ByteData.sublistView(body).getUint32(0) + 4
            : (body[0] << 21) | (body[1] << 14) | (body[2] << 7) | body[3];
        if (extended < 6 || extended > body.length) return null;
        body = Uint8List.sublistView(body, extended);
      }
      // Validate every frame before invoking the existing parser: untrusted
      // declared sizes must never cause an allocation outside the bounded tag.
      var offset = 0, frames = 0;
      while (offset + 10 <= body.length && body[offset] != 0) {
        if (++frames > 4096 || body[offset + 9] != 0) return null;
        final sizes = body.sublist(offset + 4, offset + 8);
        if (head[3] == 4 && sizes.any((b) => b > 127)) return null;
        final frameSize = head[3] == 4
            ? (sizes[0] << 21) | (sizes[1] << 14) | (sizes[2] << 7) | sizes[3]
            : ByteData.sublistView(body).getUint32(offset + 4);
        if (frameSize < 1 || offset + 10 + frameSize > body.length) return null;
        offset += 10 + frameSize;
      }
      // Existing parser counts its header in its frame offset. Padding keeps
      // the final frame readable without changing any original tag fields.
      final paddedSize = body.length + 10;
      final header = Uint8List.fromList(head);
      header[5] = 0;
      for (var i = 0; i < 4; i++) {
        header[9 - i] = (paddedSize >> (7 * i)) & 127;
      }
      data = Uint8List.fromList([...header, ...body, ...Uint8List(10)]);
    } else if (ascii.decode(head.sublist(0, 4), allowInvalid: true) == 'fLaC') {
      final blocks = <Uint8List>[];
      var offset = 4;
      var ended = false;
      for (var count = 0; count < 128; count++) {
        final header = await _range(uri, offset, 4);
        final type = header[0] & 127;
        final size = (header[1] << 16) | (header[2] << 8) | header[3];
        if (count == 0 && (type != 0 || size != 34)) return null;
        if ({0, 4, 6}.contains(type) &&
            size > 0 &&
            size + received <= maxCloudMetadataBytes &&
            (type != 6 || size <= maxArtworkBytes + 1024)) {
          final body = await _range(uri, offset + 4, size);
          if (!_validFlacBlock(type, body)) return null;
          blocks.add(Uint8List.fromList([type, ...header.sublist(1), ...body]));
        }
        offset += size + 4;
        if (header[0] & 128 != 0) {
          ended = true;
          break;
        }
      }
      if (!ended || blocks.isEmpty) return null;
      blocks.last[0] |= 128;
      data = Uint8List.fromList([
        ...ascii.encode('fLaC'),
        for (final block in blocks) ...block,
      ]);
    } else if (name.toLowerCase().endsWith('.mp3') &&
        (fileSize ?? totalBytes ?? 0) >= 128) {
      duration = await audioDuration(0);
      data = await _range(uri, (fileSize ?? totalBytes!) - 128, 128);
      if (ascii.decode(data.sublist(0, 3), allowInvalid: true) != 'TAG') {
        return duration == null ? null : CloudTags(duration: duration);
      }
      mp3 = id3v1 = true;
    } else {
      return null;
    }
    final temporary = await Directory.systemTemp.createTemp('music-time-tags-');
    try {
      final file = await File('${temporary.path}/tags').writeAsBytes(data);
      final reader = file.openSync();
      try {
        if (mp3) {
          final tags = id3v1
              ? ID3v1Parser().parse(reader)
              : ID3v2Parser(fetchImage: true).parse(reader);
          return CloudTags(
            title: tags.songName?.trim() ?? '',
            artists: _names([tags.leadPerformer ?? '']),
            album: tags.album?.trim() ?? '',
            albumArtists: _names([tags.bandOrOrchestra ?? '']),
            genres: _names(tags.genres),
            year: _positive(
              tags.year ??
                  int.tryParse(
                    (tags.customMetadata['TDRC'] ?? '').split('-').first,
                  ),
            ),
            trackNumber: _positive(tags.trackNumber),
            discNumber:
                _positive(tags.discNumber) ?? metadataPosition(tags.partOfSet),
            duration: duration ?? tags.duration,
            cover: embeddedArtwork(tags.pictures),
          );
        }
        final tags = FlacParser(fetchImage: true).parse(reader);
        return CloudTags(
          title: tags.title.firstOrNull?.trim() ?? '',
          artists: _names(tags.artist),
          album: tags.album.firstOrNull?.trim() ?? '',
          albumArtists: _names(tags.albumArtist),
          genres: _names(tags.genres),
          year: _positive(tags.date.firstOrNull?.year),
          trackNumber: _positive(tags.trackNumber.firstOrNull),
          discNumber:
              _positive(tags.discNumber) ??
              metadataPosition(tags.unknowns['DISC']),
          duration: tags.duration,
          cover: embeddedArtwork(tags.pictures),
          albumId: tags.unknowns['MUSICBRAINZ_ALBUMID'] ?? '',
          edition: tags.unknowns['EDITION'] ?? '',
        );
      } finally {
        reader.closeSync();
      }
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}

List<String> _names(List<String> values) =>
    values.map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList();
int? _positive(int? value) => value != null && value > 0 ? value : null;

bool _validFlacBlock(int type, Uint8List body) {
  if (type == 0) return body.length == 34;
  var position = type == 6 ? 4 : 0;
  int number(Endian endian) {
    if (position + 4 > body.length) {
      throw const FormatException('Bloco incompleto');
    }
    final value = ByteData.sublistView(body).getUint32(position, endian);
    position += 4;
    return value;
  }

  void skip(int length) {
    if (position + length > body.length) {
      throw const FormatException('Bloco incompleto');
    }
    position += length;
  }

  try {
    if (type == 4) {
      skip(number(Endian.little));
      final count = number(Endian.little);
      if (count > 4096) return false;
      for (var i = 0; i < count; i++) {
        skip(number(Endian.little));
      }
    } else if (type == 6) {
      skip(number(Endian.big));
      skip(number(Endian.big));
      skip(16);
      final length = number(Endian.big);
      if (length > maxArtworkBytes) return false;
      skip(length);
    }
    return position == body.length;
  } on FormatException {
    return false;
  }
}
