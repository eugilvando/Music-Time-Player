import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../infrastructure/lastfm.dart';
import '../persistence/library_store.dart';
import 'catalog.dart';

class ListeningCancelled implements Exception {}

class ListeningRequest {
  bool cancelled = false;
  void check() {
    if (cancelled) throw ListeningCancelled();
  }
}

class ListeningRank {
  const ListeningRank(this.title, this.artist, this.album, this.count);
  final String title, artist, album;
  final int count;
  String get key => listeningTrackKey(artist, title);
  Map<String, Object?> toJson() => {
    'title': title,
    'artist': artist,
    'album': album,
    'count': count,
  };
  factory ListeningRank.fromJson(Map<String, dynamic> value) => ListeningRank(
    value['title'] as String,
    value['artist'] as String,
    value['album'] as String,
    value['count'] as int,
  );
}

String listeningTrackKey(String artist, String title) =>
    '${searchKey(artist.trim())}\u0000${searchKey(title.trim())}';

class ListeningReport {
  const ListeningReport({
    required this.user,
    required this.from,
    required this.until,
    required this.previousFrom,
    required this.updatedAt,
    required this.nextPage,
    required this.totalPages,
    required this.complete,
    required this.scrobbles,
    required this.previousScrobbles,
    required this.tracks,
    required this.artists,
    required this.albums,
    required this.days,
    required this.previousTracks,
    this.invalid = 0,
  });
  final String user;
  final DateTime from, until, previousFrom, updatedAt;
  final int nextPage, totalPages, scrobbles, previousScrobbles, invalid;
  final bool complete;
  final List<ListeningRank> tracks, artists, albums;
  final Map<String, int> days, previousTracks;
  Map<String, Object?> toJson() => {
    'user': user,
    'from': from.toIso8601String(),
    'until': until.toIso8601String(),
    'previousFrom': previousFrom.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'nextPage': nextPage,
    'totalPages': totalPages,
    'complete': complete,
    'scrobbles': scrobbles,
    'previousScrobbles': previousScrobbles,
    'invalid': invalid,
    'tracks': tracks.map((r) => r.toJson()).toList(),
    'artists': artists.map((r) => r.toJson()).toList(),
    'albums': albums.map((r) => r.toJson()).toList(),
    'days': days,
    'previousTracks': previousTracks,
  };
  factory ListeningReport.fromJson(Map<String, dynamic> v) => ListeningReport(
    user: v['user'] as String,
    from: DateTime.parse(v['from'] as String),
    until: DateTime.parse(v['until'] as String),
    previousFrom: DateTime.parse(v['previousFrom'] as String),
    updatedAt: DateTime.parse(v['updatedAt'] as String),
    nextPage: v['nextPage'] as int,
    totalPages: v['totalPages'] as int,
    complete: v['complete'] as bool,
    scrobbles: v['scrobbles'] as int,
    previousScrobbles: v['previousScrobbles'] as int,
    invalid: v['invalid'] as int,
    tracks: (v['tracks'] as List)
        .map((r) => ListeningRank.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
    artists: (v['artists'] as List)
        .map((r) => ListeningRank.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
    albums: (v['albums'] as List)
        .map((r) => ListeningRank.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
    days: Map<String, int>.from(v['days'] as Map),
    previousTracks: Map<String, int>.from(v['previousTracks'] as Map),
  );
}

typedef ListeningWork = ({
  ListeningReport? base,
  String user,
  DateTime from,
  DateTime until,
  DateTime previousFrom,
  List<LastFmTrack> events,
  int nextPage,
  int totalPages,
  bool complete,
  int invalid,
});

ListeningReport aggregateListening(ListeningWork work) {
  final base = work.base;
  final tracks = {for (final r in base?.tracks ?? <ListeningRank>[]) r.key: r};
  final artists = {
    for (final r in base?.artists ?? <ListeningRank>[]) searchKey(r.title): r,
  };
  final albums = {
    for (final r in base?.albums ?? <ListeningRank>[])
      listeningTrackKey(r.artist, r.title): r,
  };
  final days = Map<String, int>.of(base?.days ?? {});
  final previous = Map<String, int>.of(base?.previousTracks ?? {});
  var count = base?.scrobbles ?? 0, oldCount = base?.previousScrobbles ?? 0;
  void add(Map<String, ListeningRank> values, String key, ListeningRank rank) {
    final old = values[key];
    values[key] = ListeningRank(
      rank.title,
      rank.artist,
      old?.album.isNotEmpty == true ? old!.album : rank.album,
      (old?.count ?? 0) + 1,
    );
  }

  for (final event in work.events) {
    final at = event.playedAt;
    if (at == null ||
        at.isBefore(work.previousFrom) ||
        !at.isBefore(work.until)) {
      continue;
    }
    final key = listeningTrackKey(event.artist, event.title);
    if (at.isBefore(work.from)) {
      oldCount++;
      if (event.artist.trim().isNotEmpty && event.title.trim().isNotEmpty) {
        previous.update(key, (v) => v + 1, ifAbsent: () => 1);
      }
      continue;
    }
    count++;
    final local = at.toLocal();
    final day =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    days.update(day, (v) => v + 1, ifAbsent: () => 1);
    if (event.artist.trim().isNotEmpty) {
      add(
        artists,
        searchKey(event.artist),
        ListeningRank(event.artist, event.artist, '', 1),
      );
    }
    if (event.title.trim().isNotEmpty && event.artist.trim().isNotEmpty) {
      add(
        tracks,
        key,
        ListeningRank(event.title, event.artist, event.album, 1),
      );
    }
    if (event.album.trim().isNotEmpty && event.artist.trim().isNotEmpty) {
      add(
        albums,
        listeningTrackKey(event.artist, event.album),
        ListeningRank(event.album, event.artist, event.album, 1),
      );
    }
  }
  List<ListeningRank> sorted(Map<String, ListeningRank> values) =>
      values.values.toList()..sort((a, b) {
        final order = b.count.compareTo(a.count);
        return order != 0 ? order : a.key.compareTo(b.key);
      });
  return ListeningReport(
    user: work.user,
    from: work.from,
    until: work.until,
    previousFrom: work.previousFrom,
    updatedAt: DateTime.now().toUtc(),
    nextPage: work.nextPage,
    totalPages: work.totalPages,
    complete: work.complete,
    scrobbles: count,
    previousScrobbles: oldCount,
    invalid: (base?.invalid ?? 0) + work.invalid,
    tracks: sorted(tracks),
    artists: sorted(artists),
    albums: sorted(albums),
    days: days,
    previousTracks: previous,
  );
}

ListeningReport decodeListening(String text) =>
    ListeningReport.fromJson(jsonDecode(text) as Map<String, dynamic>);
String encodeListening(ListeningReport report) => jsonEncode(report.toJson());

class ListeningInsightsRepository {
  ListeningInsightsRepository(this.store, this.api);
  final LibraryStore store;
  final Future<LastFmClient> Function() api;
  final _sessionRefreshes = <String>{};
  final _reports = <String, ListeningReport>{};
  String selectedPeriod = '30', selectedTab = 'overview';
  DateTime? selectedFrom, selectedUntil;
  ListeningReport? peekCached(String user, String period) =>
      _reports[_key(user, period)];
  String _key(String user, String period) => '${user.toLowerCase()}|$period';
  bool beginAutomaticRefresh(String user, String period) =>
      _sessionRefreshes.add(_key(user, period));
  void remember(String user, String period, ListeningReport report) {
    final key = _key(user, period);
    _reports.remove(key);
    _reports[key] = report;
    while (_reports.length > 3) {
      _reports.remove(_reports.keys.first);
    }
  }

  Future<void> schema() => store.database.execute(
    'CREATE TABLE IF NOT EXISTS lastfm_profile_cache (user TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(user,kind))',
  );
  Future<ListeningReport?> cached(String user, String period) async {
    final memory = _reports[_key(user, period)];
    if (memory != null) return memory;
    await schema();
    var rows = await store.database.query(
      'lastfm_profile_cache',
      where: 'user=? AND kind=? AND length(CAST(payload AS BLOB))<=8388608',
      whereArgs: [user.toLowerCase(), 'insights.v1:$period'],
    );
    if (rows.isEmpty && !period.startsWith('custom:')) {
      rows = await store.database.query(
        'lastfm_profile_cache',
        where:
            'user=? AND kind LIKE ? AND length(CAST(payload AS BLOB))<=8388608',
        whereArgs: [
          user.toLowerCase(),
          'insights.v1:${period.split(':').first}:%',
        ],
        orderBy: 'updated_at DESC',
        limit: 1,
      );
    }
    if (rows.isEmpty) return null;
    try {
      final report = await compute(
        decodeListening,
        rows.single['payload'] as String,
      );
      if (report.user.toLowerCase() != user.toLowerCase()) return null;
      remember(user, period, report);
      return report;
    } catch (_) {
      return null;
    }
  }

  Future<ListeningReport> load({
    required String user,
    required String period,
    required DateTime from,
    required DateTime until,
    required ListeningRequest request,
    ListeningReport? resume,
    int pageBudget = 250,
    void Function(int page, int total)? onProgress,
  }) async {
    if (user.trim().isEmpty || !until.isAfter(from) || pageBudget < 1) {
      throw ArgumentError('Invalid listening request');
    }
    if (resume != null &&
        (resume.user.toLowerCase() != user.toLowerCase() ||
            resume.from != from ||
            resume.until != until)) {
      throw ArgumentError('Cannot resume another profile or period');
    }
    request.check();
    final client = await api();
    request.check();
    final previousFrom =
        resume?.previousFrom ??
        (from.millisecondsSinceEpoch == 0
            ? from
            : from.subtract(until.difference(from)));
    final events = <LastFmTrack>[];
    var page = resume?.nextPage ?? 1,
        pages = resume?.totalPages ?? 1,
        invalid = 0;
    final start = page;
    while (page <= pages && page - start < pageBudget) {
      request.check();
      Map<String, dynamic>? body;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          body = await client.readProfile('user.getRecentTracks', {
            'user': user,
            'page': '$page',
            'limit': '200',
            'from':
                '${(previousFrom.millisecondsSinceEpoch ~/ 1000 - 1).clamp(0, 9999999999)}',
            'to': '${(until.millisecondsSinceEpoch + 999) ~/ 1000}',
          });
          break;
        } on LastFmException catch (error) {
          if (!error.retryable || attempt == 2) rethrow;
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (attempt + 1)),
          );
          request.check();
        }
      }
      request.check();
      final section = body!['recenttracks'];
      if (section is! Map || section['@attr'] is! Map) {
        throw const FormatException('Missing Last.fm pagination');
      }
      final attr = section['@attr'] as Map;
      final receivedPage = int.tryParse('${attr['page']}');
      final receivedPages = int.tryParse('${attr['totalPages']}');
      if (receivedPage != page || receivedPages == null || receivedPages < 0) {
        throw const FormatException('Invalid Last.fm pagination');
      }
      if (page != 1 && receivedPages != pages) {
        throw const FormatException(
          'Last.fm history changed during pagination; refresh',
        );
      }
      pages = receivedPages;
      final raw = section['track'];
      if (raw != null && raw is! List && raw is! Map) {
        throw const FormatException('Invalid Last.fm tracks');
      }
      final rows = raw is List
          ? raw
          : raw is Map
          ? [raw]
          : const [];
      String name(Object? v) =>
          v is Map ? '${v['name'] ?? v['#text'] ?? ''}' : '${v ?? ''}';
      for (final row in rows) {
        if (row is! Map) {
          invalid++;
          continue;
        }
        if (row['@attr'] is Map && '${row['@attr']['nowplaying']}' == 'true') {
          continue;
        }
        final date = row['date'];
        final stamp = date is Map ? int.tryParse('${date['uts']}') : null;
        if (stamp == null) {
          invalid++;
          continue;
        }
        events.add(
          LastFmTrack(
            name(row['name']),
            name(row['artist']),
            name(row['album']),
            DateTime.fromMillisecondsSinceEpoch(stamp * 1000, isUtc: true),
          ),
        );
      }
      if (rows.isEmpty && page < pages) {
        throw const FormatException('Empty Last.fm page before end');
      }
      onProgress?.call(page, pages);
      page++;
      if (page <= pages) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    request.check();
    final report = await compute(aggregateListening, (
      base: resume,
      user: user,
      from: from,
      until: until,
      previousFrom: previousFrom,
      events: events,
      nextPage: page,
      totalPages: pages,
      complete: page > pages,
      invalid: invalid,
    ));
    request.check();
    final payload = await compute(encodeListening, report);
    request.check();
    if (utf8.encode(payload).length <= 8388608) {
      await schema();
      await store.database.transaction((txn) async {
        request.check();
        await txn.rawInsert(
          'INSERT OR REPLACE INTO lastfm_profile_cache(user,kind,payload,updated_at) VALUES(?,?,?,?)',
          [
            user.toLowerCase(),
            'insights.v1:$period',
            payload,
            report.updatedAt.toIso8601String(),
          ],
        );
        request.check();
        await txn.rawDelete(
          "DELETE FROM lastfm_profile_cache WHERE kind LIKE 'insights.v1:%' AND rowid NOT IN (SELECT rowid FROM lastfm_profile_cache WHERE kind LIKE 'insights.v1:%' ORDER BY updated_at DESC LIMIT 6)",
        );
        request.check();
      });
    }
    remember(user, period, report);
    return report;
  }
}
