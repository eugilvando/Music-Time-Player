import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/library/lastfm_profile.dart';
import 'package:music_time/presentation/storage_settings.dart';
import 'package:music_time/presentation/sources_dialog.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;

void main() {
  testWidgets(
    'Perfil Last.fm revisa ausentes antes de adicionar favoritos sem scrobbling',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'lastfm.profile_user': 'fixture-user',
      });
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      await tester.runAsync(
        () => store.addTracks([
          const Track(
            id: 'a',
            title: 'Canção',
            artist: 'Artista',
            localPath: 'fixture.mp3',
          ),
        ]),
      );
      final vault = MemoryVault();
      await vault.write('lastfm.api_key', 'fixture-key');
      final provider = ProviderConnections(
        await SharedPreferences.getInstance(),
        store,
        vault: vault,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'lovedtracks': {
                'track': [
                  {
                    'name': 'Canção',
                    'artist': {'name': 'Artista'},
                  },
                  {
                    'name': 'Ausente',
                    'artist': {'name': 'Artista'},
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProviderSettingsPage(
              providers: provider,
              onlyMicrosoft: false,
              onImported: () {},
            ),
          ),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 350));
      }

      await settle();
      await tester.scrollUntilVisible(
        find.text('Avançado'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Avançado'));
      await tester.pumpAndSettle();
      expect(find.text('Obter chave da API Last.fm'), findsOneWidget);
      final button = find.widgetWithText(OutlinedButton, 'Importar favoritos');
      await tester.scrollUntilVisible(
        button,
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(button);
      for (
        var i = 0;
        i < 15 && find.text('Revisar importação').evaluate().isEmpty;
        i++
      ) {
        await settle();
      }
      expect(provider.error, isNull);
      expect(find.text('Revisar importação'), findsOneWidget);
      await tester.tap(find.text('Remover da importação'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Importar faixas revisadas'));
      await settle();
      expect(find.text('Importar dados do Last.fm?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Importar'));
      for (var i = 0; i < 15 && provider.busy; i++) {
        await settle();
      }
      expect(provider.error, isNull);
      expect((await tester.runAsync(store.favoriteIds))!, {'a'});
      expect((await tester.runAsync(store.history))!, isEmpty);
      expect((await tester.runAsync(store.scrobbleStatus))!, isEmpty);
      expect(await vault.read('lastfm.session'), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      await tester.runAsync(store.close);
    },
  );
  test(
    'Last.fm lê favoritos paginados sem sessão, assinatura ou secret',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.method, 'GET');
        expect(request.url.queryParameters.containsKey('sk'), false);
        expect(request.url.queryParameters.containsKey('api_sig'), false);
        return http.Response(
          jsonEncode({
            'lovedtracks': {
              '@attr': {'totalPages': '2'},
              'track': [
                {
                  'name': 'Faixa $requests',
                  'artist': {'name': 'Artista'},
                },
              ],
            },
          }),
          200,
        );
      });
      addTearDown(client.close);
      final rows = await LastFmClient(
        client,
        apiKey: 'fixture',
        apiSecret: '',
      ).profileTracks('user', loved: true);
      expect(rows.map((t) => t.title), ['Faixa 1', 'Faixa 2']);
      expect(requests, 2);
    },
  );
  test('Recentes preservam data e ordem e não importam now playing', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'recenttracks': {
            'track': [
              {
                'name': 'Agora',
                'artist': {'#text': 'A'},
                '@attr': {'nowplaying': 'true'},
              },
              {
                'name': 'Antes',
                'artist': {'#text': 'A'},
                'album': {'#text': 'Disco'},
                'date': {'uts': '1000'},
              },
            ],
          },
        }),
        200,
      ),
    );
    addTearDown(client.close);
    final rows = await LastFmClient(
      client,
      apiKey: 'fixture',
      apiSecret: '',
    ).profileTracks('user', loved: false);
    expect(rows.single.title, 'Antes');
    expect(rows.single.album, 'Disco');
    expect(rows.single.playedAt!.millisecondsSinceEpoch, 1000000);
  });
  test('Correspondência exata ignora acentos mas mantém versões ambíguas', () {
    const tracks = [
      Track(id: 'a', title: 'Canção', artist: 'Artista', album: 'Estúdio'),
      Track(id: 'b', title: 'Canção', artist: 'Artista', album: 'Ao vivo'),
    ];
    final report = matchLastFmProfile((
      [
        const LastFmTrack('CANCAO', 'ARTISTA', 'Estudio', null),
        const LastFmTrack('Canção', 'Artista', '', null),
        const LastFmTrack('Outra', 'Artista', '', null),
      ],
      tracks,
    ));
    expect(report.ids, ['a']);
    expect(report.unresolved, 2);
    expect(report.entries[1].candidates, ['a', 'b']);
  });
  test('Erro de chave Last.fm não retorna resultado parcial', () async {
    final client = MockClient((_) async => http.Response('{"error":10}', 200));
    addTearDown(client.close);
    await expectLater(
      LastFmClient(
        client,
        apiKey: 'fixture',
        apiSecret: '',
      ).profileTracks('user', loved: true),
      throwsA(isA<LastFmException>()),
    );
  });
  test(
    'Limpeza mede apenas arquivos pertencentes ao cache e preserva originais',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'music-time-cache-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/cached.jpg').writeAsBytes([1, 2, 3]);
      final original = await File('${root.path}/original.mp3')
          .writeAsBytes([4, 5]);
      final sub = await Directory('${root.path}/music').create();
      await File('${sub.path}/cached.jpg').writeAsBytes([6]);
      bool accepts(String name) => name == 'cached.jpg';
      expect(await ownedCacheFiles(root, accepts: accepts), 3);
      expect(await ownedCacheFiles(root, accepts: accepts, clear: true), 3);
      expect(await original.exists(), true);
      expect(await File('${sub.path}/cached.jpg').exists(), true);
      expect(storageSize(1024), '1.0 KiB');
    },
  );
}
