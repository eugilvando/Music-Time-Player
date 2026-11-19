import 'dart:convert';

import '../infrastructure/brainz.dart';
import '../persistence/library_store.dart';
import 'catalog.dart';

class MusicBrainzMetadata {
  MusicBrainzMetadata(this.store, this.transport, this.enabled);
  final LibraryStore store;
  final BrainzTransport transport;
  final bool Function() enabled;
  final _jobs = <String, Future<List<String>>>{};
  Future<List<String>> artistGenres(String artist) => _jobs.putIfAbsent(
    artistNameKey(artist),
    () => _load(artist).whenComplete(() {
      _jobs.remove(artistNameKey(artist));
    }),
  );
  Future<List<String>> _load(String artist) async {
    await store.database.execute(
      'CREATE TABLE IF NOT EXISTS musicbrainz_artist_cache(artist TEXT PRIMARY KEY,mbid TEXT,genres TEXT NOT NULL,updated_at INTEGER NOT NULL)',
    );
    final key = artistNameKey(artist);
    final rows = await store.database.query(
      'musicbrainz_artist_cache',
      where: 'artist=?',
      whereArgs: [key],
    );
    final cached = rows.isEmpty
        ? <String>[]
        : (jsonDecode(rows.first['genres'] as String) as List).cast<String>();
    if (!enabled() ||
        rows.isNotEmpty &&
            DateTime.now().millisecondsSinceEpoch -
                    (rows.first['updated_at'] as int) <
                const Duration(days: 30).inMilliseconds) {
      return cached;
    }
    try {
      // Quoted search, followed by exact normalized name and unique match checks.
      final escaped = artist.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      final result = await transport.request(
        '/ws/2/artist/',
        query: {'query': 'artist:"$escaped"', 'fmt': 'json', 'limit': '10'},
      );
      final matches = (result['artists'] as List? ?? [])
          .whereType<Map>()
          .where(
            (r) =>
                artistNameKey('${r['name']}') == key &&
                int.tryParse('${r['score']}') == 100,
          )
          .toList();
      String? id;
      var genres = <String>[];
      if (matches.length == 1) {
        id = matches.single['id'] as String;
        final detail = await transport.request(
          '/ws/2/artist/$id',
          query: {'fmt': 'json', 'inc': 'genres'},
        );
        genres = (detail['genres'] as List? ?? [])
            .whereType<Map>()
            .map((g) => '${g['name']}')
            .where((g) => g.isNotEmpty)
            .toList();
      }
      await store.database.rawInsert(
        'INSERT OR REPLACE INTO musicbrainz_artist_cache VALUES(?,?,?,?)',
        [key, id, jsonEncode(genres), DateTime.now().millisecondsSinceEpoch],
      );
      return genres;
    } catch (_) {
      return cached;
    }
  }
}
