import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<String?> artworkHashes(List<Uint8List?> images) => [
  for (final image in images)
    image == null ? null : sha256.convert(image).toString(),
];

class ArtworkOptimization {
  const ArtworkOptimization(this.processed, {this.compacting = false});
  final int processed;
  final bool compacting;
}

/// Exact byte deduplication. No resizing/recompression or source file writes.
class ArtworkStorage extends ChangeNotifier {
  ArtworkStorage(this.database);
  final Database database;
  bool running = false, cancelled = false, compacting = false;
  ArtworkOptimization? progress;
  void cancel() => cancelled = true;

  // Kept subquery-free because this expression also participates in an index.
  static const available = '(cover IS NOT NULL OR cover_hash IS NOT NULL)';
  static String hasCover(String alias) =>
      "($alias.cover IS NOT NULL OR $alias.cover_hash IS NOT NULL OR EXISTS (SELECT 1 FROM artworks WHERE hash=json_extract($alias.metadata,'\$.userOverride.catalogCoverHash')))";
  static String cover(String alias) =>
      "COALESCE((SELECT bytes FROM artworks WHERE hash=json_extract($alias.metadata,'\$.userOverride.catalogCoverHash')),$alias.cover,(SELECT bytes FROM artworks WHERE hash=$alias.cover_hash))";

  static Future<void> createSchema(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS artworks(hash TEXT PRIMARY KEY, bytes BLOB NOT NULL, byte_count INTEGER NOT NULL)',
    );
    if (!(await db.rawQuery('PRAGMA table_info(tracks)'))
        .any((r) => r['name'] == 'cover_hash')) {
      await db.execute(
        'ALTER TABLE tracks ADD COLUMN cover_hash TEXT REFERENCES artworks(hash)',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS tracks_artwork_idx ON tracks(cover_hash)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS tracks_legacy_artwork_idx ON tracks(id) WHERE cover IS NOT NULL',
    );
    // A previous executable can open a newer SQLite file without a downgrade
    // callback. Protect manual references even from its old cleanup query.
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS protect_manual_album_artwork
      BEFORE DELETE ON artworks
      WHEN EXISTS (SELECT 1 FROM tracks
        WHERE json_extract(metadata,'\$.userOverride.catalogCoverHash')=OLD.hash)
      BEGIN SELECT RAISE(ABORT,'Artwork is referenced by a manual album cover'); END
    """);
    await db.execute('DROP INDEX IF EXISTS tracks_catalog_read_idx');
    await db.execute(
      'CREATE INDEX tracks_catalog_read_idx ON tracks(id,title,artist,album,path,metadata,added_at,$available)',
    );
  }

  Future<int> storedBytes() async {
    var bytes =
        (await database.rawQuery(
              'SELECT COALESCE(SUM(byte_count),0) AS n FROM artworks',
            )).single['n']
            as int;
    // Short reads let playback saves and downloads run between batches.
    var cursor = 0;
    while (true) {
      final rows = await database.rawQuery(
        'SELECT rowid AS cursor,length(cover) AS n FROM tracks WHERE rowid>? ORDER BY rowid LIMIT 100',
        [cursor],
      );
      if (rows.isEmpty) return bytes;
      for (final row in rows) {
        bytes += row['n'] as int? ?? 0;
      }
      cursor = rows.last['cursor'] as int;
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Each batch commits both references and bytes atomically. Restarting resumes
  /// from remaining legacy covers. VACUUM only runs after all batches finish.
  Future<void> optimize({
    void Function(ArtworkOptimization)? onProgress,
    bool compact = true,
  }) async {
    if (running) throw StateError('Artwork optimization is already running');
    running = true;
    cancelled = false;
    progress = const ArtworkOptimization(0);
    notifyListeners();
    var processed = 0;
    try {
      while (!cancelled) {
        final rows = await database.rawQuery(
          'SELECT id,cover FROM tracks INDEXED BY tracks_legacy_artwork_idx WHERE cover IS NOT NULL LIMIT 16',
        );
        if (rows.isEmpty) break;
        final hashes = await compute(
          artworkHashes,
          rows.map((r) => r['cover'] as Uint8List?).toList(),
        );
        if (cancelled) return;
        await database.transaction((txn) async {
          final batch = txn.batch();
          for (var i = 0; i < rows.length; i++) {
            final bytes = rows[i]['cover'] as Uint8List;
            batch.insert('artworks', {
              'hash': hashes[i],
              'bytes': bytes,
              'byte_count': bytes.length,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
            // A sync may have replaced the cover while hashing off the UI isolate.
            batch.rawUpdate(
              'UPDATE tracks SET cover_hash=?,cover=NULL WHERE id=? AND cover=?',
              [hashes[i], rows[i]['id'], bytes],
            );
          }
          await batch.commit(noResult: true);
        });
        processed += rows.length;
        progress = ArtworkOptimization(processed);
        onProgress?.call(progress!);
        notifyListeners();
        await Future<void>.delayed(Duration.zero);
      }
      if (cancelled) return;
      await database.execute(
        "DELETE FROM artworks WHERE NOT EXISTS (SELECT 1 FROM tracks WHERE cover_hash=artworks.hash OR json_extract(metadata,'\$.userOverride.catalogCoverHash')=artworks.hash)",
      );
      if (compact && !cancelled) {
        compacting = true;
        progress = ArtworkOptimization(processed, compacting: true);
        onProgress?.call(progress!);
        notifyListeners();
        await database.execute('VACUUM');
      }
    } finally {
      running = compacting = false;
      notifyListeners();
    }
  }
}
