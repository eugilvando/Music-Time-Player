import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../domain/track.dart';
import '../persistence/library_store.dart';
import 'file_availability.dart';
import 'local_metadata.dart';

class LocalSyncCancelled implements Exception {}

class LocalSourceSync extends ChangeNotifier {
  LocalSourceSync(this.store);
  final LibraryStore store;
  bool running = false, cancelled = false, disposed = false;
  int examined = 0, processed = 0, placeholders = 0;
  String? source, error;
  void update() {
    if (!disposed) notifyListeners();
  }

  void cancel() {
    cancelled = true;
    update();
  }

  void check() {
    if (cancelled || disposed) throw LocalSyncCancelled();
  }

  Future<void> sync(String folder) async {
    if (running) throw StateError('Sincronização em andamento');
    running = true;
    cancelled = false;
    error = null;
    source = folder;
    examined = processed = placeholders = 0;
    update();
    final found = <String>{};
    final batch = <String>[];
    try {
      final directory = Directory(folder);
      if (!await directory.exists()) {
        throw FileSystemException('Pasta indisponível');
      }
      final previous = (await store.database.rawQuery(
        'SELECT ${LibraryStore.trackColumns('t', includeCovers: true)} FROM tracks t JOIN local_source_tracks m ON m.track_id=t.id WHERE m.source_id=?',
        [folder],
      )).map((row) => decodeTrackRow(row, applyUser: false)).toList();
      final old = {for (final track in previous) track.id: track};
      Future<void> flush() async {
        check();
        final local = <String>[];
        final tracks = <Track>[];
        for (final value in batch) {
          if (!File(value).existsSync()) continue;
          found.add(value);
          if (fileHasLocalData(File(value))) {
            local.add(value);
          } else {
            placeholders++;
            tracks.add(
              old[value] ??
                  Track(
                    id: value,
                    localPath: value,
                    title: path.basenameWithoutExtension(value),
                    artist: 'Artista desconhecido',
                    format: path.extension(value).substring(1).toUpperCase(),
                  ),
            );
          }
        }
        if (local.isNotEmpty) {
          tracks.addAll(
            await compute(readLocalSyncTracks, <String, Object>{
              'paths': local,
              'previous': <String, Track>{
                for (final id in local)
                  if (old.containsKey(id)) id: old[id]!,
              },
            }),
          );
        }
        check();
        await store.addTracks(tracks);
        await store.registerLocalSource(
          folder,
          folder,
          tracks.map((t) => t.id).toList(),
        );
        processed += tracks.length;
        batch.clear();
        update();
      }

      await for (final entry in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        check();
        examined++;
        if (entry is! File ||
            !RegExp(
              r'\.(mp3|flac|m4a|ogg|opus|wav)$',
              caseSensitive: false,
            ).hasMatch(entry.path)) {
          continue;
        }
        batch.add(entry.path);
        if (batch.length >= 25) await flush();
        if (examined % 100 == 0) update();
      }
      if (batch.isNotEmpty) await flush();
      check();
      // An empty existing folder is a valid snapshot. An inaccessible folder
      // throws during enumeration and never marks old memberships absent.
      await store.registerLocalSource(folder, folder, const []);
      found.removeWhere((id) => !File(id).existsSync());
      final previousPresent = (await store.database.query(
        'local_source_tracks',
        where: 'source_id=?',
        whereArgs: [folder],
      )).map((r) => r['track_id'] as String).toSet();
      await store.reconcileLocalSource(
        folder,
        found,
        previousPresent
            .difference(found)
            .where((id) => !File(id).existsSync())
            .toSet(),
        jsonEncode({
          'completedAt': DateTime.now().toIso8601String(),
          'total': found.length,
          'processed': processed,
          'missing': previousPresent.difference(found).length,
          'placeholders': placeholders,
        }),
      );
    } on LocalSyncCancelled {
      error = 'Sincronização cancelada; lotes já lidos foram preservados. A reconciliação final não foi aplicada.';
      rethrow;
    } catch (_) {
      error = 'Fonte inacessível ou leitura interrompida. Confira a pasta e tente novamente; a reconciliação final não foi aplicada.';
      rethrow;
    } finally {
      running = false;
      update();
    }
  }

  @override
  void dispose() {
    disposed = true;
    cancelled = true;
    super.dispose();
  }
}
