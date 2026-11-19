import 'dart:convert';

import '../persistence/library_store.dart';
import 'catalog.dart';
import 'catalog_query.dart';

/// Uses the persistent catalog index; never reads audio or cover blobs.
final _indexes = Expando<_LocalSimilarityIndex>();

class _LocalSimilarityIndex {
  Future<void>? ready;
  int generation = -1;
  final results = <String, List<String>>{};
  final jobs = <String, Future<List<String>>>{};
  Future<void> setup(LibraryStore store) => ready ??= _setup(store);
  Future<void> _setup(LibraryStore store) async {
    final db = store.database;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS local_similarity_revision(id INTEGER PRIMARY KEY CHECK(id=1),generation INTEGER NOT NULL)',
    );
    await db.execute(
      'INSERT OR IGNORE INTO local_similarity_revision VALUES(1,0)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS local_similarity_results(cache_key TEXT PRIMARY KEY,generation INTEGER NOT NULL,payload TEXT NOT NULL,updated_at INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS playlist_entries_track_idx ON playlist_entries(track_id,playlist_id)',
    );
    for (final table in [
      'catalog_search',
      'playlist_entries',
      'favorites',
      'local_sources',
      'local_source_tracks',
      'cloud_sources',
      'tracks',
    ]) {
      for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
        await db.execute(
          'CREATE TRIGGER IF NOT EXISTS local_similarity_${table}_$event AFTER $event ON $table BEGIN UPDATE local_similarity_revision SET generation=generation+1 WHERE id=1; END',
        );
      }
    }
  }
}

Future<List<String>> localSimilarArtists(
  LibraryStore store,
  String artist, {
  List<String> additionalGenres = const [],
}) async {
  final index = _indexes[store] ??= _LocalSimilarityIndex();
  await index.setup(store);
  final revision =
      (await store.database.query('local_similarity_revision'))
              .single['generation']
          as int;
  if (index.generation != revision) {
    index.generation = revision;
    index.results.clear();
  }
  final key = artistNameKey(artist);
  final cacheKey = '$key|${jsonEncode(additionalGenres)}';
  final saved = index.results.remove(cacheKey);
  if (saved != null) {
    index.results[cacheKey] = saved;
    return List.of(saved);
  }
  final jobKey = '$revision:$cacheKey';
  return List.of(
    await index.jobs.putIfAbsent(
      jobKey,
      () =>
          _loadSimilar(
            store,
            index,
            key,
            cacheKey,
            revision,
            additionalGenres,
          ).whenComplete(() {
            index.jobs.remove(jobKey);
          }),
    ),
  );
}

Future<List<String>> _loadSimilar(
  LibraryStore store,
  _LocalSimilarityIndex index,
  String key,
  String cacheKey,
  int revision,
  List<String> additionalGenres,
) async {
  final persisted = await store.database.query(
    'local_similarity_results',
    columns: ['payload'],
    where: 'cache_key=? AND generation=?',
    whereArgs: [cacheKey, revision],
  );
  if (persisted.isNotEmpty) {
    try {
      return (jsonDecode(persisted.single['payload'] as String) as List)
          .cast<String>();
    } catch (_) {
      /* Rebuild an invalid optional cache. */
    }
  }
  // Materialize visibility once, then join precomputed sets instead of running
  // correlated genre/playlist subqueries for each track and artist.
  final rows = await store.database.rawQuery(
    """
    WITH visible AS MATERIALIZED (
      SELECT c.* FROM tracks t INDEXED BY tracks_catalog_read_idx
      JOIN catalog_search c ON c.track_id=t.id WHERE ${catalogVisibility('t')}
    ), seed AS MATERIALIZED (
      SELECT * FROM visible WHERE EXISTS (SELECT 1 FROM json_each(artists) WHERE value=?)
    ), seed_genres AS MATERIALIZED (
      SELECT DISTINCT lower(trim(g.value)) AS genre FROM seed,json_each(seed.genres) g
      UNION SELECT lower(trim(value)) FROM json_each(?)
    ), matching_genres AS MATERIALIZED (
      SELECT DISTINCT c.track_id FROM visible c,json_each(c.genres) g
      JOIN seed_genres s ON lower(trim(g.value))=s.genre WHERE s.genre!=''
    ), shared AS MATERIALIZED (
      SELECT DISTINCT e.playlist_id FROM playlist_entries e JOIN seed ON seed.track_id=e.track_id
    ), matching_playlists AS MATERIALIZED (
      SELECT DISTINCT e.track_id FROM playlist_entries e JOIN shared s ON e.playlist_id=s.playlist_id
    ), seed_year AS MATERIALIZED (SELECT avg(year) AS year FROM seed WHERE year>0)
    SELECT a.value AS name,
      MAX(CASE WHEN g.track_id IS NOT NULL THEN 100 ELSE 0 END) AS genre_score,
      MAX(CASE WHEN p.track_id IS NOT NULL THEN 20 ELSE 0 END) AS affinity,
      MAX(CASE WHEN c.year>0 AND abs(c.year-y.year)<=10 THEN 5 ELSE 0 END) AS era,
      MAX(CASE WHEN f.track_id IS NOT NULL THEN 1 ELSE 0 END) AS favorite
    FROM visible c,json_each(c.artists) a CROSS JOIN seed_year y
    LEFT JOIN matching_genres g ON g.track_id=c.track_id
    LEFT JOIN matching_playlists p ON p.track_id=c.track_id
    LEFT JOIN favorites f ON f.track_id=c.track_id
    WHERE a.value!=? AND a.value!=''
    GROUP BY a.value HAVING genre_score>0 OR affinity>0
    ORDER BY genre_score+affinity+era+favorite DESC,name LIMIT 100
    """,
    [key, jsonEncode(additionalGenres), key],
  );
  final result = rows.map((r) => r['name'] as String).toList();
  await store.database.rawInsert(
    'INSERT OR REPLACE INTO local_similarity_results VALUES(?,?,?,?)',
    [
      cacheKey,
      revision,
      jsonEncode(result),
      DateTime.now().millisecondsSinceEpoch,
    ],
  );
  await store.database.execute(
    'DELETE FROM local_similarity_results WHERE cache_key NOT IN (SELECT cache_key FROM local_similarity_results ORDER BY updated_at DESC LIMIT 100)',
  );
  // A library edit while the query was running must not populate a newer cache.
  if (index.generation == revision) index.results[cacheKey] = result;
  if (index.results.length > 100) {
    index.results.remove(index.results.keys.first);
  }
  return List.of(result);
}
