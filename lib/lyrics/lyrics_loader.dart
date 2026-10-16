import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../domain/track.dart';
import 'lyrics.dart';
import 'id3_lyrics.dart';

String? readEmbeddedLyrics(String file) {
  try {
    final reader = File(file).openSync();
    try {
      final head = reader.readSync(10);
      if (head.length == 10 &&
          head[0] == 73 &&
          head[1] == 68 &&
          head[2] == 51) {
        final size = syncSafe(head, 6);
        if (size <= maxLyricsTagBytes) {
          final text = embeddedId3Lyrics(
            Uint8List.fromList([...head, ...reader.readSync(size)]),
          );
          if (text != null) return text;
        }
      }
    } finally {
      reader.closeSync();
    }
    return readMetadata(File(file), getImage: false).lyrics;
  } catch (_) {
    return null;
  }
}

Future<LyricsDocument?> loadLocalLyrics(Track track) async {
  final local = track.localPath;
  if (local == null) return null;
  final base = path.withoutExtension(local);
  for (final name in ['$base.lrc', '$local.lrc', '$base.txt', '$local.txt']) {
    final file = File(name);
    if (await file.exists()) {
      try {
        if (await file.length() > maxLyricsBytes) continue;
        return await compute(
          parseLyrics,
          decodeLyricsBytes(await file.readAsBytes()),
        );
      } on FormatException {
        /* Try another sidecar or embedded lyrics. */
      } on FileSystemException {
        /* An inaccessible sidecar must not hide embedded lyrics. */
      }
    }
  }
  final embedded = await compute(readEmbeddedLyrics, local);
  if (embedded == null || embedded.trim().isEmpty) return null;
  return compute(parseLyrics, embedded);
}
