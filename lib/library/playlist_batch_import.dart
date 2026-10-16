import 'package:flutter/foundation.dart';

import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/track.dart';
import '../persistence/library_store.dart';
import 'm3u8.dart';

class PlaylistImportFile {
  const PlaylistImportFile(this.path, this.read);
  final String path;
  final Future<String> Function() read;
}

/// File IO and UTF-8 decoding are executed in a worker, before catalog parsing.
Future<String> readPlaylistText(String path) async {
  final file = File(path);
  if (await file.length() > 16 * 1024 * 1024) {
    throw const FormatException('Invalid or unsupported playlist');
  }
  return file.readAsString();
}

class PlaylistImportResult {
  const PlaylistImportResult(
    this.name, {
    this.id,
    this.found = 0,
    this.pending = 0,
    this.failure,
    this.phase = 'Reading file',
  });
  final String name;
  final int? id;
  final int found, pending;

  /// Safe category, never exception text that might contain private locations.
  final String? failure;
  final String phase;
}

Future<List<PlaylistImportResult>> importPlaylistBatch(
  LibraryStore store,
  List<PlaylistImportFile> files,
  List<Track> catalog, {
  void Function(int done, int total, PlaylistImportResult current)? onProgress,
}) async {
  final results = <PlaylistImportResult>[];
  final drives = catalog
      .where((t) => t.provider == 'onedrive')
      .map((t) => t.driveId)
      .whereType<String>()
      .toSet();
  for (final file in files) {
    var name = p.basenameWithoutExtension(file.path);
    onProgress?.call(results.length, files.length, PlaylistImportResult(name));
    String? failure;
    String? content;
    try {
      content = await file.read();
    } on FormatException {
      failure = 'format';
    } catch (_) {
      failure = 'read';
    }
    PlaylistImportResult result;
    try {
      if (failure != null) throw const FormatException('read');
      if (content!.length > 16 * 1024 * 1024) {
        throw const FormatException('size');
      }
      final report = await compute(parsePlaylistInBackground, (
        content: content,
        filePath: file.path,
        tracks: catalog,
        drive: drives.length == 1 ? drives.single : null,
      ));
      if (report.name?.isNotEmpty == true) {
        name = report.name!;
      }
      onProgress?.call(
        results.length,
        files.length,
        PlaylistImportResult(
          name,
          found: report.ids.length,
          pending: report.unresolved,
          phase: 'Saving playlist',
        ),
      );
      failure = 'save';
      final id = await store.importReviewedPlaylist(name, report);
      result = PlaylistImportResult(
        name,
        id: id,
        found: report.ids.length,
        pending: report.unresolved,
        phase: 'Completed',
      );
    } catch (_) {
      result = PlaylistImportResult(name, failure: failure ?? 'format');
    }
    results.add(result);
    onProgress?.call(results.length, files.length, result);
    await Future<void>.delayed(Duration.zero);
  }
  return results;
}

/// Exact-only retry. Ambiguous candidates remain pending, including duplicates.
Future<int> retryPlaylistReferences(
  LibraryStore store,
  int playlist,
  List<Track> catalog,
) async {
  final pending = (await store.playlistOccurrences(playlist))
      .where((r) => r['track_id'] == null)
      .toList();
  final groups = <(String, String?), List<Map<String, Object?>>>{};
  for (final row in pending) {
    final key = (
      row['reference_base'] as String? ?? '',
      row['reference_drive'] as String?,
    );
    (groups[key] ??= []).add(row);
  }
  var linked = 0;
  for (final group in groups.entries) {
    final report = await compute(parsePlaylistInBackground, (
      content: group.value
          .map((r) => r['original_reference'] as String? ?? '')
          .join('\n'),
      filePath: group.key.$1,
      tracks: catalog,
      drive: group.key.$2,
    ));
    for (var i = 0; i < group.value.length; i++) {
      final track = report.entries[i].trackId;
      await store.retryPlaylistOccurrence(
        group.value[i]['id'] as int,
        track,
        report.entries[i].reason,
      );
      if (track != null) {
        linked++;
      }
    }
  }
  return linked;
}
