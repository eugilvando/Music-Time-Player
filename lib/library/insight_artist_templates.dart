import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/track.dart';
import '../infrastructure/lastfm.dart';
import '../persistence/library_store.dart';
import 'artist_selection.dart';
import 'artist_similarity.dart';
import 'catalog.dart';
import 'lastfm_profile.dart';
import 'listening_insights.dart';
import 'm3u8.dart';

PlaylistImportReport artistPeriodPlaylist(
  (ListeningReport, List<Track>, String, int) work,
) => matchLastFmProfile((
  work.$1.tracks
      .where((r) => artistNameKey(r.artist) == artistNameKey(work.$3))
      .take(work.$4)
      .map((r) => LastFmTrack(r.title, r.artist, r.album, null))
      .toList(),
  work.$2,
));

class InsightArtistTemplates {
  InsightArtistTemplates(this.store, this.api);
  final LibraryStore store;
  final Future<LastFmClient> Function() api;
  late final similarity = ArtistSimilarity(store, api);

  Future<PlaylistImportReport> prepare({
    required String criterion,
    required String artist,
    required ListeningReport report,
    required List<Track> catalog,
    required int limit,
    bool offline = false,
  }) async {
    if (artist.trim().isEmpty ||
        limit < 1 ||
        limit > 100 ||
        !{'artist_period', 'artist_radio', 'artist_top'}.contains(criterion)) {
      throw ArgumentError('Invalid artist selection');
    }
    if (criterion == 'artist_period') {
      return compute(artistPeriodPlaylist, (report, catalog, artist, limit));
    }
    if (criterion == 'artist_radio') {
      final similar = await similarity.names(artist, offline: offline);
      final tracks = await compute(prepareArtistSelection, (
        tracks: catalog,
        artist: artist,
        count: limit,
        radio: true,
        similar: similar,
      ));
      if (tracks.isEmpty) throw StateError('No known similar artists');
      return PlaylistImportReport([
        for (var i = 0; i < tracks.length; i++)
          PlaylistImportEntry(
            i + 1,
            tracks[i].id,
            [tracks[i].id],
            [],
            title: tracks[i].title,
            artist: tracks[i].artist,
          ),
      ]);
    }
    final top = await topTracks(artist, offline: offline);
    final matched = await compute(matchLastFmProfile, (top, catalog));
    return PlaylistImportReport(
      matched.entries
          .where((e) => e.candidates.isNotEmpty)
          .take(limit)
          .toList(),
    );
  }

  final _topJobs = <String, Future<List<LastFmTrack>>>{};
  Future<List<LastFmTrack>> topTracks(String artist, {bool offline = false}) {
    final key = '${artistNameKey(artist)}|$offline';
    return _topJobs.putIfAbsent(
      key,
      () => _loadTopTracks(artist, offline: offline).whenComplete(() {
        _topJobs.remove(key);
      }),
    );
  }

  Future<List<LastFmTrack>> _loadTopTracks(
    String artist, {
    bool offline = false,
  }) async {
    await store.database.execute(
      'CREATE TABLE IF NOT EXISTS lastfm_profile_cache(user TEXT NOT NULL,kind TEXT NOT NULL,payload TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(user,kind))',
    );
    const kind = 'artist.top.v1';
    final key = artistNameKey(artist);
    final rows = await store.database.query(
      'lastfm_profile_cache',
      where: 'user=? AND kind=?',
      whereArgs: [key, kind],
    );
    final old = rows.firstOrNull;
    final fresh =
        old != null &&
        DateTime.now().toUtc().difference(
              DateTime.parse(old['updated_at'] as String),
            ) <
            const Duration(days: 7);
    Map<String, dynamic>? body;
    if (offline || fresh) {
      if (old != null) {
        body = jsonDecode(old['payload'] as String) as Map<String, dynamic>;
      }
    } else {
      try {
        body = await (await api())
            .readProfile('artist.getTopTracks', {
              'artist': artist,
              'limit': '200',
              'autocorrect': '0',
            })
            .timeout(const Duration(seconds: 10));
        await store.database.insert('lastfm_profile_cache', {
          'user': key,
          'kind': kind,
          'payload': jsonEncode(body),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await store.database.rawDelete(
          "DELETE FROM lastfm_profile_cache WHERE kind=? AND rowid NOT IN (SELECT rowid FROM lastfm_profile_cache WHERE kind=? ORDER BY updated_at DESC LIMIT 50)",
          [kind, kind],
        );
      } catch (_) {
        if (old == null) rethrow;
        body = jsonDecode(old['payload'] as String) as Map<String, dynamic>;
      }
    }
    if (body == null) throw StateError('No cached artist ranking');
    final raw = body['toptracks']?['track'];
    return [
      for (final row
          in (raw is List
                  ? raw
                  : raw is Map
                  ? [raw]
                  : [])
              .whereType<Map>())
        if (row['name'] is String)
          LastFmTrack(
            row['name'] as String,
            row['artist'] is Map && row['artist']['name'] is String
                ? row['artist']['name'] as String
                : artist,
            '',
            null,
          ),
    ];
  }
}
