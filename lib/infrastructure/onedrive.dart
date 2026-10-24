import '../domain/onedrive_identity.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../library/artwork.dart';
import '../library/cloud_metadata.dart';
import '../lyrics/lyrics.dart';

import 'package:path/path.dart' as path;

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show compute;

import '../domain/ports.dart';
import '../domain/track.dart';

class GraphException implements Exception {
  const GraphException(this.status, {this.operation = 'graph'});
  final String operation;
  final int status;
  @override
  String toString() => 'Graph HTTP $status';
}

class DrivePage {
  const DrivePage(this.items, this.nextLink, this.deltaLink);
  final List<Map<String, dynamic>> items;
  final Uri? nextLink, deltaLink;
}

/// Transporte Graph somente leitura. Cursor deve ser salvo apenas junto com
/// o commit das alterações no catálogo (incluindo tombstones deleted).
class OneDriveClient implements MediaSourceResolver {
  OneDriveClient(this.httpClient, this.tokens, {this.cancelled, this.wait});
  final bool Function()? cancelled;
  final Future<void> Function(Duration)? wait;
  final http.Client httpClient;
  final AccessTokenProvider tokens;
  static final root = Uri.parse(
    'https://graph.microsoft.com/v1.0/me/drive/root/delta',
  );

  static void validateGraphUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != 'graph.microsoft.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        !uri.path.startsWith('/v1.0/')) {
      throw ArgumentError('URL Graph inválida');
    }
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    validateGraphUri(uri);
    for (var attempt = 0; attempt < 5; attempt++) {
      if (cancelled?.call() == true) {
        throw StateError('Sincronização cancelada');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['Authorization'] = 'Bearer ${await tokens.accessToken()}';
      http.Response response;
      try {
        response = await httpClient
            .send(request)
            .then(http.Response.fromStream)
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        if (attempt == 4) rethrow;
        await pause(1 << attempt);
        continue;
      } on http.ClientException {
        if (attempt == 4) rethrow;
        await pause(1 << attempt);
        continue;
      } on SocketException {
        if (attempt == 4) rethrow;
        await pause(1 << attempt);
        continue;
      }
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode == 401 &&
          attempt == 0 &&
          tokens is RefreshableAccessTokenProvider) {
        await (tokens as RefreshableAccessTokenProvider)
            .invalidateAccessToken();
        continue;
      }
      if ((response.statusCode == 429 || response.statusCode >= 500) &&
          attempt < 4) {
        final delay =
            (int.tryParse(response.headers['retry-after'] ?? '') ??
            (1 << attempt));
        await pause(delay < 1 ? 1 : delay);
        continue;
      }
      throw GraphException(
        response.statusCode,
        operation: uri.path == '/v1.0/me/drive' ? 'drive' : 'items',
      );
    }
    throw const GraphException(503);
  }

  Future<void> pause(int seconds) async {
    if (wait != null) {
      await wait!(Duration(seconds: seconds));
      return;
    }
    for (var i = 0; i < seconds; i++) {
      if (cancelled?.call() == true) {
        throw StateError('Sincronização cancelada');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<Map<String, dynamic>> drive() async {
    final result = await _get(
      Uri.parse('https://graph.microsoft.com/v1.0/me/drive'),
    );
    if (result['id'] is String) {
      result['id'] = oneDriveIdentity(result['id'] as String);
    }
    return result;
  }

  Future<String?> lyrics(Track track) async {
    final drive = Uri.encodeComponent(track.driveId!);
    final item = await _get(
      Uri.parse(
        'https://graph.microsoft.com/v1.0/drives/$drive/items/${Uri.encodeComponent(track.itemId!)}',
      ),
    );
    final parent = (item['parentReference'] as Map?)?['id'];
    final name = item['name'] as String? ?? track.fileName;
    final reader = CloudMetadataReader(httpClient);
    if (parent is String && name.isNotEmpty) {
      for (final sidecar in [
        '${path.withoutExtension(name)}.lrc',
        '$name.lrc',
        '${path.withoutExtension(name)}.txt',
        '$name.txt',
      ]) {
        try {
          final data = await _get(
            Uri.parse(
              'https://graph.microsoft.com/v1.0/drives/$drive/items/${Uri.encodeComponent(parent)}:/${Uri.encodeComponent(sidecar)}',
            ),
          );
          if ((data['size'] as num? ?? 0) > 2 * 1024 * 1024) continue;
          final url = data['@microsoft.graph.downloadUrl'];
          if (url is! String) continue;
          final text = await reader.readLyricText(Uri.parse(url));
          await compute(parseLyrics, text);
          return text;
        } on GraphException catch (e) {
          if (!{404, 410}.contains(e.status)) rethrow;
        } on FormatException {
          /* A malformed sidecar must not hide embedded lyrics. */
        }
      }
    }
    if (name.toLowerCase().endsWith('.mp3')) {
      final url = item['@microsoft.graph.downloadUrl'];
      if (url is String) return reader.readEmbeddedLyrics(Uri.parse(url));
    }
    return null;
  }

  Future<Map<String, dynamic>> folderMetadata({
    String? itemId,
    String folderPath = '',
  }) {
    final relative = folderPath.isEmpty
        ? ''
        : folderPath.substring(folderPath.indexOf(':') + 1);
    final location = itemId != null
        ? 'items/${Uri.encodeComponent(itemId)}'
        : relative.isEmpty
        ? 'root'
        : 'root:${relative.split('/').map(Uri.encodeComponent).join('/')}:';
    return _get(
      Uri.parse('https://graph.microsoft.com/v1.0/me/drive/$location'),
    );
  }

  Future<List<Map<String, dynamic>>> folders({String? itemId}) async {
    Uri? next = Uri.parse(
      itemId == null
          ? 'https://graph.microsoft.com/v1.0/me/drive/root/children'
          : 'https://graph.microsoft.com/v1.0/me/drive/items/${Uri.encodeComponent(itemId)}/children',
    );
    final result = <Map<String, dynamic>>[];
    while (next != null) {
      final page = await _get(next);
      result.addAll(
        (page['value'] as List).cast<Map<String, dynamic>>().where(
          (row) => row['folder'] != null,
        ),
      );
      next = page['@odata.nextLink'] == null
          ? null
          : Uri.parse(page['@odata.nextLink'] as String);
    }
    return result;
  }

  Future<DrivePage> delta({Uri? cursor}) async {
    final json = await _get(cursor ?? root);
    return DrivePage(
      (json['value'] as List).cast<Map<String, dynamic>>(),
      json['@odata.nextLink'] == null
          ? null
          : Uri.parse(json['@odata.nextLink'] as String),
      json['@odata.deltaLink'] == null
          ? null
          : Uri.parse(json['@odata.deltaLink'] as String),
    );
  }

  Future<DrivePage> childrenPage({
    String? itemId,
    String folderPath = '',
    Uri? next,
  }) async {
    final relative = folderPath.isEmpty
        ? ''
        : folderPath.substring(folderPath.indexOf(':') + 1);
    final encoded = relative.split('/').map(Uri.encodeComponent).join('/');
    final location = itemId != null
        ? 'items/${Uri.encodeComponent(itemId)}'
        : relative.isEmpty
        ? 'root'
        : 'root:$encoded:';
    final json = await _get(
      next ??
          Uri.parse(
            'https://graph.microsoft.com/v1.0/me/drive/$location/children?\$expand=thumbnails&\$top=50',
          ),
    );
    return DrivePage(
      (json['value'] as List).cast<Map<String, dynamic>>(),
      json['@odata.nextLink'] == null
          ? null
          : Uri.parse(json['@odata.nextLink'] as String),
      null,
    );
  }

  Future<Uint8List?> thumbnail(Map<String, dynamic> item) async {
    try {
      for (final set in item['thumbnails'] as List? ?? const []) {
        final value = (set as Map)['large'] ?? set['medium'] ?? set['small'];
        if (value is! Map || value['url'] is! String) continue;
        final uri = Uri.parse(value['url'] as String);
        if (uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          continue;
        }
        // Signed image URL from Graph: never attach an OAuth bearer header or
        // persist the URL. Fetch only bounded image bytes, never music content.
        final request = http.Request('GET', uri)..followRedirects = false;
        final response = await httpClient
            .send(request)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200 ||
            !(response.headers['content-type'] ?? '').toLowerCase().startsWith(
              'image/',
            )) {
          await response.stream.listen((_) {}).cancel();
          continue;
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 15),
        )) {
          if (bytes.length + chunk.length > maxArtworkBytes) return null;
          bytes.add(chunk);
        }
        return validatedArtwork(bytes.takeBytes());
      }
    } catch (_) {
      /* Artwork failure does not discard the track/catalog. */
    }
    return null;
  }

  /// A cover file already enumerated in the selected folder, not arbitrary audio.
  Future<Uint8List?> folderArtwork(
    Map<String, dynamic> item,
    String driveId,
  ) async {
    final size = (item['size'] as num?)?.toInt();
    final name = item['name'] as String? ?? '';
    if (size == null ||
        size < 1 ||
        size > maxArtworkBytes ||
        !RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false).hasMatch(name)) {
      return null;
    }
    try {
      final uri = await resolve(
        Track(
          id: '',
          title: '',
          artist: '',
          driveId: driveId,
          itemId: item['id'] as String,
        ),
      );
      final response = await httpClient
          .send(http.Request('GET', uri)..followRedirects = false)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > maxArtworkBytes) {
        await response.stream.listen(null).cancel();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        if (bytes.length + chunk.length > maxArtworkBytes) return null;
        bytes.add(chunk);
      }
      if (bytes.length != size) return null;
      return validatedArtwork(bytes.takeBytes());
    } catch (_) {
      return null;
    }
  }

  /// Delta can omit parentReference.path; resolve folder metadata without
  /// requesting any file content. Cache is scoped to one synchronization.
  Future<String> folderPath(
    String id,
    Map<String, String> cache, [
    Set<String>? visiting,
  ]) async {
    if (cache.containsKey(id)) return cache[id]!;
    final active = visiting ?? <String>{};
    if (!active.add(id)) throw const FormatException('Hierarquia inválida');
    try {
      final item = await _get(
        Uri.parse(
          'https://graph.microsoft.com/v1.0/me/drive/items/${Uri.encodeComponent(id)}',
        ),
      );
      if (item['root'] != null) return cache[id] = '/drive/root:';
      final parent = item['parentReference'] as Map<String, dynamic>? ?? {};
      final prefix = parent['path'] is String
          ? Uri.decodeComponent(parent['path'] as String)
          : await folderPath(parent['id'] as String, cache, active);
      return cache[id] = '$prefix/${item['name'] as String}';
    } finally {
      active.remove(id);
    }
  }

  @override
  Future<Uri> resolve(Track track) async {
    if (track.localPath != null) return Uri.file(track.localPath!);
    if (track.driveId == null || track.itemId == null) {
      throw StateError('Faixa sem origem');
    }
    final drive = Uri.encodeComponent(track.driveId!);
    final item = Uri.encodeComponent(track.itemId!);
    final json = await _get(
      Uri.parse('https://graph.microsoft.com/v1.0/drives/$drive/items/$item'),
    );
    final url = json['@microsoft.graph.downloadUrl'];
    if (url is! String) throw StateError('OneDrive não retornou URL de áudio');
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty) {
      throw StateError('URL de áudio insegura');
    }
    // URL temporária: resolver a cada reprodução, não persistir.
    // O player recebe só esta URL, nunca o bearer token Graph.
    return uri;
  }
}
