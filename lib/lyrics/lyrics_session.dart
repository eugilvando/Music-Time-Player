import 'dart:async';

import '../domain/track.dart';
import 'lyrics.dart';

String lyricsIdentity(Track t) =>
    '${t.id}|${t.revision}|${t.localPath}|'
    '${t.title}|${t.artist}|${t.album}|${t.duration.inSeconds}';

/// Shared by the lyrics panels and the bounded look-ahead worker.
class LyricsSession {
  LyricsSession(this.loader, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final Future<LyricsDocument?> Function(Track, bool) loader;
  final DateTime Function() now;
  final _pending = <String, Future<LyricsDocument?>>{};
  final _cache = <String, (LyricsDocument?, DateTime)>{};
  List<(Track, String)> _wanted = [];
  bool _working = false, _disposed = false;
  String _signature = '';

  Future<LyricsDocument?> load(Track track, bool refresh, {String? key}) async {
    key ??= lyricsIdentity(track);
    if (_disposed) return null;
    final pending = _pending[key];
    if (pending != null) return pending;
    final cached = _cache[key];
    if (!refresh &&
        cached != null &&
        (cached.$1 != null ||
            now().difference(cached.$2) < const Duration(minutes: 2))) {
      return cached.$1;
    }
    final work = Future.sync(() => loader(track, refresh));
    _pending[key] = work;
    try {
      final result = await work;
      if (!_disposed) {
        _cache.remove(key);
        _cache[key] = (result, now());
        while (_cache.length > 100) {
          _cache.remove(_cache.keys.first);
        }
      }
      return result;
    } finally {
      _pending.remove(key);
    }
  }

  void prefetch(Iterable<Track> tracks, {String Function(Track)? keyFor}) {
    if (_disposed) return;
    final wanted = tracks
        .take(3)
        .map((t) => (t, (keyFor ?? lyricsIdentity)(t)))
        .toList();
    final signature = wanted.map((e) => e.$2).join('\n');
    if (signature == _signature) return;
    _signature = signature;
    _wanted = wanted;
    if (!_working) unawaited(_drain());
  }

  Future<void> _drain() async {
    _working = true;
    try {
      while (!_disposed && _wanted.isNotEmpty) {
        final (track, key) = _wanted.removeAt(0);
        try {
          await load(track, false, key: key);
        } catch (_) {
          // Speculative work must never affect playback.
        }
      }
    } finally {
      _working = false;
    }
  }

  void dispose() {
    _disposed = true;
    _wanted.clear();
    _cache.clear();
  }
}
