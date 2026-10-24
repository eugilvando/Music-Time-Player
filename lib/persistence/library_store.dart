import 'dart:convert';

import 'artwork_storage.dart';

import 'package:flutter/foundation.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/track.dart';
import '../library/catalog_query.dart';
import '../library/artwork.dart';
import '../library/m3u8.dart';
import '../library/playlist_reference.dart';

class SavedPlayback {
  const SavedPlayback(
    this.queue,
    this.index,
    this.position, {
    this.shuffle = false,
    this.repeat = 'off',
    this.volume = 100,
    this.title,
  });
  final List<Track> queue;
  final int index;
  final Duration position;
  final bool shuffle;
  final String repeat;
  final double volume;
  final String? title;
}

class LibraryStore {
  LibraryStore._(this.database);
  final Database database;
  late final artwork = ArtworkStorage(database);

  static Future<LibraryStore> open(
    String path, {
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('Abrindo o banco da biblioteca…');
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 16,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS tracks (id TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT NOT NULL, path TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS queue (ordinal INTEGER PRIMARY KEY, track_id TEXT NOT NULL REFERENCES tracks(id))',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS playback (id INTEGER PRIMARY KEY CHECK(id=1), current_index INTEGER NOT NULL, position_ms INTEGER NOT NULL)',
          );
          await _createCollections(db);
          await _metadataSchema(db);
          await _localSourcesSchema(db);
          await _ensureColumn(db, 'tracks', 'added_at', 'TEXT');
          await _localSyncSchema(db);
          await _catalogSearchSchema(db);
          await _cloudSourcesSchema(db);
          await _mediaCacheSchema(db);
          await _ensureColumn(
            db,
            'local_sources',
            'visible',
            'INTEGER NOT NULL DEFAULT 1',
          );
          await _catalogReadIndex(db);
          await _ensureColumn(db, 'playlists', 'cover', 'BLOB');
          await _playlistReadIndex(db);
          await _ensureColumn(db, 'playback', 'title', 'TEXT');
          await ArtworkStorage.createSchema(db);
          await _playlistReferencesSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          onProgress?.call(
            'Atualizando o catálogo da versão $oldVersion para $newVersion…',
          );
          if (oldVersion < 10) await _mediaCacheSchema(db);
          if (oldVersion < 9) await _cloudSourcesSchema(db);
          if (oldVersion < 6) {
            await _ensureColumn(db, 'tracks', 'added_at', 'TEXT');
          }
          if (oldVersion < 5) await _localSourcesSchema(db);
          if (oldVersion < 2) {
            await _createCollections(db);
          }
          if (oldVersion < 4) {
            await _metadataSchema(db);
          }
          if (oldVersion < 7) await _localSyncSchema(db);
          if (oldVersion < 8) {
            await _catalogSearchSchema(db);
          }
          await _ensureColumn(
            db,
            'local_sources',
            'visible',
            'INTEGER NOT NULL DEFAULT 1',
          );
          onProgress?.call('Preparando leitura rápida de metadados sem capas…');
          await _catalogReadIndex(db);
          await _ensureColumn(db, 'playlists', 'cover', 'BLOB');
          await _playlistReadIndex(db);
          await _ensureColumn(db, 'playback', 'title', 'TEXT');
          await ArtworkStorage.createSchema(db);
          await _playlistReferencesSchema(db);
          if (oldVersion < 15) {
            await LibraryStore._(db)
                .rebuildCatalogIndex(executor: db, onProgress: onProgress);
          }
        },
      ),
    );
    return LibraryStore._(db);
  }

  static Future<void> _catalogReadIndex(Database db) => db.execute(
    'CREATE INDEX IF NOT EXISTS tracks_catalog_read_idx ON tracks(id,title,artist,album,path,metadata,added_at,(cover IS NOT NULL))',
  );

  static Future<void> _playlistReadIndex(Database db) => db.execute(
    'CREATE INDEX IF NOT EXISTS playlist_entries_order_idx ON playlist_entries(playlist_id,ordinal,id,track_id)',
  );

  static Future<void> _playlistReferencesSchema(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(playlist_entries)');
    if (columns.any((c) => c['name'] == 'original_reference')) return;
    final sequence =
        (await db.rawQuery(
              "SELECT seq FROM sqlite_sequence WHERE name='playlist_entries'",
            )).firstOrNull?['seq']
            as int? ??
        0;
    await db.execute(
      'ALTER TABLE playlist_entries RENAME TO playlist_entries_old',
    );
    await db.execute(
      'CREATE TABLE playlist_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE, track_id TEXT REFERENCES tracks(id), ordinal INTEGER NOT NULL, original_reference TEXT, reference_base TEXT, reference_drive TEXT, import_title TEXT, import_artist TEXT, import_duration INTEGER, resolution_reason TEXT)',
    );
    await db.execute(
      'INSERT INTO playlist_entries(id,playlist_id,track_id,ordinal) SELECT id,playlist_id,track_id,ordinal FROM playlist_entries_old',
    );
    await db.execute('DROP TABLE playlist_entries_old');
    await db.rawInsert(
      "INSERT INTO sqlite_sequence(name,seq) SELECT 'playlist_entries',? WHERE NOT EXISTS(SELECT 1 FROM sqlite_sequence WHERE name='playlist_entries')",
      [sequence],
    );
    await db.rawUpdate(
      "UPDATE sqlite_sequence SET seq=MAX(seq,?) WHERE name='playlist_entries'",
      [sequence],
    );
    await _playlistReadIndex(db);
  }

  Future<int> importReviewedPlaylist(
    String name,
    PlaylistImportReport report,
  ) => database.transaction((txn) async {
    final base = name.trim().isEmpty ? 'Playlist' : name.trim();
    var unique = base, suffix = 2;
    while ((await txn.query(
      'playlists',
      columns: ['id'],
      where: 'name=? COLLATE NOCASE',
      whereArgs: [unique],
      limit: 1,
    )).isNotEmpty) {
      unique = '$base (${suffix++})';
    }
    final id = await txn.insert('playlists', {'name': unique});
    final batch = txn.batch();
    var ordinal = 0;
    for (final e in report.entries.where((e) => !e.removed)) {
      batch.insert('playlist_entries', {
        'playlist_id': id,
        'track_id': e.trackId,
        'ordinal': ordinal++,
        'original_reference': PlaylistReference.safe(e.reference),
        'reference_base': e.sourcePath,
        'reference_drive': e.driveId,
        'import_title': e.title,
        'import_artist': e.artist,
        'import_duration': e.durationSeconds,
        'resolution_reason': e.trackId == null ? e.reason ?? 'missing' : null,
      });
    }
    await batch.commit(noResult: true);
    return id;
  });

  Future<List<Map<String, Object?>>> playlistOccurrences(int id) =>
      database.query(
        'playlist_entries',
        where: 'playlist_id=?',
        whereArgs: [id],
        orderBy: 'ordinal,id',
      );

  Future<void> linkPlaylistOccurrence(int entryId, String trackId) async {
    await database.update(
      'playlist_entries',
      {'track_id': trackId, 'resolution_reason': null},
      where: 'id=?',
      whereArgs: [entryId],
    );
  }

  Future<void> retryPlaylistOccurrence(
    int entryId,
    String? trackId,
    String? reason,
  ) async {
    await database.update(
      'playlist_entries',
      {
        'track_id': trackId,
        'resolution_reason': trackId == null ? reason ?? 'missing' : null,
      },
      where: 'id=? AND track_id IS NULL',
      whereArgs: [entryId],
    );
  }

  static Future<void> _localSourcesSchema(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS local_sources (id TEXT PRIMARY KEY, label TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS local_source_tracks (source_id TEXT NOT NULL REFERENCES local_sources(id), track_id TEXT NOT NULL REFERENCES tracks(id), PRIMARY KEY(source_id, track_id))',
    );
    await db.insert('local_sources', {
      'id': 'legacy',
      'label': 'Arquivos locais existentes',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute(
      "INSERT OR IGNORE INTO local_source_tracks SELECT 'legacy', id FROM tracks WHERE path NOT LIKE 'onedrive:%'",
    );
  }

  static Future<void> _cloudSourcesSchema(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS cloud_sync_seen(source TEXT NOT NULL, track_id TEXT NOT NULL, PRIMARY KEY(source,track_id))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS cloud_sources(id TEXT PRIMARY KEY, account TEXT NOT NULL, folder TEXT NOT NULL, label TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS cloud_source_account ON cloud_sources(account)',
    );
  }

  static Future<void> _mediaCacheSchema(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS media_cache(track_id TEXT PRIMARY KEY REFERENCES tracks(id), revision TEXT NOT NULL, path TEXT NOT NULL, bytes INTEGER NOT NULL, last_played TEXT, cached_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS media_cache_access ON media_cache(last_played)',
    );
  }

  Future<void> saveCloudSource(
    String id,
    String account,
    String folder,
    String label,
    bool active,
  ) => database.insert('cloud_sources', {
    'id': id,
    'account': account,
    'folder': folder.isEmpty ? '/drive/root:' : folder,
    'label': label,
    'active': active ? 1 : 0,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> removeCloudSource(String id) async {
    final ids = await removableSourceTracks(id);
    await beforeSourceRemoval?.call(ids);
    await database.transaction((txn) async {
      await _deleteSourceTracks(txn, ids);
      await txn.delete('cloud_sources', where: 'id=?', whereArgs: [id]);
    });
  }

  /// Installed by the application so managed audio is removed before its rows.
  Future<void> Function(List<String>)? beforeSourceRemoval;

  Future<List<String>> removableSourceTracks(
    String id, {
    bool local = false,
  }) async {
    final rows = local
        ? await database.rawQuery(
            'SELECT track_id AS id FROM local_source_tracks m WHERE source_id=? AND NOT EXISTS(SELECT 1 FROM local_source_tracks other JOIN local_sources s ON s.id=other.source_id WHERE other.track_id=m.track_id AND other.source_id!=? AND s.active=1)',
            [id, id],
          )
        : await database.rawQuery(
            "SELECT c.track_id AS id FROM catalog_search c JOIN cloud_sources s ON s.id=? AND ${cloudAccountMatch('c.account', 's.account')} AND (c.folder=s.folder OR substr(c.folder,1,length(s.folder)+1)=s.folder||'/') WHERE NOT EXISTS(SELECT 1 FROM cloud_sources other WHERE other.id!=s.id AND ${cloudAccountMatch('other.account', 'c.account')} AND (c.folder=other.folder OR substr(c.folder,1,length(other.folder)+1)=other.folder||'/'))",
            [id],
          );
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<void> _deleteSourceTracks(Transaction txn, List<String> ids) async {
    if (ids.isEmpty) return;
    final encoded = jsonEncode(ids);
    const matches = 'IN (SELECT value FROM json_each(?))';
    // Keep playlist occurrences as repairable references; never delete playlists.
    await txn.rawUpdate(
      "UPDATE playlist_entries SET original_reference=COALESCE(original_reference,(SELECT CASE WHEN json_extract(metadata,'\$.driveId') IS NULL THEN path ELSE COALESCE(json_extract(metadata,'\$.sourcePath'),'')||'/'||COALESCE(NULLIF(json_extract(metadata,'\$.fileName'),''),title) END FROM tracks WHERE tracks.id=playlist_entries.track_id)), reference_drive=COALESCE(reference_drive,(SELECT json_extract(metadata,'\$.driveId') FROM tracks WHERE id=track_id)), import_title=COALESCE(import_title,(SELECT title FROM tracks WHERE id=track_id)), import_artist=COALESCE(import_artist,(SELECT artist FROM tracks WHERE id=track_id)), resolution_reason='missing', track_id=NULL WHERE track_id $matches",
      [encoded],
    );
    final queue = await txn.query('queue', orderBy: 'ordinal');
    final playback = (await txn.query('playback')).firstOrNull;
    final removed = ids.toSet();
    final oldIndex = playback?['current_index'] as int? ?? 0;
    final retained = queue
        .where((r) => !removed.contains(r['track_id']))
        .toList();
    final index = queue
        .take(oldIndex)
        .where((r) => !removed.contains(r['track_id']))
        .length;
    await txn.delete('queue');
    for (var i = 0; i < retained.length; i++) {
      await txn.insert('queue', {
        'ordinal': i,
        'track_id': retained[i]['track_id'],
      });
    }
    if (playback != null) {
      await txn.update('playback', {
        'current_index': retained.isEmpty
            ? -1
            : index.clamp(0, retained.length - 1),
        if (oldIndex >= 0 &&
            oldIndex < queue.length &&
            removed.contains(queue[oldIndex]['track_id']))
          'position_ms': 0,
      });
    }
    for (final table in [
      'downloads',
      'media_cache',
      'offline_memberships',
      'history',
      'favorites',
      'scrobble_outbox',
      'local_source_tracks',
      'cloud_sync_seen',
    ]) {
      await txn.delete(table, where: 'track_id $matches', whereArgs: [encoded]);
    }
    // Keep hidden local identities as protection for original files, including
    // originals deliberately stored inside a managed directory. Reset uses them.
    await txn.rawUpdate(
      "UPDATE tracks SET metadata=json_set(metadata,'\$.catalogExcluded',json('true')) WHERE id $matches AND json_extract(metadata,'\$.driveId') IS NULL",
      [encoded],
    );
    await txn.delete(
      'tracks',
      where: "id $matches AND json_extract(metadata,'\$.driveId') IS NOT NULL",
      whereArgs: [encoded],
    );
    await txn.rawDelete(
      'DELETE FROM artworks WHERE NOT EXISTS(SELECT 1 FROM tracks WHERE cover_hash=artworks.hash)',
    );
  }

  Future<Map<String, dynamic>?> cloudCheckpoint(String source) async {
    final rows = await database.query(
      'sync_cursors',
      where: 'source=?',
      whereArgs: ['scan:$source'],
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.single['cursor'] as String) as Map<String, dynamic>;
  }

  Future<Set<String>> cloudSeen(String source) async => (await database.query(
    'cloud_sync_seen',
    columns: ['track_id'],
    where: 'source=?',
    whereArgs: [source],
  )).map((r) => r['track_id'] as String).toSet();
  Future<void> saveCloudCheckpoint(
    String source,
    Map<String, Object?> state,
    Iterable<String> seen,
  ) async {
    await database.transaction((txn) async {
      final batch = txn.batch();
      for (final id in seen) {
        batch.insert('cloud_sync_seen', {
          'source': source,
          'track_id': id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      batch.insert('sync_cursors', {
        'source': 'scan:$source',
        'cursor': jsonEncode(state),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
    });
  }

  Future<void> clearCloudCheckpoint(String source) async {
    await database.transaction((txn) async {
      await txn.delete(
        'cloud_sync_seen',
        where: 'source=?',
        whereArgs: [source],
      );
      await txn.delete(
        'sync_cursors',
        where: 'source=?',
        whereArgs: ['scan:$source'],
      );
    });
  }

  Future<List<Map<String, Object?>>> localSources() => database.query(
    'local_sources',
    where: "active=1 AND (id != 'legacy' OR EXISTS (SELECT 1 FROM local_source_tracks WHERE source_id='legacy'))",
    orderBy: 'label',
  );
  static Future<void> _catalogSearchSchema(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS catalog_search(track_id TEXT PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,title_key TEXT NOT NULL,artist_key TEXT NOT NULL,album_key TEXT NOT NULL,album_identity TEXT NOT NULL,album_legacy TEXT NOT NULL,searchable TEXT NOT NULL,provider TEXT NOT NULL,account TEXT NOT NULL,folder TEXT NOT NULL,artists TEXT NOT NULL,genres TEXT NOT NULL,year INTEGER,format TEXT NOT NULL,duration_ms INTEGER NOT NULL,added_us INTEGER NOT NULL)',
    );
    for (final field in [
      'title_key',
      'artist_key',
      'album_key',
      'duration_ms',
      'added_us',
      'provider',
      'account',
      'folder',
      'album_identity',
    ]) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS catalog_${field}_idx ON catalog_search($field,track_id)',
      );
    }
  }

  static const metadataColumns = [
    'id',
    'title',
    'artist',
    'album',
    'path',
    'metadata',
    'added_at',
  ];
  static String trackColumns(String alias, {bool includeCovers = false}) =>
      "${metadataColumns.map((c) => '$alias.$c').join(',')},${ArtworkStorage.hasCover(alias)} AS has_cover${includeCovers ? ',${ArtworkStorage.cover(alias)} AS cover' : ''}";
  Future<void> rebuildCatalogIndex({
    DatabaseExecutor? executor,
    void Function(String)? onProgress,
  }) async {
    Future<void> rebuild(DatabaseExecutor txn) async {
      await txn.delete('catalog_search');
      String? cursor;
      var processed = 0;
      while (true) {
        final rows = await txn.rawQuery(
          'SELECT ${metadataColumns.join(',')} FROM tracks INDEXED BY tracks_catalog_read_idx ${cursor == null ? '' : 'WHERE id>?'} ORDER BY id LIMIT 500',
          cursor == null ? [] : [cursor],
        );
        if (rows.isEmpty) break;
        final projections = await compute(projectCatalogRows, rows);
        final batch = txn is Database
            ? txn.batch()
            : (txn as Transaction).batch();
        for (final projection in projections) {
          batch.insert('catalog_search', projection);
        }
        await batch.commit(noResult: true);
        cursor = rows.last['id'] as String;
        processed += rows.length;
        onProgress?.call('Atualizando busca: $processed faixas processadas…');
      }
    }

    if (executor != null) {
      await rebuild(executor);
    } else {
      await database.transaction(rebuild);
    }
  }

  Future<CatalogPage> catalogPage(
    CatalogSqlQuery query, {
    int offset = 0,
    int limit = 100,
    bool includeCovers = true,
  }) async {
    if (offset < 0 || limit < 1 || limit > 200) {
      throw ArgumentError('Página inválida');
    }
    return database.transaction((txn) async {
      final total =
          (await txn.rawQuery(
                'SELECT COUNT(*) AS n ${CatalogSqlQuery.from} WHERE ${query.where}',
                query.arguments,
              )).single['n']
              as int;
      final columns = includeCovers
          ? trackColumns('t', includeCovers: true)
          : "${metadataColumns.map((c) => 't.$c').join(',')}, ${ArtworkStorage.hasCover('t')} AS has_cover";
      final rows = await txn.rawQuery(
        'SELECT $columns ${CatalogSqlQuery.from} WHERE ${query.where} ORDER BY ${query.order} LIMIT ? OFFSET ?',
        [...query.arguments, limit, offset],
      );
      return CatalogPage(rows.map(trackFromRow).toList(), total, offset);
    });
  }

  Future<List<Track>> catalogResult(
    CatalogSqlQuery query,
  ) async => (await database.rawQuery(
    'SELECT ${metadataColumns.map((c) => 't.$c').join(',')}, ${ArtworkStorage.hasCover('t')} AS has_cover ${CatalogSqlQuery.from} WHERE ${query.where} ORDER BY ${query.order}',
    query.arguments,
  )).map(trackFromRow).toList();
  Future<Uint8List?> trackCover(String id) async =>
      (await database.rawQuery(
            'SELECT ${ArtworkStorage.cover('t')} AS cover FROM tracks t WHERE id=?',
            [id],
          )).firstOrNull?['cover']
          as Uint8List?;

  Future<void> setMissingFolderCover(
    String drive,
    String folder,
    Uint8List bytes,
  ) async {
    final hash = (await compute(artworkHashes, [bytes])).single!;
    await database.transaction((txn) async {
      await txn.insert('artworks', {
        'hash': hash,
        'bytes': bytes,
        'byte_count': bytes.length,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update(
        'tracks',
        {'cover_hash': hash},
        where: "cover IS NULL AND cover_hash IS NULL AND json_extract(metadata, '\$.driveId')=? AND json_extract(metadata, '\$.sourcePath')=?",
        whereArgs: [drive, folder],
      );
    });
  }

  static Future<void> _localSyncSchema(Database db) async {
    await _ensureColumn(
      db,
      'local_source_tracks',
      'present',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(db, 'local_sources', 'sync_summary', 'TEXT');
  }

  Future<void> registerLocalSource(String id, String label, List<String> ids) =>
      database.transaction((txn) async {
        await txn.insert('local_sources', {
          'id': id,
          'label': label,
          'active': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.update(
          'local_sources',
          {'active': 1},
          where: 'id=?',
          whereArgs: [id],
        );
        for (final trackId in ids) {
          await txn.rawUpdate(
            "UPDATE tracks SET metadata=json_remove(metadata,'\$.catalogExcluded') WHERE id=?",
            [trackId],
          );
          await txn.insert('local_source_tracks', {
            'source_id': id,
            'track_id': trackId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });
  Future<void> removeLocalSource(String id) async {
    final ids = await removableSourceTracks(id, local: true);
    await beforeSourceRemoval?.call(ids);
    await database.transaction((txn) async {
      await _deleteSourceTracks(txn, ids);
      await txn.delete(
        'local_source_tracks',
        where: 'source_id=?',
        whereArgs: [id],
      );
      await txn.delete('local_sources', where: 'id=?', whereArgs: [id]);
    });
  }

  Future<int> importPlaylist(String name, List<String> trackIds) async {
    if (name.trim().isEmpty) throw ArgumentError('Nome obrigatório');
    return database.transaction((txn) async {
      final id = await txn.insert('playlists', {'name': name.trim()});
      for (var i = 0; i < trackIds.length; i++) {
        await txn.insert('playlist_entries', {
          'playlist_id': id,
          'track_id': trackIds[i],
          'ordinal': i,
        });
      }
      return id;
    });
  }

  Future<void> addTracks(
    List<Track> tracks, {
    bool preserveCovers = false,
  }) async {
    final hashes = await compute(
      artworkHashes,
      tracks.map((t) => t.cover).toList(),
    );
    await database.transaction((txn) async {
      final previousOverrides = <String, Object?>{};
      final previousDates = {
        for (final row in await txn.rawQuery(
          r"SELECT id,added_at,json_extract(metadata,'$.userOverride') AS user_override FROM tracks WHERE id IN (SELECT value FROM json_each(?))",
          [jsonEncode(tracks.map((t) => t.id).toList())],
        ))
          row['id'] as String: (() {
            previousOverrides[row['id'] as String] = row['user_override'];
            return row['added_at'] as String?;
          })(),
      };
      final batch = txn.batch();
      for (var trackIndex = 0; trackIndex < tracks.length; trackIndex++) {
        final track = tracks[trackIndex];
        final hash = hashes[trackIndex];
        if (hash != null) {
          batch.insert('artworks', {
            'hash': hash,
            'bytes': track.cover,
            'byte_count': track.cover!.length,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        if (track.localPath == null &&
            (track.driveId == null || track.itemId == null)) {
          throw ArgumentError('Arquivo local obrigatório');
        }
        final row = <String, Object?>{
          'id': track.id,
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'path': track.localPath ?? 'onedrive:///',
          'metadata': jsonEncode({
            if (previousOverrides[track.id] is String)
              'userOverride': jsonDecode(previousOverrides[track.id] as String),
            'duration': track.duration.inMilliseconds,
            'albumArtist': track.albumArtist,
            'genre': track.genre,
            'year': track.year,
            'trackNumber': track.trackNumber,
            'discNumber': track.discNumber,
            'sourcePath': track.sourcePath,
            'fileName': track.fileName,
            'cloudTagsVersion': track.cloudTagsVersion,
            'cloudCoverEmbedded': track.cloudCoverEmbedded,
            'revision': track.revision,
            'available': track.available,
            'driveId': track.driveId,
            'itemId': track.itemId,
            'artists': track.artists,
            'albumArtists': track.albumArtists,
            'genres': track.genres,
            'albumId': track.albumId,
            'edition': track.edition,
            'format': track.format,
            'sourceProvider': track.sourceProvider,
            'sourceAccount': track.sourceAccount,
          }),
          'cover': track.cover,
        };
        final added =
            previousDates[track.id] ??
            (track.addedAt ?? DateTime.now().toUtc()).toIso8601String();
        previousDates[track.id] = added;
        batch.rawInsert(
          'INSERT INTO tracks(id,title,artist,album,path,metadata,cover,added_at,cover_hash) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,artist=excluded.artist,album=excluded.album,path=excluded.path,metadata=excluded.metadata,cover=${preserveCovers ? 'CASE WHEN excluded.cover_hash IS NULL THEN tracks.cover ELSE NULL END' : 'NULL'},cover_hash=${preserveCovers ? 'COALESCE(excluded.cover_hash,tracks.cover_hash)' : 'excluded.cover_hash'}',
          [
            row['id'],
            row['title'],
            row['artist'],
            row['album'],
            row['path'],
            row['metadata'],
            null,
            added,
            hash,
          ],
        );
        batch.insert(
          'catalog_search',
          catalogProjection(trackFromRow({...row, 'added_at': added})),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Track trackFromRow(Map<String, Object?> row) => decodeTrackRow(row);

  Future<void> setUserMetadata(
    List<String> ids,
    Map<String, Object?> fields, {
    bool clear = false,
  }) => _writeUserMetadata({for (final id in ids) id: fields}, clear: clear);

  Future<void> setUserMetadataBatch(
    Map<String, Map<String, Object?>> changes,
  ) => _writeUserMetadata(changes);

  Future<void> _writeUserMetadata(
    Map<String, Map<String, Object?>> changes, {
    bool clear = false,
  }) async {
    const allowed = {
      'title',
      'artist',
      'artists',
      'album',
      'albumArtist',
      'albumArtists',
      'genre',
      'genres',
      'year',
      'trackNumber',
      'discNumber',
      'edition',
      'albumId',
    };
    for (final fields in changes.values) {
      if (fields.keys.any((k) => !allowed.contains(k))) {
        throw ArgumentError('Campo não editável');
      }
      for (final entry in fields.entries) {
        if (entry.value == null) continue;
        if ({'year', 'trackNumber', 'discNumber'}.contains(entry.key)) {
          if (entry.value is! int ||
              (entry.value as int) < 1 ||
              (entry.value as int) > 9999) {
            throw ArgumentError('Número inválido');
          }
        } else if ({'artists', 'albumArtists', 'genres'}.contains(entry.key)) {
          if (entry.value is! List<String>) {
            throw ArgumentError('Lista inválida');
          }
        } else if (entry.value is! String) {
          throw ArgumentError('Texto inválido');
        }
      }
    }
    await database.transaction((txn) async {
      final rows = await txn.query(
        'tracks',
        columns: metadataColumns,
        where: 'id IN (SELECT value FROM json_each(?))',
        whereArgs: [jsonEncode(changes.keys.toList())],
      );
      final batch = txn.batch();
      for (final row in rows) {
        final metadata = jsonDecode(
          row['metadata'] as String? ?? '{}',
        ) as Map<String, dynamic>;
        final override = clear
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(metadata['userOverride'] as Map? ?? {});
        override.addAll(changes[row['id']]!);
        metadata['userOverride'] = override;
        final encoded = jsonEncode(metadata);
        batch.update(
          'tracks',
          {'metadata': encoded},
          where: 'id=?',
          whereArgs: [row['id']],
        );
        batch.insert(
          'catalog_search',
          catalogProjection(decodeTrackRow({...row, 'metadata': encoded})),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Track>> loadTracks({
    bool includeCovers = true,
    bool includeHidden = false,
  }) async {
    final rows = includeCovers
        ? await database.rawQuery(
            "SELECT ${trackColumns('tracks', includeCovers: true)} FROM tracks ${includeHidden ? '' : 'WHERE ${catalogVisibility('tracks')}'} ORDER BY rowid",
          )
        : await database.rawQuery(
            'SELECT ${metadataColumns.join(',')},${ArtworkStorage.available} AS has_cover FROM tracks INDEXED BY tracks_catalog_read_idx ${includeHidden ? '' : 'WHERE ${catalogVisibility('tracks')}'} ORDER BY rowid',
          );
    return !includeCovers && rows.length > 1000
        ? await compute(decodeCatalogRows, rows)
        : decodeCatalogRows(rows);
  }

  Future<void> savePlayback(
    List<Track> queue,
    int index,
    Duration position, {
    bool shuffle = false,
    String repeat = 'off',
    double volume = 100,
    String? title,
  }) async {
    await database.transaction((txn) async {
      final previous = (await txn.query(
        'queue',
        columns: ['track_id'],
        orderBy: 'ordinal',
      )).map((r) => r['track_id'] as String).toList();
      if (!listEquals(previous, queue.map((t) => t.id).toList())) {
        final batch = txn.batch();
        batch.delete('queue');
        for (var i = 0; i < queue.length; i++) {
          batch.insert('queue', {'ordinal': i, 'track_id': queue[i].id});
        }
        await batch.commit(noResult: true);
      }
      await txn.insert('playback', {
        'id': 1,
        'current_index': index,
        'position_ms': position.inMilliseconds,
        'shuffle': shuffle ? 1 : 0,
        'repeat': repeat,
        'volume': volume,
        'title': title,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<SavedPlayback> loadPlayback({bool includeCovers = true}) async {
    final columns = includeCovers
        ? trackColumns('t', includeCovers: true)
        : "${metadataColumns.map((c) => 't.$c').join(',')}, ${ArtworkStorage.hasCover('t')} AS has_cover";
    final queue = (await database.rawQuery(
      'SELECT $columns FROM queue q JOIN tracks t ON t.id=q.track_id ORDER BY q.ordinal',
    )).map(trackFromRow).toList();
    final rows = await database.query('playback');
    if (rows.isEmpty || queue.isEmpty) {
      return const SavedPlayback([], -1, Duration.zero);
    }
    final index = rows.first['current_index'] as int;
    final ms = rows.first['position_ms'] as int;
    return SavedPlayback(
      queue,
      index.clamp(0, queue.length - 1),
      Duration(milliseconds: ms < 0 ? 0 : ms),
      shuffle: rows.first['shuffle'] == 1,
      repeat: rows.first['repeat'] as String? ?? 'off',
      title: rows.first['title'] as String?,
      volume: (rows.first['volume'] as num? ?? 100).toDouble().clamp(0, 100),
    );
  }

  static Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String declaration,
  ) async {
    final fields = await db.rawQuery('PRAGMA table_info($table)');
    if (fields.any((field) => field['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $declaration');
  }

  static Future<void> _metadataSchema(Database db) async {
    await _ensureColumn(db, 'tracks', 'metadata', "TEXT NOT NULL DEFAULT '{}'");
    await _ensureColumn(db, 'tracks', 'cover', 'BLOB');
    await db.execute(
      'CREATE TABLE IF NOT EXISTS sync_cursors (source TEXT PRIMARY KEY, cursor TEXT NOT NULL, updated_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS downloads (track_id TEXT PRIMARY KEY REFERENCES tracks(id), path TEXT, status TEXT NOT NULL DEFAULT "pending", received INTEGER NOT NULL DEFAULT 0, total INTEGER, error TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS offline_memberships (selection TEXT NOT NULL, track_id TEXT NOT NULL REFERENCES tracks(id), PRIMARY KEY(selection, track_id))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS scrobble_outbox (id TEXT PRIMARY KEY, track_id TEXT NOT NULL REFERENCES tracks(id), title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT NOT NULL, started_at TEXT NOT NULL, duration_ms INTEGER NOT NULL, status TEXT NOT NULL DEFAULT "pending", attempts INTEGER NOT NULL DEFAULT 0, next_attempt TEXT, error TEXT)',
    );
    await _ensureColumn(
      db,
      'playback',
      'shuffle',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'playback',
      'repeat',
      "TEXT NOT NULL DEFAULT 'off'",
    );
    await _ensureColumn(db, 'playback', 'volume', 'REAL NOT NULL DEFAULT 100');
    await db.execute(
      'CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY AUTOINCREMENT, track_id TEXT NOT NULL REFERENCES tracks(id), started_at TEXT NOT NULL, listened_ms INTEGER NOT NULL, UNIQUE(track_id, started_at))',
    );
  }

  static Future<void> _createCollections(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS favorites (track_id TEXT PRIMARY KEY REFERENCES tracks(id), added_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK(length(trim(name))>0))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS playlist_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE, track_id TEXT NOT NULL REFERENCES tracks(id), ordinal INTEGER NOT NULL)',
    );
  }

  Future<Set<String>> favoriteIds() async =>
      (await database.query('favorites'))
          .map((row) => row['track_id'] as String)
          .toSet();

  Future<void> setFavorite(String trackId, bool favorite) async {
    if (favorite) {
      await database.insert('favorites', {
        'track_id': trackId,
        'added_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await database.delete(
        'favorites',
        where: 'track_id = ?',
        whereArgs: [trackId],
      );
    }
  }

  Future<List<Map<String, Object?>>> playlists() => database.rawQuery(
    'SELECT p.id,p.name,(p.cover IS NOT NULL) AS has_cover,COUNT(e.id) AS track_count,COUNT(e.track_id) AS resolved_count,SUM(CASE WHEN e.id IS NOT NULL AND e.track_id IS NULL THEN 1 ELSE 0 END) AS pending_count FROM playlists p LEFT JOIN playlist_entries e ON e.playlist_id=p.id GROUP BY p.id ORDER BY p.name COLLATE NOCASE,p.id',
  );

  Future<Uint8List?> playlistCover(int id) async {
    final rows = await database.query(
      'playlists',
      columns: ['cover'],
      where: 'id=?',
      whereArgs: [id],
    );
    return rows.firstOrNull?['cover'] as Uint8List?;
  }

  Future<void> setPlaylistCover(int id, Uint8List? cover) async {
    if (cover != null && validatedArtwork(cover) == null) {
      throw const FormatException('Use uma imagem PNG ou JPEG de até 4 MB.');
    }
    final count = await database.update(
      'playlists',
      {'cover': cover},
      where: 'id=?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Playlist não encontrada');
  }

  Future<int> createPlaylist(String name) {
    if (name.trim().isEmpty) throw ArgumentError('Nome obrigatório');
    return database.insert('playlists', {'name': name.trim()});
  }

  Future<void> renamePlaylist(int id, String name) async {
    if (name.trim().isEmpty) throw ArgumentError('Nome obrigatório');
    await database.update(
      'playlists',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePlaylist(int id) async {
    await database.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> appendToPlaylist(int id, String trackId) async {
    await database.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT COALESCE(MAX(ordinal), -1)+1 AS next FROM playlist_entries WHERE playlist_id = ?',
        [id],
      );
      await txn.insert('playlist_entries', {
        'playlist_id': id,
        'track_id': trackId,
        'ordinal': rows.single['next'],
      });
    });
  }

  Future<List<Map<String, Object?>>> playlistEntries(
    int id,
  ) => database.rawQuery(
    "SELECT e.id AS entry_id, ${metadataColumns.map((c) => 't.$c').join(',')}, ${ArtworkStorage.hasCover('t')} AS has_cover, e.ordinal FROM playlist_entries e INDEXED BY playlist_entries_order_idx JOIN tracks t INDEXED BY tracks_catalog_read_idx ON t.id=e.track_id WHERE playlist_id=? ORDER BY e.ordinal, e.id",
    [id],
  );

  Future<List<Track>> playlistArtworkTracks(
    int id,
  ) async => (await database.rawQuery(
    "SELECT ${metadataColumns.map((c) => 't.$c').join(',')}, ${ArtworkStorage.hasCover('t')} AS has_cover FROM playlist_entries e JOIN tracks t ON t.id=e.track_id WHERE e.playlist_id=? ORDER BY e.ordinal,e.id LIMIT 4",
    [id],
  )).map(trackFromRow).toList();

  Future<List<String>> playlistTrackIds(int id) async =>
      (await database.rawQuery(
        'SELECT track_id FROM playlist_entries WHERE playlist_id=? AND track_id IS NOT NULL ORDER BY ordinal,id',
        [id],
      )).map((row) => row['track_id'] as String).toList();

  Future<void> removePlaylistEntry(int entryId) async {
    await database.delete(
      'playlist_entries',
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }

  Future<void> reorderPlaylist(int playlistId, List<int> entryIds) async {
    await database.transaction((txn) async {
      final current = await txn.query(
        'playlist_entries',
        columns: ['id'],
        where: 'playlist_id=?',
        whereArgs: [playlistId],
      );
      final existing = current.map((row) => row['id'] as int).toSet();
      if (entryIds.length != existing.length ||
          entryIds.toSet().length != existing.length ||
          !entryIds.toSet().containsAll(existing)) {
        throw ArgumentError(
          'Ordenação deve conter todas as ocorrências da playlist.',
        );
      }
      for (var index = 0; index < entryIds.length; index++) {
        await txn.update(
          'playlist_entries',
          {'ordinal': index},
          where: 'id=? AND playlist_id=?',
          whereArgs: [entryIds[index], playlistId],
        );
      }
    });
  }

  Future<Map<String, Map<String, Object?>>> listeningStats() async {
    final rows = await database.rawQuery(
      'SELECT track_id, COUNT(*) AS play_count, MAX(started_at) AS last_played FROM history GROUP BY track_id',
    );
    return {for (final row in rows) row['track_id'] as String: row};
  }

  Future<Map<String, List<Map<String, Object?>>>> sourceMemberships() async {
    final rows = await database.rawQuery(
      'SELECT m.track_id, s.id, s.label FROM local_source_tracks m JOIN local_sources s ON s.id=m.source_id WHERE s.active=1 AND s.visible=1 AND m.present=1',
    );
    final result = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      result.putIfAbsent(row['track_id'] as String, () => []).add(row);
    }
    for (final row in await database.rawQuery(
      "SELECT c.track_id, s.id, s.label FROM catalog_search c JOIN cloud_sources s ON ${cloudAccountMatch('c.account', 's.account')} AND (c.folder=s.folder OR substr(c.folder,1,length(s.folder)+1)=s.folder||'/') WHERE s.active=1",
    )) {
      result.putIfAbsent(row['track_id'] as String, () => []).add(row);
    }
    return result;
  }

  Future<void> setFavorites(List<String> ids, bool value) =>
      database.transaction((txn) async {
        for (final id in ids.toSet()) {
          if (value) {
            await txn.insert('favorites', {
              'track_id': id,
              'added_at': DateTime.now().toUtc().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          } else {
            await txn.delete('favorites', where: 'track_id=?', whereArgs: [id]);
          }
        }
      });
  Future<void> appendTracksToPlaylist(int id, List<String> ids) =>
      database.transaction((txn) async {
        final row = await txn.rawQuery(
          'SELECT COALESCE(MAX(ordinal), -1)+1 AS next FROM playlist_entries WHERE playlist_id=?',
          [id],
        );
        var ordinal = row.single['next'] as int;
        for (final trackId in ids) {
          await txn.insert('playlist_entries', {
            'playlist_id': id,
            'track_id': trackId,
            'ordinal': ordinal++,
          });
        }
      });
  Future<void> recordHistory(
    String trackId,
    DateTime started,
    Duration listened,
  ) async {
    await database.insert('history', {
      'track_id': trackId,
      'started_at': started.toUtc().toIso8601String(),
      'listened_ms': listened.inMilliseconds,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> history() => database.rawQuery(
    'SELECT ${trackColumns('t', includeCovers: true)}, h.started_at, h.listened_ms FROM history h JOIN tracks t ON t.id=h.track_id ORDER BY h.started_at DESC, h.id DESC LIMIT 200',
  );

  Future<void> enqueueScrobble(
    Track track,
    DateTime started,
    Duration duration,
  ) async {
    await database.insert('scrobble_outbox', {
      'id': '${track.id}|${started.toUtc().toIso8601String()}',
      'track_id': track.id,
      'title': track.title,
      'artist': track.artist,
      'album': track.album,
      'started_at': started.toUtc().toIso8601String(),
      'duration_ms': duration.inMilliseconds,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> pendingScrobbles() => database.query(
    'scrobble_outbox',
    where: 'status=? AND (next_attempt IS NULL OR next_attempt <= ?)',
    whereArgs: ['pending', DateTime.now().toUtc().toIso8601String()],
    orderBy: 'started_at',
    limit: 25,
  );
  Future<List<Map<String, Object?>>> scrobbleStatus() =>
      database.query('scrobble_outbox', orderBy: 'started_at DESC', limit: 100);
  Future<void> updateScrobble(
    String id,
    String status,
    int attempts, {
    String? error,
    DateTime? nextAttempt,
  }) async {
    await database.update(
      'scrobble_outbox',
      {
        'status': status,
        'attempts': attempts,
        'error': error,
        'next_attempt': nextAttempt?.toUtc().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> recoverScrobbles() async {
    await database.update(
      'scrobble_outbox',
      {
        'status': 'ambiguous',
        'error': 'Aplicativo interrompido durante envio.',
      },
      where: 'status=?',
      whereArgs: ['sending'],
    );
  }

  Future<void> reconnectScrobbles() async {
    await database.update(
      'scrobble_outbox',
      {'status': 'pending', 'error': null, 'next_attempt': null},
      where: 'status=?',
      whereArgs: ['auth_required'],
    );
  }

  Future<void> selectOffline(String selection, List<Track> tracks) async {
    await database.transaction((txn) async {
      for (final track in tracks) {
        await txn.insert('offline_memberships', {
          'selection': selection,
          'track_id': track.id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert('downloads', {
          'track_id': track.id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.update(
          'downloads',
          {'status': 'pending', 'error': null},
          where: 'track_id=? AND status=?',
          whereArgs: [track.id, 'removed'],
        );
      }
    });
  }

  Future<List<Map<String, Object?>>> downloadTasks({
    bool includeCovers = true,
  }) {
    final columns = includeCovers
        ? trackColumns('t', includeCovers: true)
        : "${metadataColumns.map((c) => 't.$c').join(',')}, ${ArtworkStorage.hasCover('t')} AS has_cover";
    return database.rawQuery(
      'SELECT $columns, d.path AS download_path, d.status, d.received, d.total, d.error FROM downloads d JOIN tracks t ON t.id=d.track_id ORDER BY t.title',
    );
  }

  Future<Map<String, Object?>?> offlineFile(String trackId) async {
    final rows = await database.query(
      'downloads',
      where: 'track_id=? AND status=?',
      whereArgs: [trackId, 'complete'],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> updateDownload(
    String id,
    String status, {
    String? path,
    int received = 0,
    int? total,
    String? error,
  }) async {
    await database.update(
      'downloads',
      {
        'status': status,
        'path': path,
        'received': received,
        'total': total,
        'error': error,
      },
      where: 'track_id=?',
      whereArgs: [id],
    );
  }

  Future<List<String>> removeOfflineSelection(String selection) async =>
      database.transaction((txn) async {
        final rows = await txn.query(
          'offline_memberships',
          where: 'selection=?',
          whereArgs: [selection],
        );
        await txn.delete(
          'offline_memberships',
          where: 'selection=?',
          whereArgs: [selection],
        );
        final unreferenced = <String>[];
        for (final row in rows) {
          final id = row['track_id'] as String;
          final refs = await txn.query(
            'offline_memberships',
            where: 'track_id=?',
            whereArgs: [id],
            limit: 1,
          );
          if (refs.isEmpty) unreferenced.add(id);
        }
        return unreferenced;
      });

  Future<void> removeOfflineTrackReferences(String trackId) async {
    await database.delete(
      'offline_memberships',
      where: 'track_id=?',
      whereArgs: [trackId],
    );
  }

  Future<List<Map<String, Object?>>> offlineSelections() => database.rawQuery(
    'SELECT selection, COUNT(*) AS count FROM offline_memberships GROUP BY selection',
  );

  Future<void> recoverDownloads() async {
    await database.update(
      'downloads',
      {'status': 'pending'},
      where: 'status=?',
      whereArgs: ['downloading'],
    );
  }

  Future<Uri?> syncCursor(String source) async {
    final rows = await database.query(
      'sync_cursors',
      where: 'source=?',
      whereArgs: [source],
    );
    return rows.isEmpty ? null : Uri.parse(rows.single['cursor'] as String);
  }

  Future<void> finishSync(
    String source,
    Uri cursor,
    List<String> deleted,
  ) async {
    await database.transaction((txn) async {
      for (final id in deleted) {
        final rows = await txn.query(
          'tracks',
          columns: ['metadata'],
          where: 'id=?',
          whereArgs: [id],
        );
        if (rows.isEmpty) continue;
        final data = jsonDecode(
          rows.single['metadata'] as String,
        ) as Map<String, dynamic>;
        data['available'] = false;
        await txn.update(
          'tracks',
          {'metadata': jsonEncode(data)},
          where: 'id=?',
          whereArgs: [id],
        );
      }
      await txn.insert('sync_cursors', {
        'source': source,
        'cursor': cursor.toString(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<int> resetSyncCursor(String source) =>
      database.delete('sync_cursors', where: 'source=?', whereArgs: [source]);

  Future<void> close() => database.close();

  Future<void> reconcileLocalSource(
    String source,
    Set<String> found,
    Set<String> missing,
    String summary,
  ) async {
    await database.transaction((txn) async {
      for (final membership in await txn.query(
        'local_source_tracks',
        where: 'source_id=?',
        whereArgs: [source],
      )) {
        final id = membership['track_id'] as String;
        await txn.update(
          'local_source_tracks',
          {'present': found.contains(id) ? 1 : 0},
          where: 'source_id=? AND track_id=?',
          whereArgs: [source, id],
        );
        if (found.contains(id) || missing.contains(id)) {
          final rows = await txn.query(
            'tracks',
            columns: ['metadata'],
            where: 'id=?',
            whereArgs: [id],
          );
          final metadata = jsonDecode(
            rows.single['metadata'] as String,
          ) as Map<String, dynamic>;
          metadata['available'] = found.contains(id);
          await txn.update(
            'tracks',
            {'metadata': jsonEncode(metadata)},
            where: 'id=?',
            whereArgs: [id],
          );
        }
      }
      await txn.update(
        'local_sources',
        {'sync_summary': summary},
        where: 'id=?',
        whereArgs: [source],
      );
    });
  }

  Future<void> finishOneDriveFolder(
    String account,
    String folder,
    Set<String> seen,
  ) async {
    await database.rawUpdate(
      r"UPDATE tracks SET metadata=json_set(metadata,'$.catalogExcluded',json('false'),'$.available',json(CASE WHEN id IN (SELECT value FROM json_each(?)) THEN 'true' ELSE 'false' END)) WHERE json_extract(metadata,'$.driveId')=? AND (?='' OR json_extract(metadata,'$.sourcePath')=? OR substr(json_extract(metadata,'$.sourcePath'),1,length(?)+1)=?||'/')",
      [jsonEncode(seen.toList()), account, folder, folder, folder, folder],
    );
  }
}

Track decodeTrackRow(Map<String, Object?> row, {bool applyUser = true}) {
  final metadata =
      jsonDecode(row['metadata'] as String? ?? '{}') as Map<String, dynamic>;
  final overrides = applyUser && metadata['userOverride'] is Map
      ? Map<String, dynamic>.from(metadata['userOverride'] as Map)
      : <String, dynamic>{};
  metadata.addAll(overrides);
  return Track(
    id: row['id'] as String,
    title: overrides['title'] as String? ?? row['title'] as String,
    artist: overrides['artist'] as String? ?? row['artist'] as String,
    album: overrides['album'] as String? ?? row['album'] as String,
    localPath: metadata['driveId'] == null ? row['path'] as String : null,
    driveId: metadata['driveId'] as String?,
    sourcePath: metadata['sourcePath'] as String? ?? '',
    fileName: metadata['fileName'] as String? ?? '',
    cloudTagsVersion: metadata['cloudTagsVersion'] as int? ?? 0,
    cloudCoverEmbedded: metadata['cloudCoverEmbedded'] as bool? ?? false,
    revision: metadata['revision'] as String? ?? '',
    available: metadata['available'] as bool? ?? true,
    itemId: metadata['itemId'] as String?,
    duration: Duration(milliseconds: metadata['duration'] as int? ?? 0),
    albumArtist: metadata['albumArtist'] as String? ?? '',
    genre: metadata['genre'] as String? ?? '',
    year: metadata['year'] as int?,
    trackNumber: metadata['trackNumber'] as int?,
    discNumber: metadata['discNumber'] as int?,
    cover: row['cover'] as Uint8List?,
    coverAvailable: row['has_cover'] == 1,
    artists: (metadata['artists'] as List? ?? []).cast<String>(),
    albumArtists: (metadata['albumArtists'] as List? ?? []).cast<String>(),
    genres: (metadata['genres'] as List? ?? []).cast<String>(),
    albumId: metadata['albumId'] as String? ?? '',
    edition: metadata['edition'] as String? ?? '',
    format: metadata['format'] as String? ?? '',
    sourceProvider: metadata['sourceProvider'] as String? ?? '',
    sourceAccount: metadata['sourceAccount'] as String? ?? '',
    addedAt: DateTime.tryParse(row['added_at'] as String? ?? ''),
  );
}

List<Track> decodeCatalogRows(List<Map<String, Object?>> rows) =>
    rows.map(decodeTrackRow).toList();

List<Map<String, Object?>> projectCatalogRows(
  List<Map<String, Object?>> rows,
) => rows.map((row) => catalogProjection(decodeTrackRow(row))).toList();
