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
  Future<void> setup(LibraryStore store) => ready ??= _setup(store);
  Future<void> _setup(LibraryStore store) async {
    final db = store.database;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS local_similarity_revision(id INTEGER PRIMARY KEY CHECK(id=1),generation INTEGER NOT NULL)',
    );
    await db.execute(
      'INSERT OR IGNORE INTO local_similarity_revision VALUES(1,0)',
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
  final rows = await store.database.rawQuery(
    """
    WITH seed AS (
      SELECT c.* FROM catalog_search c JOIN tracks t ON t.id=c.track_id
      WHERE ${catalogVisibility('t')}
        AND EXISTS (SELECT 1 FROM json_each(c.artists) WHERE value=?)
    ), seed_genres AS (
      SELECT lower(trim(g.value)) AS genre FROM seed,json_each(seed.genres) g
      UNION SELECT lower(trim(value)) FROM json_each(?)
    ), shared AS (
      SELECT DISTINCT e.playlist_id FROM playlist_entries e JOIN seed ON seed.track_id=e.track_id
    )
    SELECT a.value AS name,
      MAX(CASE WHEN EXISTS (SELECT 1 FROM json_each(c.genres) g JOIN seed_genres s ON lower(trim(g.value))=s.genre WHERE s.genre!='') THEN 100 ELSE 0 END) AS genre_score,
      MAX(CASE WHEN EXISTS (SELECT 1 FROM playlist_entries e JOIN shared s ON e.playlist_id=s.playlist_id WHERE e.track_id=c.track_id) THEN 20 ELSE 0 END) AS affinity,
      MAX(CASE WHEN c.year>0 AND abs(c.year-(SELECT avg(year) FROM seed WHERE year>0))<=10 THEN 5 ELSE 0 END) AS era,
      MAX(CASE WHEN EXISTS (SELECT 1 FROM favorites f WHERE f.track_id=c.track_id) THEN 1 ELSE 0 END) AS favorite
    FROM catalog_search c JOIN tracks t ON t.id=c.track_id, json_each(c.artists) a
    WHERE ${catalogVisibility('t')} AND a.value!=? AND a.value!=''
    GROUP BY a.value HAVING genre_score>0 OR affinity>0
    ORDER BY genre_score+affinity+era+favorite DESC,name LIMIT 100
  """,
    [key, jsonEncode(additionalGenres), key],
  );
  final result = rows.map((r) => r['name'] as String).toList();
  index.results[cacheKey] = result;
  if (index.results.length > 100) {
    index.results.remove(index.results.keys.first);
  }
  return List.of(result);
}
