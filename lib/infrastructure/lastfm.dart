import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/ports.dart';
import '../domain/track.dart';

class LastFmException implements Exception {
  const LastFmException(this.code);
  final int code;
  bool get requiresLogin => code == 9;
  bool get retryable => code == 11 || code == 16 || code == 29;
  @override
  String toString() => 'Last.fm: erro $code';
}

class LastFmIgnoredException implements Exception {
  const LastFmIgnoredException();
}

class LastFmTrack {
  const LastFmTrack(this.title, this.artist, this.album, this.playedAt);
  final String title, artist, album;
  final DateTime? playedAt;
}

class LastFmClient implements ScrobbleSink {
  LastFmClient(
    this.client, {
    required this.apiKey,
    required this.apiSecret,
    this.sessionKey,
  });
  final http.Client client;
  final String apiKey, apiSecret;
  String? sessionKey;
  static final endpoint = Uri.parse('https://ws.audioscrobbler.com/2.0/');

  Future<Map<String, dynamic>> readProfile(
    String method,
    Map<String, String> fields,
  ) async {
    const methods = {
      'artist.getSimilar',
      'artist.getTopTracks',
      'album.getInfo',
      'user.getTopTracks',
      'user.getRecentTracks',
    };
    if (!methods.contains(method)) throw ArgumentError('Método não permitido');
    if (apiKey.trim().isEmpty) throw StateError('Configure a chave Last.fm');
    final response = await client
        .get(
          endpoint.replace(
            queryParameters: {
              'method': method,
              'api_key': apiKey,
              'format': 'json',
              ...fields,
            },
          ),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 429) throw const LastFmException(29);
    if (response.statusCode >= 500) throw const LastFmException(16);
    if (response.statusCode != 200) throw StateError('Last.fm indisponível');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['error'] != null) {
      throw LastFmException(int.parse('${body['error']}'));
    }
    return body;
  }

  Future<List<LastFmTrack>> topTracks(String user, String period) async {
    if (!{
          'overall',
          '1month',
          '7day',
          '3month',
          '6month',
          '12month',
        }.contains(period) ||
        user.trim().isEmpty) {
      throw ArgumentError('Confira o usuário e período Last.fm');
    }
    final body = await readProfile('user.getTopTracks', {
      'user': user.trim(),
      'period': period,
      'limit': '200',
    });
    final rows = body['toptracks']?['track'];
    return [
      for (final row in rows is List ? rows : [])
        if (row is Map)
          LastFmTrack(
            '${row['name'] ?? ''}',
            '${row['artist']?['name'] ?? ''}',
            '',
            null,
          ),
    ];
  }

  /// Public, read-only profile methods do not require a session or API secret.
  Future<List<LastFmTrack>> profileTracks(
    String user, {
    required bool loved,
  }) async {
    if (apiKey.trim().isEmpty || user.trim().isEmpty) {
      throw StateError('Informe a chave da API e o usuário Last.fm');
    }
    final tracks = <LastFmTrack>[];
    for (var page = 1; page <= 100; page++) {
      final response = await client
          .get(
            endpoint.replace(
              queryParameters: {
                'method': loved
                    ? 'user.getLovedTracks'
                    : 'user.getRecentTracks',
                'user': user.trim(),
                'api_key': apiKey,
                'format': 'json',
                'limit': '200',
                'page': '$page',
              },
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError('Last.fm HTTP ${response.statusCode}');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['error'] != null) {
        throw LastFmException(int.parse('${body['error']}'));
      }
      final result =
          body[loved ? 'lovedtracks' : 'recenttracks'] as Map<String, dynamic>;
      final raw = result['track'];
      final rows = raw is List
          ? raw
          : raw is Map
          ? [raw]
          : [];
      String name(Object? value) => value is Map
          ? '${value['name'] ?? value['#text'] ?? ''}'
          : '${value ?? ''}';
      for (final row in rows) {
        if (row is! Map ||
            (row['@attr'] is Map && row['@attr']['nowplaying'] == 'true')) {
          continue;
        }
        final timestamp = row['date'] is Map
            ? int.tryParse('${row['date']['uts']}')
            : null;
        tracks.add(
          LastFmTrack(
            '${row['name'] ?? ''}',
            name(row['artist']),
            name(row['album']),
            timestamp == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    timestamp * 1000,
                    isUtc: true,
                  ),
          ),
        );
      }
      final pages = result['@attr'] is Map
          ? int.tryParse('${result['@attr']['totalPages']}') ?? 1
          : 1;
      if (!loved || page >= pages) return tracks;
      if (page == 100) {
        throw StateError(
          'Favoritos excedem 20 mil itens; importação não concluída',
        );
      }
    }
    return tracks;
  }

  static String signature(Map<String, String> params, String secret) {
    final keys =
        params.keys
            .where((k) => k != 'format' && k != 'callback' && k != 'api_sig')
            .toList()
          ..sort();
    final body = keys.map((k) => '$k${params[k]}').join();
    return md5.convert(utf8.encode('$body$secret')).toString();
  }

  Future<Map<String, dynamic>> _call(
    String method,
    Map<String, String> fields,
  ) async {
    if (apiKey.isEmpty || apiSecret.isEmpty) {
      throw StateError('Configure suas credenciais Last.fm');
    }
    final params = {'method': method, 'api_key': apiKey, ...fields};
    params['api_sig'] = signature(params, apiSecret);
    params['format'] = 'json';
    final response = await client
        .post(endpoint, body: params)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('Last.fm HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw LastFmException(int.parse('${json['error']}'));
    }
    return json;
  }

  Future<String> requestToken() async =>
      (await _call('auth.getToken', {}))['token'] as String;

  Uri authorizationUrl(String token) => Uri.https('www.last.fm', '/api/auth/', {
    'api_key': apiKey,
    'token': token,
  });

  /// Após o usuário autorizar no navegador. Persistir key no cofre do SO.
  Future<String> exchangeToken(String token) async {
    final result = await _call('auth.getSession', {'token': token});
    sessionKey = (result['session'] as Map<String, dynamic>)['key'] as String;
    return sessionKey!;
  }

  Map<String, String> _trackFields(Track track) {
    if (!track.hasScrobbleMetadata) {
      throw ArgumentError('Artista e título são obrigatórios');
    }
    if (sessionKey == null || sessionKey!.isEmpty) {
      throw StateError('Last.fm desconectado');
    }
    return {
      'sk': sessionKey!,
      'artist': track.artist,
      'track': track.title,
      if (track.album.isNotEmpty) 'album': track.album,
    };
  }

  @override
  Future<void> nowPlaying(Track track) async {
    await _call('track.updateNowPlaying', _trackFields(track));
  }

  @override
  Future<void> submit(
    Track track,
    DateTime startedAt,
    Duration duration,
  ) async {
    final result = await _call('track.scrobble', {
      ..._trackFields(track),
      'timestamp': '${startedAt.toUtc().millisecondsSinceEpoch ~/ 1000}',
      'duration': '${duration.inSeconds}',
    });
    final summary = result['scrobbles'] as Map<String, dynamic>?;
    final attributes = summary?['@attr'] as Map<String, dynamic>?;
    if (attributes == null || int.tryParse('${attributes['accepted']}') != 1) {
      // Ignorado não é sucesso. Worker futuro deve registrar motivo,
      // remover erros permanentes da outbox e não repetir indefinidamente.
      throw const LastFmIgnoredException();
    }
  }
}
