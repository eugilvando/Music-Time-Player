import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;

import 'package:music_time/domain/track.dart';

void main() {
  for (final mode in ['success', 'failure', 'cancel']) {
    final fail = mode == 'failure', cancel = mode == 'cancel';
    test(
      'OneDrive subpastas sem caminho, páginas e resumo; modo=$mode',
      () async {
        const id = '00000000-0000-0000-0000-000000000001';
        SharedPreferences.setMockInitialValues({
          'microsoft.client_id': id,
          'microsoft.folder_path': '/drive/root:/Música',
          'microsoft.folder_name': 'Música',
          'microsoft.folder_selected': true,
          if (fail || cancel) 'microsoft.folder_id': 'music',
        });
        final prefs = await SharedPreferences.getInstance();
        final vault = MemoryVault();
        await vault.write(
          'microsoft.session',
          jsonEncode({
            'client_id': id,
            'access_token': 'fixture',
            'expires_at': '2099-01-01T00:00:00Z',
          }),
        );
        final store = await LibraryStore.open(':memory:');
        await store.addTracks([
          const Track(
            id: 'local',
            title: 'Local',
            artist: '',
            localPath: 'C:/original.mp3',
          ),
          const Track(
            id: 'onedrive:d:outside',
            title: 'Anterior',
            artist: '',
            sourceProvider: 'onedrive',
            sourceAccount: 'd',
            sourcePath: '/drive/root:/Outra',
            driveId: 'd',
            itemId: 'outside',
          ),
        ]);
        final requests = <String>[];
        final artwork = await File('assets/branding/icon.png').readAsBytes();
        final p = ProviderConnections(
          prefs,
          store,
          vault: vault,
          client: MockClient((r) async {
            final path = Uri.decodeComponent(r.url.path);
            requests.add(path);
            if (r.url.host == 'artwork.example.test') {
              expect(r.headers.containsKey('Authorization'), false);
              return http.Response.bytes(
                artwork,
                200,
                headers: {'content-type': 'image/png'},
              );
            }
            final body = switch (path) {
              '/v1.0/me/drive' => {'id': 'd'},
              '/v1.0/me/drive/items/music/children' ||
              '/v1.0/me/drive/root:/Música:/children' => {
                'value': [
                  {
                    'id': 'a',
                    'name': 'a.mp3',
                    'eTag': 'revision-1',
                    'audio': {
                      'title': 'Título real',
                      'artist': 'Artista & Banda',
                      'album': 'Álbum real',
                      'albumArtist': 'Artista do álbum',
                      'year': 2020,
                      'track': 3,
                      'disc': 2,
                      'genre': 'Rock',
                      'duration': 123000,
                    },
                    'thumbnails': [
                      {
                        'large': {
                          'url': 'https://artwork.example.test/art.png',
                        },
                      },
                    ],
                    'parentReference': {'id': 'sub'},
                  },
                  {'id': 'sub', 'name': 'Álbum', 'folder': {}},
                  {'id': 'image', 'name': 'cover.jpg'},
                ],
                '@odata.nextLink': 'https://graph.microsoft.com/v1.0/page2',
              },
              '/v1.0/page2' => {'value': []},
              '/v1.0/me/drive/items/sub/children' => {
                'value': [
                  {'id': 'b', 'name': 'b.flac'},
                ],
              },
              _ => throw StateError('Unexpected request'),
            };
            if (fail && r.url.path == '/v1.0/page2') {
              return http.Response('{}', 403);
            }
            return http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        if (cancel) {
          p.addListener(() {
            if (p.syncPages == 1) p.cancelSync = true;
          });
        }
        try {
          await p.importMicrosoft();
          final tracks = await store.loadTracks();
          if (cancel) {
            expect(tracks.map((t) => t.id).toSet(), {
              'local',
              'onedrive:d:outside',
            });
            expect(p.syncStatus, 'cancelled');
            expect(p.syncSummary, isNull);
            expect(
              await store.syncCursor(
                'onedrive:d:/drive/root:/Música:recursive-v2',
              ),
              isNull,
            );
            return;
          }
          expect(tracks.length, 3);
          if (!fail) {
            expect(
              tracks.singleWhere((t) => t.itemId == 'b').sourcePath,
              '/drive/root:/Música/Álbum',
            );
          }
          expect(tracks.any((t) => t.id == 'onedrive:d:outside'), fail);
          expect(
            await store.database.query(
              'tracks',
              where: 'id=?',
              whereArgs: ['onedrive:d:outside'],
            ),
            hasLength(1),
          );
          expect(
            requests.any(
              (r) =>
                  r.contains('/root/') ||
                  r.contains('/delta') ||
                  r.contains('/outside/'),
            ),
            false,
          );
          expect(requests.any((r) => r.endsWith('/content')), false);
          expect(p.imported, fail ? 1 : 2);
          expect(p.syncingMicrosoft, false);
          expect(p.syncPages, fail ? 1 : 3);
          expect(p.syncStatus, fail ? 'failed' : 'completed');
          expect(p.syncSummary?['total'], fail ? null : 2);
          final tagged = tracks.singleWhere((t) => t.itemId == 'a');
          expect(tagged.title, 'Título real');
          expect(tagged.fileName, 'a.mp3');
          expect(tagged.artistNames, ['Artista', 'Banda']);
          expect(tagged.trackNumber, 3);
          expect(tagged.discNumber, 2);
          expect(tagged.cover, artwork);
          if (!fail) {
            await p.importMicrosoft();
            expect(requests.where((r) => r == '/art.png'), hasLength(1));
            expect(p.syncSummary?['covers'], 1);
            expect(
              (await store.database.query(
                'tracks',
                where: 'id=?',
                whereArgs: ['onedrive:d:a'],
              )).single['metadata'].toString(),
              isNot(contains('artwork.example.test')),
            );
          }
          expect(
            await store.syncCursor(
              'onedrive:d:/drive/root:/Música:recursive-v2',
            ),
            isNull,
          );
        } finally {
          p.dispose();
          await store.close();
        }
      },
    );
  }
}
