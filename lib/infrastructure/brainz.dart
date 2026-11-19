import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/track.dart';

class BrainzFailure implements Exception {
  const BrainzFailure(this.code);
  final int code;
  @override
  String toString() => 'Serviço indisponível (HTTP $code).';
}

/// A single lane per service, including cooldowns from server rate limits.
class BrainzTransport {
  BrainzTransport(this.client, this.host, {this.allowed});
  final http.Client client;
  final String host;
  final bool Function()? allowed;
  Future<void> _tail = Future.value();
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);
  Future<Map<String, dynamic>> request(
    String path, {
    String? token,
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool Function()? guard,
  }) {
    final job = _tail.then((_) async {
      final wait = _next.difference(DateTime.now());
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (allowed != null && !allowed!() || guard != null && !guard()) {
        throw const BrainzFailure(0);
      }
      final headers = <String, String>{
        'User-Agent':
            'MusicTime/3.0 (https://github.com/eugilvando/Music-Time-Player)',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Token $token',
        if (body != null) 'Content-Type': 'application/json',
      };
      final uri = Uri.https(host, path, query);
      try {
        final response =
            await (body == null
                    ? client.get(uri, headers: headers)
                    : client.post(
                        uri,
                        headers: headers,
                        body: jsonEncode(body),
                      ))
                .timeout(const Duration(seconds: 12));
        final seconds =
            int.tryParse(
              response.headers['x-ratelimit-reset-in'] ??
                  response.headers['retry-after'] ??
                  '',
            ) ??
            60;
        _next = DateTime.now().add(
          Duration(
            seconds:
                response.statusCode == 429 ||
                    response.headers['x-ratelimit-remaining'] == '0'
                ? seconds.clamp(1, 3600)
                : 1,
          ),
        );
        if (response.statusCode != 200) {
          throw BrainzFailure(response.statusCode);
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      } finally {
        if (_next.isBefore(DateTime.now())) {
          _next = DateTime.now().add(const Duration(seconds: 1));
        }
      }
    });
    _tail = job.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return job;
  }
}

class ListenBrainzClient {
  ListenBrainzClient(this.transport, this.token);
  final BrainzTransport transport;
  final String token;
  Future<String> validate() async {
    final result = await transport.request('/1/validate-token', token: token);
    if (result['valid'] != true ||
        result['user_name'] is! String ||
        (result['user_name'] as String).isEmpty) {
      throw const BrainzFailure(401);
    }
    return result['user_name'] as String;
  }

  static Map<String, dynamic> payload(
    Track track,
    DateTime? started,
    Duration duration,
  ) => {
    if (started != null)
      'listened_at': started.toUtc().millisecondsSinceEpoch ~/ 1000,
    'track_metadata': {
      'artist_name': track.artist,
      'track_name': track.title,
      if (track.album.isNotEmpty) 'release_name': track.album,
      'additional_info': {
        'submission_client': 'Music Time',
        'media_player': 'Music Time',
        if (duration > Duration.zero) 'duration_ms': duration.inMilliseconds,
      },
    },
  };
  Future<void> send(
    Map<String, dynamic> payload, {
    bool nowPlaying = false,
    bool Function()? guard,
  }) async {
    await transport.request(
      '/1/submit-listens',
      token: token,
      guard: guard,
      body: {
        'listen_type': nowPlaying ? 'playing_now' : 'single',
        'payload': [payload],
      },
    );
  }
}
