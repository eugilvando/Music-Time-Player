import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/track.dart';
import '../domain/ports.dart';
import '../persistence/library_store.dart';

/// Complete automatic files only. Never shares paths with original music/offline selections.
class MediaCache extends ChangeNotifier {
  MediaCache(
    this.store,
    this.remote, {
    http.Client? client,
    this.directory,
    DateTime Function()? now,
  }) : client = client ?? http.Client(),
       now = now ?? DateTime.now;
  final LibraryStore store;
  final MediaSourceResolver remote;
  final http.Client client;
  final Future<Directory> Function()? directory;
  final DateTime Function() now;
  bool enabled = true, offlineOnly = false, _disposed = false;
  int maxBytes = 10 * 1000 * 1000 * 1000, prefetchCount = 5, _epoch = 0;
  String? pinned, current;
  final pending = <String>{};
  Future<void> _tail = Future.value();
  Future<void> get idle => _tail;
  Completer<void>? _abort;
  StreamIterator<List<int>>? _reader;
  bool _clearing = false;
  void suspendForExit() {
    enabled = false;
    _epoch++;
    _cancelActive();
  }

  void _cancelActive() {
    if (_abort?.isCompleted == false) _abort!.complete();
    unawaited(_reader?.cancel() ?? Future<void>.value());
  }

  Future<Directory> root() async => directory != null
      ? directory!()
      : Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'media-cache',
          ),
        );
  String key(String id) => sha256.convert(utf8.encode(id)).toString();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> _owned(String value, String id) async {
    final expected = path.join((await root()).path, '${key(id)}.audio');
    return path.equals(path.normalize(value), path.normalize(expected)) &&
        await FileSystemEntity.type(path.dirname(value), followLinks: false) ==
            FileSystemEntityType.directory &&
        await FileSystemEntity.type(value, followLinks: false) ==
            FileSystemEntityType.file;
  }

  Future<List<Map<String, Object?>>> rows({
    bool validOnly = false,
  }) => store.database.rawQuery(
    "SELECT c.*,COALESCE(json_extract(t.metadata,'\$.userOverride.title'),t.title) AS title,COALESCE(json_extract(t.metadata,'\$.userOverride.artist'),t.artist) AS artist FROM media_cache c JOIN tracks t ON t.id=c.track_id ${validOnly ? "WHERE c.revision=COALESCE(json_extract(t.metadata,'\$.revision'),'')" : ''} ORDER BY COALESCE(c.last_played,c.cached_at) DESC",
  );
  Future<void> remove(String id) async {
    if (id == pinned) throw StateError('Faixa em reprodução');
    _epoch++;
    _cancelActive();
    await _tail;
    final records = await store.database.query(
      'media_cache',
      where: 'track_id=?',
      whereArgs: [id],
    );
    if (records.isEmpty) return;
    final value = records.single['path'] as String;
    final originals = await store.database.query(
      'tracks',
      columns: ['path'],
      where: r"json_extract(metadata,'$.driveId') IS NULL",
    );
    if (originals.any(
      (r) => path.equals(
        path.normalize(r['path'] as String),
        path.normalize(value),
      ),
    )) {
      throw StateError('Arquivo original protegido');
    }
    if (id == pinned) throw StateError('Faixa em reprodução');
    if (await _owned(value, id)) await File(value).delete();
    await store.database.delete(
      'media_cache',
      where: 'track_id=?',
      whereArgs: [id],
    );
    _notify();
  }

  Future<File?> valid(Track track) async {
    final rows = await store.database.query(
      'media_cache',
      where: 'track_id=?',
      whereArgs: [track.id],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final file = File(row['path'] as String);
    try {
      if (row['revision'] != track.revision ||
          !await _owned(file.path, track.id) ||
          await file.length() != row['bytes'] ||
          (row['bytes'] as int) <= 0) {
        return null;
      }
      return file;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> markPlayed(Track track) async {
    pinned = track.id;
    if (await valid(track) != null) {
      await store.database.update(
        'media_cache',
        {'last_played': now().toUtc().toIso8601String()},
        where: 'track_id=?',
        whereArgs: [track.id],
      );
      _notify();
    } else {
      request(track);
    }
  }

  void configure({
    required bool enabled,
    required bool offlineOnly,
    required int maxBytes,
    required int prefetchCount,
  }) {
    if (this.enabled != enabled ||
        this.offlineOnly != offlineOnly ||
        this.prefetchCount != prefetchCount) {
      _epoch++;
      _cancelActive();
    }
    this.enabled = enabled;
    this.offlineOnly = offlineOnly;
    this.maxBytes = maxBytes.clamp(1024 * 1024, 100 * 1000 * 1000 * 1000);
    this.prefetchCount = prefetchCount.clamp(0, 20);
  }

  void request(Track track) {
    if (_disposed ||
        _clearing ||
        !enabled ||
        offlineOnly ||
        track.localPath != null ||
        !track.available ||
        !pending.add(track.id)) {
      return;
    }
    final epoch = _epoch;
    _tail = _tail
        .then((_) async {
          if (_disposed || epoch != _epoch || !enabled || offlineOnly) return;
          if (await valid(track) != null) return;
          final permanent = await store.offlineFile(track.id);
          if (permanent?['path'] is String &&
              await File(permanent!['path'] as String).exists()) {
            return;
          }
          current = track.id;
          _notify();
          await _fetch(track, epoch);
        })
        .catchError((Object _) {})
        .whenComplete(() {
          pending.remove(track.id);
          current = null;
          _notify();
        });
  }

  Future<void> _fetch(Track track, int epoch) async {
    File? part;
    File? promoted;
    IOSink? sink;
    StreamIterator<List<int>>? reader;
    final abort = Completer<void>();
    _abort = abort;
    try {
      final directory = await root();
      await directory.create(recursive: true);
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return;
      }
      final completed = File(
        path.join(directory.path, '${key(track.id)}.audio'),
      );
      part = File('${completed.path}.part');
      final uri = await Future.any<Uri>([
        remote.resolve(track),
        abort.future.then((_) => throw StateError('Cancelled')),
      ]);
      if ((uri.scheme != 'file' && !allowedMediaUri(remote, uri)) ||
          epoch != _epoch ||
          _disposed) {
        return;
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll(await mediaHeaders(remote, track, uri));
      request.followRedirects = request.headers.isEmpty;
      final responseFuture = uri.scheme == 'file'
          ? File.fromUri(uri).length().then(
              (length) => http.StreamedResponse(
                File.fromUri(uri).openRead(),
                200,
                contentLength: length,
              ),
            )
          : client.send(request).timeout(const Duration(seconds: 20));
      unawaited(
        responseFuture
            .then((response) async {
              if (epoch != _epoch || _disposed) {
                await response.stream.listen(null).cancel();
              }
            })
            .catchError((Object _) {}),
      );
      final response = await Future.any<http.StreamedResponse>([
        responseFuture,
        abort.future.then((_) => throw StateError('Cancelled')),
      ]);
      final mime = response.headers['content-type'] ?? '';
      if (response.statusCode != 200 ||
          mime.startsWith('text/') ||
          mime.contains('json') ||
          mime.contains('xml') ||
          (response.contentLength ?? 0) > maxBytes ||
          epoch != _epoch ||
          _disposed) {
        await response.stream.listen(null).cancel();
        return;
      }
      var bytes = 0;
      sink = part.openWrite();
      reader = StreamIterator(
        response.stream.timeout(const Duration(seconds: 30)),
      );
      _reader = reader;
      while (await reader.moveNext()) {
        final chunk = reader.current;
        if (epoch != _epoch || _disposed || offlineOnly) {
          throw StateError('Cancelled');
        }
        bytes += chunk.length;
        if (bytes > maxBytes) throw StateError('Cache limit');
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (bytes == 0 ||
          (response.contentLength != null && bytes != response.contentLength) ||
          epoch != _epoch ||
          _disposed) {
        return;
      }
      await cleanup(reserve: bytes);
      final usage = await store.database.rawQuery(
        'SELECT COALESCE(SUM(bytes),0) AS bytes FROM media_cache',
      );
      if ((usage.single['bytes'] as int) + bytes > maxBytes ||
          epoch != _epoch ||
          _disposed) {
        return;
      }
      await part.rename(completed.path);
      part = null;
      promoted = completed;
      if (epoch != _epoch || _disposed) {
        await completed.delete();
        return;
      }
      await store.database.insert('media_cache', {
        'track_id': track.id,
        'revision': track.revision,
        'path': completed.path,
        'bytes': bytes,
        'last_played': pinned == track.id
            ? now().toUtc().toIso8601String()
            : null,
        'cached_at': now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      promoted = null;
    } catch (_) {
      /* Cache failure never prevents streaming or explicit downloads. */
    } finally {
      await reader?.cancel();
      if (identical(_reader, reader)) _reader = null;
      if (identical(_abort, abort)) _abort = null;
      await sink?.close();
      if (part != null && await part.exists()) await part.delete();
      if (promoted != null && await promoted.exists()) {
        try {
          await promoted.delete();
        } on FileSystemException {
          /* Kept for the next safe cleanup. */
        }
      }
    }
  }

  Future<void> cleanup({int reserve = 0, bool all = false}) async {
    final values = await rows();
    final originals = (await store.database.query(
      'tracks',
      columns: ['path'],
      where: r"json_extract(metadata,'$.driveId') IS NULL",
    )).map((r) => path.normalize(r['path'] as String)).toSet();
    var bytes = values.fold<int>(0, (sum, row) => sum + (row['bytes'] as int));
    final cutoff = now().toUtc().subtract(const Duration(days: 30));
    for (final row in values.reversed) {
      final id = row['track_id'] as String;
      final expired =
          (DateTime.tryParse(
            row['last_played'] as String? ?? row['cached_at'] as String,
          )?.isBefore(cutoff) ??
          true);
      if (id == pinned || (!all && !expired && bytes + reserve <= maxBytes)) {
        continue;
      }
      final value = row['path'] as String;
      if (originals.contains(path.normalize(value))) continue;
      if (await _owned(value, id)) {
        if (id == pinned) continue;
        try {
          await File(value).delete();
        } on FileSystemException {
          continue;
        }
      }
      await store.database.delete(
        'media_cache',
        where: 'track_id=?',
        whereArgs: [id],
      );
      bytes -= row['bytes'] as int;
    }
    final directory = await root();
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      final keep =
          (await rows()).map((r) => path.normalize(r['path'] as String)).toSet()
            ..addAll(originals);
      final protected = {
        for (final id in pending) key(id),
        if (pinned != null) key(pinned!),
      };
      await for (final file in directory.list(followLinks: false)) {
        final name = path.basename(file.path);
        if (file is! File ||
            !RegExp(r'^[a-f0-9]{64}\.audio(\.part)?$').hasMatch(name) ||
            keep.contains(path.normalize(file.path)) ||
            protected.contains(name.substring(0, 64))) {
          continue;
        }
        try {
          await file.delete();
        } on FileSystemException {
          /* In-use files are retried later. */
        }
      }
    }
    _notify();
  }

  Future<void> clear() async {
    _clearing = true;
    _epoch++;
    _cancelActive();
    try {
      await _tail;
      await cleanup(all: true);
    } finally {
      _clearing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _cancelActive();
    client.close();
    super.dispose();
  }
}
