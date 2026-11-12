import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/track.dart';
import '../offline/download_manager.dart';
import '../sources/provider_connections.dart';
import 'lyrics.dart';
import 'lyrics_loader.dart';
import 'online_lyrics.dart';
import 'lyrics_session.dart';

class LibraryLyrics {
  LibraryLyrics(this.downloads, {this.durationFor, this.cacheDirectory});
  final Future<Directory> Function()? cacheDirectory;
  final Duration Function(Track)? durationFor;
  final DownloadManager downloads;
  late final session = LyricsSession(
    (track, refresh) => _load(track, refresh, lyricsIdentity(track)),
  );
  String sessionKey(Track track) =>
      '${lyricsIdentity(track)}|'
      '${track.duration > Duration.zero ? track.duration.inSeconds : durationFor?.call(track).inSeconds}|${downloads.offlineOnly}|'
      '${downloads.remote is ProviderConnections ? (downloads.remote as ProviderConnections).preferences.getBool('visual.online_lyrics') : null}';
  Future<LyricsDocument?> load(Track track, bool refresh) =>
      session.load(track, refresh, key: sessionKey(track));
  void prefetch(Iterable<Track> tracks) =>
      session.prefetch(tracks, keyFor: sessionKey);
  void dispose() => session.dispose();

  Future<LyricsDocument?> _load(Track track, bool refresh, String key) async {
    if (track.localPath != null) {
      try {
        final local = await loadLocalLyrics(track);
        if (local != null) return local;
      } on FileSystemException {
        // A removed/inaccessible local file cannot block cached or online lyrics.
      }
    }
    try {
      // Explicit downloads and automatic audio cache can supply embedded tags.
      final cached = await downloads.cache?.valid(track);
      if (cached != null) {
        final text = await compute(readEmbeddedLyrics, cached.path);
        if (text != null) return await compute(parseLyrics, text);
      }
      final row = await downloads.store.offlineFile(track.id);
      if (row != null && row['path'] is String) {
        final text = await compute(readEmbeddedLyrics, row['path'] as String);
        if (text != null) return await compute(parseLyrics, text);
      }
    } catch (_) {
      // Missing or malformed downloaded tags cannot block other sources.
    }
    final directory =
        await cacheDirectory?.call() ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'lyrics-cache',
          ),
        );
    final cache = File(
      path.join(directory.path, '${sha256.convert(utf8.encode(key))}.txt'),
    );
    LyricsDocument? previous;
    try {
      // Preserve existing offline lyrics from versions that keyed by revision only.
      final legacyKey = '${track.id}|${track.revision}';
      final legacy = File(
        path.join(
          directory.path,
          '${sha256.convert(utf8.encode(legacyKey))}.txt',
        ),
      );
      final readable = await cache.exists() ? cache : legacy;
      if (await readable.exists()) {
        if (await readable.length() <= 2 * 1024 * 1024) {
          final text = await readable.readAsString();
          previous = await compute(parseLyrics, text);
          if (readable.path != cache.path) await _save(directory, cache, text);
          if (downloads.offlineOnly || !refresh) {
            return previous;
          }
        }
      }
    } on FileSystemException {
      // Optional cache cannot prevent audio-tag or remote lyrics.
    } on FormatException {
      // Refresh corrupt cache.
    }
    if (!downloads.offlineOnly && downloads.remote is ProviderConnections) {
      try {
        final text = await (downloads.remote as ProviderConnections)
            .lyrics(track)
            .timeout(const Duration(seconds: 5));
        if (text != null) {
          final result = await compute(parseLyrics, text);
          await _save(directory, cache, text);
          return result;
        }
      } catch (_) {
        // Continue with downloaded audio or a previously cached document.
      }
    }
    if (!downloads.offlineOnly && downloads.remote is ProviderConnections) {
      final providers = downloads.remote as ProviderConnections;
      if (providers.preferences.getBool('visual.online_lyrics') ?? true) {
        final text = await OnlineLyrics(providers.client)
            .load(track, duration: durationFor?.call(track));
        if (text != null) {
          await _save(directory, cache, text);
          return await compute(parseLyrics, text);
        }
      }
    }
    return previous;
  }

  Future<void> _save(Directory directory, File cache, String text) async {
    try {
      await directory.create(recursive: true);
      final temp = File('${cache.path}.tmp');
      await temp.writeAsString(text, flush: true);
      if (await cache.exists()) await cache.delete();
      await temp.rename(cache.path);
      final files = await directory
          .list()
          .where(
            (e) =>
                e is File &&
                RegExp(r'^[a-f0-9]{64}\.txt$').hasMatch(path.basename(e.path)),
          )
          .cast<File>()
          .toList();
      if (files.length > 100) {
        final dated = await Future.wait(
          files.map((f) async => (f, await f.lastModified())),
        );
        dated.sort((a, b) => a.$2.compareTo(b.$2));
        for (final (file, _) in dated.take(files.length - 100)) {
          if (file.path != cache.path) await file.delete();
        }
      }
    } on FileSystemException {
      // Display a successful response even when optional caching fails.
    }
  }
}
