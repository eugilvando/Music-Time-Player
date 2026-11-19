import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../infrastructure/brainz.dart';
import '../infrastructure/lastfm.dart';
import 'listening_insights.dart';

class AlternativeInsights extends ListeningInsightsRepository {
  AlternativeInsights(
    super.store,
    super.api, {
    required super.source,
    this.transport,
    this.allowed,
  });
  final BrainzTransport? transport;
  final bool Function()? allowed;
  @override
  Future<ListeningReport> load({
    required String user,
    required String period,
    required DateTime from,
    required DateTime until,
    required ListeningRequest request,
    ListeningReport? resume,
    int pageBudget = 250,
    void Function(int, int)? onProgress,
  }) async {
    request.check();
    if (!until.isAfter(from)) throw ArgumentError('Invalid period');
    final previous = from.millisecondsSinceEpoch == 0
        ? from
        : from.subtract(until.difference(from));
    final events = <LastFmTrack>[];
    var complete = true,
        invalid = 0,
        cursor =
            resume?.nextPage ?? ((until.millisecondsSinceEpoch + 999) ~/ 1000);
    if (source == 'local') {
      final rows = await store.database.rawQuery(
        'SELECT t.title,t.artist,t.album,h.started_at FROM history h JOIN tracks t ON t.id=h.track_id WHERE h.listened_ms>0 AND h.started_at>=? AND h.started_at<? ORDER BY h.started_at',
        [previous.toUtc().toIso8601String(), until.toUtc().toIso8601String()],
      );
      for (final row in rows) {
        events.add(
          LastFmTrack(
            row['title'] as String,
            row['artist'] as String,
            row['album'] as String,
            DateTime.tryParse(row['started_at'] as String),
          ),
        );
      }
    } else {
      // Only bounded period reads; never scrape a user's complete ListenBrainz history.
      if (from.millisecondsSinceEpoch == 0 ||
          until.difference(from) > const Duration(days: 366)) {
        throw const ListenBrainzConnectionFailure(
          'ListenBrainz: selecione um período de até 365 dias. A leitura de todo o histórico exige a exportação do serviço.',
        );
      }
      if (resume != null &&
          (resume.user != user ||
              resume.from != from ||
              resume.until != until)) {
        throw ArgumentError('Invalid resume');
      }
      complete = false;
      for (var page = 0; page < math.min(pageBudget, 10); page++) {
        request.check();
        if (allowed != null && !allowed!()) throw const BrainzFailure(0);
        final body = await transport!.request(
          '/1/user/${Uri.encodeComponent(user)}/listens',
          query: {'max_ts': '$cursor', 'count': '100'},
          guard: () => !request.cancelled && (allowed?.call() ?? true),
        );
        request.check();
        final payload = body['payload'];
        if (payload is! Map || payload['listens'] is! List) {
          throw const FormatException('Invalid ListenBrainz history');
        }
        final rows = payload['listens'] as List;
        if (rows.isEmpty) {
          complete = true;
          break;
        }
        var oldest = cursor;
        for (final row in rows) {
          if (row is! Map ||
              row['listened_at'] is! int ||
              row['track_metadata'] is! Map) {
            invalid++;
            continue;
          }
          final stamp = row['listened_at'] as int;
          oldest = math.min(oldest, stamp);
          if (stamp >= cursor) {
            invalid++;
            continue;
          }
          final at = DateTime.fromMillisecondsSinceEpoch(
            stamp * 1000,
            isUtc: true,
          );
          if (at.isBefore(previous)) {
            complete = true;
            continue;
          }
          final m = row['track_metadata'] as Map;
          events.add(
            LastFmTrack(
              '${m['track_name'] ?? ''}',
              '${m['artist_name'] ?? ''}',
              '${m['release_name'] ?? ''}',
              at,
            ),
          );
        }
        if (oldest >= cursor) {
          throw const FormatException(
            'ListenBrainz pagination did not advance',
          );
        }
        cursor = oldest;
        onProgress?.call(page + 1, math.min(pageBudget, 10));
        if (complete || rows.length < 100) {
          complete = true;
          break;
        }
      }
    }
    request.check();
    final report = await compute(aggregateListening, (
      base: source == 'local' ? null : resume,
      user: user,
      from: from,
      until: until,
      previousFrom: previous,
      events: events,
      nextPage: cursor,
      totalPages: 0,
      complete: complete,
      invalid: invalid,
    ));
    request.check();
    await saveReport(user, period, report);
    return report;
  }
}
