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

class LibraryLyrics {
  LibraryLyrics(this.downloads, {this.durationFor});
  final Duration Function(Track)? durationFor;
  final DownloadManager downloads;
  final pending = <String, Future<LyricsDocument?>>{};
  Future<LyricsDocument?> load(Track track, bool refresh) async {
    final key = '${track.id}|${track.revision}';
    final job = pending[key];
    if (job != null) return job;
    final work = _load(track, refresh, key);
    pending[key] = work;
    try {
      return await work;
    } finally {
      if (identical(pending[key], work)) pending.remove(key);
    }
  }

  Future<LyricsDocument?> _load(Track track, bool refresh, String key) async {
    if (track.localPath != null) {
      final local = await loadLocalLyrics(track);
      if (local != null) return local;
    }
    final directory = Directory(
      path.join((await getApplicationSupportDirectory()).path, 'lyrics-cache'),
    );
    final cache = File(
      path.join(directory.path, '${sha256.convert(utf8.encode(key))}.txt'),
    );
    LyricsDocument? previous;
    try {
      if (await cache.exists()) {
        if (await cache.length() <= 2 * 1024 * 1024) {
          previous = await compute(parseLyrics, await cache.readAsString());
          if (downloads.offlineOnly ||
              (!refresh &&
                  DateTime.now()
                          .difference(await cache.lastModified())
                          .inHours <
                      24)) {
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
            .timeout(const Duration(seconds: 15));
        if (text != null) {
          final result = await compute(parseLyrics, text);
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
                      RegExp(r'^[a-f0-9]{64}\.txt$')
                          .hasMatch(path.basename(e.path)),
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
          return result;
        }
      } catch (_) {
        // Continue with downloaded audio or a previously cached document.
      }
    }
    // Explicit downloads and automatic audio cache can supply embedded tags.
    final cached = await downloads.cache?.valid(track);
    if (cached != null) {
      final text = await compute(readEmbeddedLyrics, cached.path);
      if (text != null) return compute(parseLyrics, text);
    }
    final row = await downloads.store.offlineFile(track.id);
    if (row != null && row['path'] is String) {
      final text = await compute(readEmbeddedLyrics, row['path'] as String);
      if (text != null) return compute(parseLyrics, text);
    }
    if (previous != null) return previous;
    if (!downloads.offlineOnly && downloads.remote is ProviderConnections) {
      final providers = downloads.remote as ProviderConnections;
      if (providers.preferences.getBool('visual.online_lyrics') ?? true) {
        final text = await OnlineLyrics(providers.client)
            .load(track, duration: durationFor?.call(track));
        if (text != null) {
          try {
            await directory.create(recursive: true);
            await cache.writeAsString(text, flush: true);
          } on FileSystemException {
            /* Lyrics remain usable without caching. */
          }
          return compute(parseLyrics, text);
        }
      }
    }
    return null;
  }
}
