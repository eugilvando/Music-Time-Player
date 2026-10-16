import 'dart:convert';

import '../infrastructure/lastfm.dart';
import '../persistence/library_store.dart';
import 'catalog.dart';

class ArtistSimilarity {
  ArtistSimilarity(this.store, this.api);
  final LibraryStore store;
  final Future<LastFmClient> Function() api;
  final _jobs = <String, Future<List<String>>>{};

  Future<List<String>> names(String artist, {bool offline = false}) {
    final key = artistNameKey(artist);
    return _jobs.putIfAbsent(
      key,
      () => _load(artist, offline).whenComplete(() {
        _jobs.remove(key);
      }),
    );
  }

  Future<List<String>> _load(String artist, bool offline) async {
    final db = store.database;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS artist_similarity_cache(artist TEXT PRIMARY KEY,names TEXT NOT NULL,updated_at TEXT NOT NULL)',
    );
    final rows = await db.query(
      'artist_similarity_cache',
      where: 'artist=?',
      whereArgs: [artistNameKey(artist)],
    );
    final row = rows.firstOrNull;
    final cached = row == null
        ? <String>[]
        : (jsonDecode(row['names'] as String) as List).cast<String>();
    final fresh =
        row != null &&
        DateTime.now().toUtc().difference(
              DateTime.parse(row['updated_at'] as String),
            ) <
            const Duration(days: 7);
    if (offline || fresh) return cached;
    try {
      final client = await api();
      final body = await client
          .readProfile('artist.getSimilar', {
            'artist': artist,
            'limit': '100',
            'autocorrect': '0',
          })
          .timeout(const Duration(seconds: 6));
      final raw = body['similarartists']?['artist'];
      final values =
          (raw is List
                  ? raw
                  : raw is Map
                  ? [raw]
                  : [])
              .whereType<Map>()
              .map((r) => r['name'])
              .whereType<String>()
              .where((n) => n.trim().isNotEmpty)
              .toSet()
              .toList();
      await db.rawInsert(
        'INSERT OR REPLACE INTO artist_similarity_cache VALUES(?,?,?)',
        [
          artistNameKey(artist),
          jsonEncode(values),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      return values;
    } catch (_) {
      return cached;
    }
  }
}
