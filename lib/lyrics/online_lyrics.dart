import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/track.dart';
import '../library/catalog.dart';

/// Exact recording lookup. Never replaces local lyrics or searches by title alone.
class OnlineLyrics {
  OnlineLyrics(this.client);
  final http.Client client;
  Future<String?> load(Track track, {Duration? duration}) async {
    final length = track.duration > Duration.zero
        ? track.duration
        : duration ?? Duration.zero;
    if (!track.hasScrobbleMetadata || length <= Duration.zero) {
      return null;
    }
    final uri = Uri.https('lrclib.net', '/api/get', {
      'track_name': track.title,
      'artist_name': track.artist,
      if (track.album.isNotEmpty) 'album_name': track.album,
      'duration': '${length.inMilliseconds / 1000}',
    });
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['User-Agent'] = 'MusicTime/0.7 (personal desktop music player)';
    try {
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) return null;
      }
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (searchKey('${data['trackName']}') != searchKey(track.title) ||
          searchKey('${data['artistName']}') != searchKey(track.artist) ||
          data['duration'] is! num ||
          ((data['duration'] as num) - length.inMilliseconds / 1000).abs() >
              2 ||
          data['instrumental'] == true) {
        return null;
      }
      for (final field in ['syncedLyrics', 'plainLyrics']) {
        final text = data[field];
        if (text is String && text.trim().isNotEmpty) {
          return '[by:LRCLIB]\n$text';
        }
      }
    } catch (_) {
      /* Optional fallback must not interrupt playback. */
    }
    return null;
  }
}
