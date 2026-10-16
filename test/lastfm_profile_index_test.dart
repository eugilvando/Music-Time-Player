import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/library/lastfm_profile_index.dart';
import 'package:music_time/persistence/library_store.dart';

class ProfileFixture extends LastFmClient {
  ProfileFixture()
    : super(
        MockClient((_) async => http.Response('', 500)),
        apiKey: 'fixture',
        apiSecret: '',
      );
  final calls = <String>[];
  Completer<void>? gate;
  String? failure;
  List<LastFmTrack> rows(String kind) {
    if (kind == failure) throw const LastFmException(29);
    return [LastFmTrack(kind, 'Artist', 'Album', DateTime.utc(2026, 10, 14))];
  }

  @override
  Future<List<LastFmTrack>> profileTracks(
    String user, {
    required bool loved,
  }) async {
    final kind = loved ? 'loved' : 'recent';
    calls.add(kind);
    await gate?.future;
    return rows(kind);
  }

  @override
  Future<List<LastFmTrack>> topTracks(String user, String period) async {
    calls.add(period);
    return rows(period);
  }
}

void main() {
  test(
    'início agenda com atraso e refresh simultâneo compartilha a consulta',
    () async {
      SharedPreferences.setMockInitialValues({
        'lastfm.profile_user': 'fixture',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = await LibraryStore.open(':memory:');
      final api = ProfileFixture()..gate = Completer<void>();
      final index = LastFmProfileIndex(prefs, store, api: () async => api);
      addTearDown(() async {
        index.dispose();
        api.client.close();
        await store.close();
      });
      expect(index.delaySeconds, 30);
      index.schedule();
      expect(api.calls, isEmpty);
      final first = index.refresh();
      expect(identical(first, index.refresh()), isTrue);
      api.gate!.complete();
      await first;
      expect(api.calls, ['loved', 'recent', 'overall', '1month']);
      expect(index.counts.values, everyElement(1));
      expect(index.updatedAt, isNotNull);
      final reopened = LastFmProfileIndex(prefs, store, api: () async => api);
      addTearDown(reopened.dispose);
      expect((await reopened.tracks('overall')).single.title, 'overall');
      expect(api.calls.length, 4);
      expect(await store.database.query('favorites'), isEmpty);
      expect(await store.database.query('history'), isEmpty);
      expect(await store.database.query('playlists'), isEmpty);
    },
  );

  test(
    'falha e offline preservam snapshot anterior sem novas requisições',
    () async {
      SharedPreferences.setMockInitialValues({
        'lastfm.profile_user': 'fixture',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = await LibraryStore.open(':memory:');
      final api = ProfileFixture();
      final index = LastFmProfileIndex(prefs, store, api: () async => api);
      addTearDown(() async {
        index.dispose();
        api.client.close();
        await store.close();
      });
      await index.refresh();
      final before = index.updatedAt;
      api.failure = '1month';
      await index.refresh();
      expect(index.updatedAt, before);
      expect(index.status, contains('preservados'));
      expect((await index.cached('loved'))!.single.title, 'loved');
      await prefs.setBool('visual.offline_only', true);
      final calls = api.calls.length;
      await index.refresh();
      expect(api.calls.length, calls);
      expect((await index.tracks('1month')).single.title, '1month');
    },
  );

  test(
    'desativar ou descartar agendamento impede leitura automática',
    () async {
      SharedPreferences.setMockInitialValues({
        'lastfm.profile_user': 'fixture',
        'lastfm.index_auto': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final store = await LibraryStore.open(':memory:');
      final api = ProfileFixture();
      final index = LastFmProfileIndex(prefs, store, api: () async => api);
      index.schedule(delay: Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(api.calls, isEmpty);
      await prefs.setBool('lastfm.index_auto', true);
      index.schedule(delay: Duration.zero);
      index.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(api.calls, isEmpty);
      api.client.close();
      await store.close();
    },
  );
}
