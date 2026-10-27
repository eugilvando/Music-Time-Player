import 'dart:async';
import 'dart:convert';

import '../infrastructure/lastfm.dart';
import '../persistence/library_store.dart';
import 'catalog.dart';

enum SimilarityIssue { none, offline, missingKey, network, noResults }

class SimilarityResult {
  const SimilarityResult(
    this.names, {
    this.cached = false,
    this.issue = SimilarityIssue.none,
  });
  final List<String> names;
  final bool cached;
  final SimilarityIssue issue;
}

class ArtistSimilarity {
  ArtistSimilarity(
    this.store,
    this.api, {
    this.requestTimeout = const Duration(seconds: 12),
  });
  final LibraryStore store;
  final Future<LastFmClient> Function() api;
  final Duration requestTimeout;
  final _jobs = <String, Future<SimilarityResult>>{};

  Future<List<String>> names(String artist, {bool offline = false}) async =>
      (await lookup(artist, offline: offline)).names;

  Future<SimilarityResult> lookup(
    String artist, {
    bool offline = false,
    bool refresh = false,
  }) {
    // Offline callers must never join an in-flight online request.
    final key = '${artistNameKey(artist)}:$offline:$refresh';
    return _jobs.putIfAbsent(
      key,
      () => _load(artist, offline, refresh).whenComplete(() {
        _jobs.remove(key);
      }),
    );
  }

  Future<SimilarityResult> _load(
    String artist,
    bool offline,
    bool refresh,
  ) async {
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
    var cached = <String>[];
    DateTime? updated;
    try {
      if (row != null) {
        cached = (jsonDecode(row['names'] as String) as List)
            .cast<String>()
            .toList();
        updated = DateTime.tryParse(row['updated_at'] as String);
      }
    } catch (_) {
      /* A malformed optional cache is rebuilt, not shown as a failure. */
    }
    final age = updated == null
        ? null
        : DateTime.now().toUtc().difference(updated);
    final fresh =
        age != null &&
        !age.isNegative &&
        age <
            (cached.isEmpty
                ? const Duration(minutes: 15)
                : const Duration(days: 7));
    if (offline) {
      return SimilarityResult(
        cached,
        cached: row != null,
        issue: SimilarityIssue.offline,
      );
    }
    if (fresh && !refresh) {
      return SimilarityResult(
        cached,
        cached: true,
        issue: cached.isEmpty
            ? SimilarityIssue.noResults
            : SimilarityIssue.none,
      );
    }
    try {
      final client = await api().timeout(requestTimeout);
      if (client.apiKey.trim().isEmpty) {
        return SimilarityResult(
          cached,
          cached: row != null,
          issue: SimilarityIssue.missingKey,
        );
      }
      Map<String, dynamic>? body;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          body = await client
              .readProfile('artist.getSimilar', {
                'artist': artist.trim(),
                'limit': '100',
                'autocorrect': '0',
              })
              .timeout(requestTimeout);
          break;
        } catch (error) {
          final retry =
              error is TimeoutException ||
              error is LastFmException && {11, 16}.contains(error.code);
          if (attempt == 1 || !retry) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
      final raw = body?['similarartists']?['artist'];
      if (raw != null && raw is! List && raw is! Map) {
        throw const FormatException('Invalid similar artists');
      }
      if (body?['similarartists'] is! Map) {
        throw const FormatException('Missing similar artists');
      }
      final names = <String, String>{};
      for (final entry
          in (raw is List
                  ? raw
                  : raw is Map
                  ? [raw]
                  : [])
              .whereType<Map>()) {
        final name = entry['name'];
        if (name is String &&
            name.trim().isNotEmpty &&
            artistNameKey(name) != artistNameKey(artist)) {
          names.putIfAbsent(artistNameKey(name), () => name.trim());
        }
      }
      final values = names.values.toList();
      // An empty response must not destroy useful older recommendations.
      if (values.isEmpty && cached.isNotEmpty) {
        return SimilarityResult(
          cached,
          cached: true,
          issue: SimilarityIssue.noResults,
        );
      }
      try {
        await db.rawInsert(
          'INSERT OR REPLACE INTO artist_similarity_cache VALUES(?,?,?)',
          [
            artistNameKey(artist),
            jsonEncode(values),
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      } catch (_) {
        // An optional cache write must not discard a valid remote result.
      }
      return SimilarityResult(
        values,
        issue: values.isEmpty
            ? SimilarityIssue.noResults
            : SimilarityIssue.none,
      );
    } catch (error) {
      final issue = error is LastFmException && {10, 26}.contains(error.code)
          ? SimilarityIssue.missingKey
          : SimilarityIssue.network;
      return SimilarityResult(cached, cached: row != null, issue: issue);
    }
  }
}
