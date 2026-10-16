import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/ports.dart';
import '../domain/track.dart';
import '../persistence/library_store.dart';
import 'media_cache.dart';
import '../library/file_availability.dart';

class DownloadManager extends ChangeNotifier
    implements MediaSourceResolver, AuthenticatedMediaResolver {
  @override
  Future<Map<String, String>> mediaHeaders(Track track, Uri uri) =>
      uri.scheme == 'file' ? Future.value({}) : getMediaHeaders(track, uri);
  Future<Map<String, String>> getMediaHeaders(Track track, Uri uri) =>
      remote is AuthenticatedMediaResolver
      ? (remote as AuthenticatedMediaResolver).mediaHeaders(track, uri)
      : Future.value({});
  @override
  bool allowsInsecureMedia(Uri uri) => allowedMediaUri(remote, uri);
  DownloadManager(
    this.store,
    this.remote, {
    http.Client? client,
    this.directory,
    this.cache,
  }) : client = client ?? http.Client();
  final LibraryStore store;
  final MediaSourceResolver remote;
  final http.Client client;
  final Future<Directory> Function()? directory;
  final MediaCache? cache;
  bool offlineOnly = false;
  Future<Directory> dataDirectory() async {
    if (directory != null) return directory!();
    final support = await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'offline'));
  }

  bool running = false, _disposed = false;
  bool suspended = false;
  bool maintaining = false;
  bool _processRequested = false;
  final cancelled = <String>{};
  String? current;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> select(String selection, List<Track> tracks) async {
    await store.selectOffline(selection, tracks);
    await process();
  }

  Future<void> pause(String id) async {
    cancelled.add(id);
    await store.updateDownload(id, 'paused');
    _notify();
  }

  Future<void> retry(String id) async {
    cancelled.remove(id);
    await store.updateDownload(id, 'pending');
    await process();
  }

  Future<void> unselect(String selection) async {
    final ids = await store.removeOfflineSelection(selection);
    final tasks = await store.downloadTasks(includeCovers: false);
    final directory = (await dataDirectory()).path;
    for (final id in ids) {
      cancelled.add(id);
      final task = tasks.where((row) => row['id'] == id).firstOrNull;
      final downloaded = task?['download_path'] as String?;
      final expected = path.join(
        directory,
        '${sha256.convert(utf8.encode(id))}.audio',
      );
      if (downloaded != null &&
          path.equals(path.normalize(downloaded), path.normalize(expected))) {
        final file = File(downloaded);
        if (await file.exists()) await file.delete();
      }
      await store.updateDownload(id, 'removed');
    }
    _notify();
  }

  Future<void> removePermanentTrack(String id) async {
    if (current == id || cache?.pinned == id || maintaining) {
      throw StateError('Faixa em uso');
    }
    final rows = await store.downloadTasks(includeCovers: false);
    final row = rows.where((r) => r['id'] == id).firstOrNull;
    if (row == null || row['status'] != 'complete') return;
    final source = row['path'] as String?;
    final downloaded = row['download_path'] as String?;
    if (source != null &&
        downloaded != null &&
        path.equals(
          path.normalize(path.absolute(source)),
          path.normalize(path.absolute(downloaded)),
        )) {
      await store.removeOfflineTrackReferences(id);
      await store.updateDownload(id, 'removed');
      _notify();
      return;
    }
    final root = path.normalize(path.absolute((await dataDirectory()).path));
    if (await FileSystemEntity.type(root, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Diretório gerenciado inválido');
    }
    final expected = path.join(
      root,
      '${sha256.convert(utf8.encode(id))}.audio',
    );
    final actual = row['download_path'] as String?;
    if (actual == null ||
        !path.equals(path.normalize(path.absolute(actual)), expected)) {
      throw StateError('Arquivo fora do diretório gerenciado');
    }
    // Never follow a substituted link or delete a source file.
    final type = await FileSystemEntity.type(expected, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw StateError('Arquivo gerenciado inválido');
    }
    final original = row['path'] as String?;
    if (original != null &&
        path.equals(path.normalize(path.absolute(original)), expected)) {
      throw StateError('Arquivo original preservado');
    }
    final originals = await store.database.rawQuery(
      "SELECT id FROM tracks WHERE lower(replace(path, char(92), '/'))=? LIMIT 1",
      [expected.replaceAll('\\', '/').toLowerCase()],
    );
    if (originals.isNotEmpty || current == id || cache?.pinned == id) {
      throw StateError('Arquivo original ou em uso preservado');
    }
    if (type == FileSystemEntityType.file) await File(expected).delete();
    await store.removeOfflineTrackReferences(id);
    await store.updateDownload(id, 'removed');
    _notify();
  }

  Future<void> process() async {
    if (_disposed || suspended || offlineOnly) return;
    if (running || maintaining) {
      _processRequested = true;
      return;
    }
    running = true;
    _notify();
    try {
      do {
        _processRequested = false;
        for (final row in await store.downloadTasks(includeCovers: false)) {
          if (_disposed || suspended || offlineOnly) break;
          if (row['status'] != 'pending') continue;
          final track = store.trackFromRow(row);
          final latest = await store.database.query(
            'downloads',
            columns: ['status'],
            where: 'track_id=?',
            whereArgs: [track.id],
          );
          if (latest.isEmpty || latest.single['status'] != 'pending') continue;
          cancelled.remove(track.id);
          current = track.id;
          await _download(track);
          _notify();
        }
      } while (_processRequested && !_disposed && !suspended);
    } finally {
      running = false;
      current = null;
      _notify();
    }
  }

  Future<void> clearIncomplete() async {
    if (running || maintaining) {
      throw StateError('Aguarde os downloads terminarem');
    }
    maintaining = true;
    try {
      final root = await dataDirectory();
      if (await FileSystemEntity.type(root.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return;
      }
      await for (final file in root.list(followLinks: false)) {
        if (file is File &&
            RegExp(r'^[a-f0-9]{64}\.audio\.part$')
                .hasMatch(path.basename(file.path))) {
          await file.delete();
        }
      }
    } finally {
      maintaining = false;
      if (_processRequested && !_disposed) unawaited(process());
    }
  }

  Future<void> _download(Track track) async {
    File? temporary;
    IOSink? sink;
    try {
      if (track.localPath != null) {
        if (!await File(track.localPath!).exists()) {
          throw StateError('Arquivo ausente');
        }
        if (_disposed ||
            suspended ||
            offlineOnly ||
            cancelled.contains(track.id)) {
          throw const _Paused();
        }
        await store.updateDownload(track.id, 'complete', path: track.localPath);
        return;
      }
      final directory = await dataDirectory();
      await directory.create(recursive: true);
      final key = sha256.convert(utf8.encode(track.id)).toString();
      final completed = File(path.join(directory.path, '$key.audio'));
      temporary = File('${completed.path}.part');
      final uri = await remote.resolve(track);
      if (_disposed ||
          suspended ||
          offlineOnly ||
          cancelled.contains(track.id)) {
        throw const _Paused();
      }
      if (uri.scheme != 'file' && !allowedMediaUri(remote, uri)) {
        throw StateError('Fonte remota deve usar HTTPS');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll(await getMediaHeaders(track, uri));
      request.followRedirects = request.headers.isEmpty;
      final response = uri.scheme == 'file'
          ? http.StreamedResponse(
              File.fromUri(uri).openRead(),
              200,
              contentLength: await File.fromUri(uri).length(),
            )
          : await client.send(request).timeout(const Duration(seconds: 30));
      if (_disposed ||
          suspended ||
          offlineOnly ||
          cancelled.contains(track.id)) {
        await response.stream.listen(null).cancel();
        throw const _Paused();
      }
      if (response.statusCode != 200) throw StateError('Download indisponível');
      final total = response.contentLength;
      var received = 0, checkpoint = 0;
      sink = temporary.openWrite();
      await store.updateDownload(track.id, 'downloading', total: total);
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (_disposed ||
            suspended ||
            offlineOnly ||
            cancelled.contains(track.id)) {
          throw const _Paused();
        }
        sink.add(bytes);
        received += bytes.length;
        if (received - checkpoint >= 262144) {
          checkpoint = received;
          await store.updateDownload(
            track.id,
            'downloading',
            received: received,
            total: total,
          );
          _notify();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (_disposed ||
          suspended ||
          offlineOnly ||
          cancelled.contains(track.id)) {
        throw const _Paused();
      }
      if (received == 0 || (total != null && received != total)) {
        throw StateError('Arquivo incompleto');
      }
      await temporary.rename(completed.path);
      temporary = null;
      if (_disposed ||
          suspended ||
          offlineOnly ||
          cancelled.contains(track.id)) {
        if (await completed.exists()) await completed.delete();
        throw const _Paused();
      }
      final promoted = await store.database.update(
        'downloads',
        {
          'status': 'complete',
          'path': completed.path,
          'received': received,
          'total': total,
          'error': null,
        },
        where: 'track_id=? AND status=?',
        whereArgs: [track.id, 'downloading'],
      );
      if (promoted == 0 && await completed.exists()) await completed.delete();
    } on _Paused {
      // Removal or a new selection may already have replaced this task.
      await store.database.update(
        'downloads',
        {'status': 'paused'},
        where: 'track_id=? AND status=?',
        whereArgs: [track.id, 'downloading'],
      );
    } catch (_) {
      if (cancelled.contains(track.id)) return;
      await store.updateDownload(
        track.id,
        'failed',
        error: 'Download não concluído. Confira rede e espaço disponível.',
      );
    } finally {
      await sink?.close();
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  Future<Uri> resolve(Track track) async {
    final file = await store.offlineFile(track.id);
    final value = file?['path'] as String?;
    if (value != null &&
        await File(value).exists() &&
        (!offlineOnly || fileHasLocalData(File(value)))) {
      return Uri.file(value);
    }
    if (track.localPath != null &&
        await File(track.localPath!).exists() &&
        (!offlineOnly || fileHasLocalData(File(track.localPath!)))) {
      return Uri.file(track.localPath!);
    }
    final cached = await cache?.valid(track);
    if (cached != null) {
      cache!.pinned = track.id;
      return Uri.file(cached.path);
    }
    if (offlineOnly) {
      throw const MediaSourceFailure(
        'Esta faixa não está disponível offline. Desative o modo offline para acessar a nuvem.',
      );
    }
    final result = await remote.resolve(track);
    if (offlineOnly) {
      throw const MediaSourceFailure(
        'O modo offline está ativo. Escolha uma faixa disponível neste dispositivo.',
      );
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    if (current != null) cancelled.add(current!);
    client.close();
    super.dispose();
  }
}

class _Paused implements Exception {
  const _Paused();
}
