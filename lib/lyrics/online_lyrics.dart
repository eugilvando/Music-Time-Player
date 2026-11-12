import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/track.dart';
import '../library/catalog.dart';
import 'lyrics.dart';

class OnlineLyrics {
  OnlineLyrics(this.client, {this.timeout = const Duration(seconds: 5)});
  final http.Client client;
  final Duration timeout;

  Future<Map<String, dynamic>?> _get(Uri uri) async {
    final abort = Completer<void>();
    try {
      return await (() async {
        final request =
            http.AbortableRequest('GET', uri, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers['User-Agent'] = 'MusicTime (desktop music player)';
        final response = await client.send(request);
        if (response.statusCode != 200) {
          final subscription = response.stream.listen((_) {});
          await subscription.cancel();
          return null;
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          bytes.addAll(chunk);
          if (bytes.length > 2 * 1024 * 1024) return null;
        }
        final data = jsonDecode(utf8.decode(bytes));
        return data is Map<String, dynamic> ? data : null;
      })().timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  String? _usable(dynamic value, String source, {bool plain = false}) {
    if (value is! String || value.trim().isEmpty) return null;
    // Plain providers use [Chorus] headings, which are not broken LRC tags.
    final body = plain
        ? value.replaceAllMapped(
            RegExp(r'^\[([^\]\d:]+)\]\s*$', multiLine: true),
            (m) => m[1]!,
          )
        : value;
    final text = '[by:$source]\n$body';
    try {
      parseLyrics(text);
      return text;
    } catch (_) {
      return null;
    }
  }

  Future<String?> load(Track track, {Duration? duration}) async {
    if (!track.hasScrobbleMetadata) return null;
    final length = track.duration > Duration.zero
        ? track.duration
        : duration ?? Duration.zero;
    if (length > Duration.zero) {
      final data = await _get(
        Uri.https('lrclib.net', '/api/get', {
          'track_name': track.title,
          'artist_name': track.artist,
          if (track.album.isNotEmpty) 'album_name': track.album,
          'duration': '${length.inMilliseconds / 1000}',
        }),
      );
      if (data != null &&
          searchKey('${data['trackName']}') == searchKey(track.title) &&
          searchKey('${data['artistName']}') == searchKey(track.artist) &&
          data['duration'] is num &&
          ((data['duration'] as num) - length.inMilliseconds / 1000).abs() <=
              2) {
        if (data['instrumental'] == true) return null;
        final synced = _usable(data['syncedLyrics'], 'LRCLIB');
        if (synced != null) return synced;
        final plain = _usable(data['plainLyrics'], 'LRCLIB', plain: true);
        if (plain != null) return plain;
      }
    }
    // This service supplies plain lyrics only; never invent synchronization.
    final data = await _get(
      Uri(
        scheme: 'https',
        host: 'api.lyrics.ovh',
        pathSegments: ['v1', track.artist, track.title],
      ),
    );
    return _usable(data?['lyrics'], 'lyrics.ovh', plain: true);
  }
}
