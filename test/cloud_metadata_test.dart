import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/library/cloud_metadata.dart';
import 'package:music_time/library/local_metadata.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;

List<int> number(int n, [Endian endian = Endian.big]) =>
    (ByteData(4)..setUint32(0, n, endian)).buffer.asUint8List();
List<int> syncsafe(int n) => [
  for (final shift in [21, 14, 7, 0]) (n >> shift) & 127,
];

Uint8List mp3Fixture(Uint8List image, {int version = 3, String disc = '2/2'}) {
  List<int> frame(String name, List<int> body) => [
    ...ascii.encode(name),
    ...(version == 4 ? syncsafe(body.length) : number(body.length)),
    0,
    0,
    ...body,
  ];
  final body = [
    for (final tag in {
      'TIT2': 'Canção real',
      'TPE1': 'Earth, Wind & Fire',
      'TPE2': 'Artista do álbum',
      'TALB': 'Álbum original',
      'TYER': '2022',
      'TRCK': '3/12',
      'TPOS': disc,
    }.entries)
      ...frame(tag.key, [3, ...utf8.encode(tag.value)]),
    ...frame('APIC', [0, ...ascii.encode('image/png'), 0, 3, 0, ...image]),
    ...Uint8List(16),
  ];
  final audio = Uint8List(1024)
    ..setAll(0, [255, 251, 144, 0])
    ..setAll(36, 'Xing'.codeUnits);
  ByteData.sublistView(audio)
    ..setUint32(40, 1)
    ..setUint32(44, 7656);
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    version,
    0,
    0,
    ...syncsafe(body.length),
    ...body,
    ...audio,
  ]);
}

http.Response rangeResponse(http.Request request, Uint8List file) {
  expect(request.headers.containsKey('Authorization'), false);
  final range = RegExp(r'^bytes=(\d+)-(\d+)$')
      .firstMatch(request.headers['Range']!)!;
  final start = int.parse(range.group(1)!), end = int.parse(range.group(2)!);
  return http.Response.bytes(
    file.sublist(start, end + 1),
    206,
    headers: {'content-range': 'bytes $start-$end/${file.length}'},
  );
}

void main() {
  test('capa de pasta em página posterior preenche faixas sem capa no mesmo escopo', () async {
    const clientId = '00000000-0000-0000-0000-000000000001';
    SharedPreferences.setMockInitialValues({
      'microsoft.client_id': clientId,
      'microsoft.folder_selected': true,
      'microsoft.folder_id': 'music',
      'microsoft.folder_path': '/drive/root:/Música',
    });
    final vault = MemoryVault();
    await vault.write(
      'microsoft.session',
      jsonEncode({
        'client_id': clientId,
        'access_token': 'fixture',
        'expires_at': '2099-01-01T00:00:00Z',
      }),
    );
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final image = await File('assets/branding/icon.png').readAsBytes();
    var imageReads = 0;
    final providers = ProviderConnections(
      await SharedPreferences.getInstance(),
      store,
      vault: vault,
      client: MockClient((r) async {
        if (r.url.host == 'content.test') {
          expect(r.headers.containsKey('Authorization'), false);
          if (r.url.path == '/cover') {
            imageReads++;
            return http.Response.bytes(image, 200);
          }
          return rangeResponse(r, Uint8List(64));
        }
        final body = switch (r.url.path) {
          '/v1.0/me/drive' => {'id': 'd'},
          '/v1.0/me/drive/items/music/children' => {
            'value': [
              {
                'id': 'track',
                'name': 'song.mp3',
                'audio': {'artist': 'Artista', 'album': 'Álbum'},
                'parentReference': {'driveId': 'd'},
              },
            ],
            '@odata.nextLink': 'https://graph.microsoft.com/v1.0/next',
          },
          '/v1.0/next' => {
            'value': [
              {
                'id': 'cover',
                'name': 'cover.png',
                'size': image.length,
                'parentReference': {'driveId': 'd'},
              },
            ],
          },
          '/v1.0/drives/d/items/track' => {
            '@microsoft.graph.downloadUrl': 'https://content.test/audio',
          },
          '/v1.0/drives/d/items/cover' => {
            '@microsoft.graph.downloadUrl': 'https://content.test/cover',
          },
          _ => <String, Object>{},
        };
        return http.Response(jsonEncode(body), 200);
      }),
    );
    addTearDown(providers.dispose);
    await providers.importMicrosoft();
    expect(providers.error, isNull);
    expect(providers.imported, 1);
    final track = (await store.loadTracks()).single;
    expect(track.artist, 'Artista');
    expect(track.cover, image);
    expect(track.cloudCoverEmbedded, false);
    expect(providers.syncSummary?['covers'], 1);
    expect(imageReads, 1);
  });
  test(
    'ID3v2.3 com cabeçalho estendido e unsynchronisation preserva capa',
    () async {
      final image = await File('assets/branding/icon.png').readAsBytes();
      final original = mp3Fixture(image);
      final logical = [
        ...number(6),
        ...Uint8List(6),
        ...original.sublist(10, original.length - 1024),
      ];
      final physical = [
        for (final b in logical) ...[b, if (b == 255) 0],
      ];
      final file = Uint8List.fromList([
        ...ascii.encode('ID3'),
        3,
        0,
        0xc0,
        ...syncsafe(physical.length),
        ...physical,
        ...Uint8List(1024),
      ]);
      final client = MockClient((r) async => rangeResponse(r, file));
      addTearDown(client.close);
      final tags = await CloudMetadataReader(client)
          .read(Uri.parse('https://content.test/audio'), 'song.mp3');
      expect(tags!.artists, ['Earth, Wind & Fire']);
      expect(tags.cover, image);
    },
  );
  test('ID3v1 lê somente cabeçalho e 128 bytes finais', () async {
    final file = Uint8List(2048);
    final start = file.length - 128;
    file.setRange(start, start + 3, ascii.encode('TAG'));
    file.setRange(start + 3, start + 8, ascii.encode('Title'));
    file.setRange(start + 33, start + 39, ascii.encode('Artist'));
    file.setRange(start + 63, start + 68, ascii.encode('Album'));
    file.setRange(start + 93, start + 97, ascii.encode('1999'));
    final reader = CloudMetadataReader(
      MockClient((r) async => rangeResponse(r, file)),
    );
    addTearDown(reader.client.close);
    final tags = await reader.read(
      Uri.parse('https://content.test/audio'),
      'song.mp3',
      fileSize: file.length,
    );
    expect(tags!.artists, ['Artist']);
    expect(tags.album, 'Album');
    expect(tags.year, 1999);
    expect(reader.received, 138 + 256);
  });
  test('tamanho ID3 fora do limite não provoca segunda requisição', () async {
    var requests = 0;
    final client = MockClient((r) async {
      requests++;
      return http.Response.bytes(
        [...ascii.encode('ID3'), 3, 0, 0, ...syncsafe(maxCloudMetadataBytes)],
        206,
        headers: {'content-range': 'bytes 0-9/20000000'},
      );
    });
    addTearDown(client.close);
    expect(
      await CloudMetadataReader(client)
          .read(Uri.parse('https://content.test/audio'), 'song.mp3'),
      isNull,
    );
    expect(requests, 1);
  });
  for (final version in [3, 4]) {
    test(
      'MP3 ID3v2.$version lê tags/capa e somente 256 bytes do cabeçalho de áudio',
      () async {
        final image = await File('assets/branding/icon.png').readAsBytes();
        final file = mp3Fixture(image, version: version);
        var received = 0;
        final client = MockClient((r) async {
          final response = rangeResponse(r, file);
          received += response.bodyBytes.length;
          return response;
        });
        addTearDown(client.close);
        final tags = await CloudMetadataReader(client)
            .read(Uri.parse('https://content.test/audio'), 'song.mp3');
        expect(tags!.title, 'Canção real');
        expect(tags.artists, ['Earth, Wind & Fire']);
        expect(tags.albumArtists, ['Artista do álbum']);
        expect(tags.album, 'Álbum original');
        expect(tags.year, 2022);
        expect(tags.trackNumber, 3);
        expect(tags.discNumber, 2);
        expect(tags.cover, image);
        expect(tags.duration!.inSeconds, 199);
        expect(received, file.length - 1024 + 256);
      },
    );
  }
  test(
    'FLAC lê múltiplos artistas, comentário e capa; ignora padding',
    () async {
      final image = await File('assets/branding/icon.png').readAsBytes();
      final comments = [
        'TITLE=Faixa',
        'ARTIST=Nome & Banda',
        'ARTIST=Participante',
        'ALBUM=Disco',
        'ALBUMARTIST=Grupo',
        'DATE=2020',
        'TRACKNUMBER=4',
        'DISCNUMBER=2/2',
      ];
      final comment = [
        ...number(0, Endian.little),
        ...number(comments.length, Endian.little),
        for (final c in comments) ...[
          ...number(utf8.encode(c).length, Endian.little),
          ...utf8.encode(c),
        ],
      ];
      final picture = [
        ...number(3),
        ...number(9),
        ...ascii.encode('image/png'),
        ...number(0),
        ...number(128),
        ...number(128),
        ...number(32),
        ...number(0),
        ...number(image.length),
        ...image,
      ];
      List<int> block(int type, List<int> body) => [
        type,
        (body.length >> 16) & 255,
        (body.length >> 8) & 255,
        body.length & 255,
        ...body,
      ];
      final stream = Uint8List(34);
      ByteData.sublistView(stream)
          .setUint64(10, (44100 << 44) | (1 << 41) | (15 << 36) | 44100);
      final file = Uint8List.fromList([
        ...ascii.encode('fLaC'),
        ...block(0, stream),
        ...block(1, Uint8List(65536)),
        ...block(4, comment),
        ...block(0x86, picture),
        ...Uint8List(1024),
      ]);
      final reader = CloudMetadataReader(
        MockClient((r) async => rangeResponse(r, file)),
      );
      addTearDown(reader.client.close);
      final tags = await reader.read(
        Uri.parse('https://content.test/audio'),
        'song.flac',
      );
      expect(tags!.artists, ['Nome & Banda', 'Participante']);
      expect(tags.album, 'Disco');
      expect(tags.albumArtists, ['Grupo']);
      expect(tags.year, 2020);
      expect(tags.trackNumber, 4);
      expect(tags.discNumber, 2);
      expect(tags.cover, image);
      expect(reader.received, lessThan(file.length - 65536));
    },
  );
  test('Range ignorado não é usado como download completo', () async {
    final client = MockClient((_) async => http.Response.bytes([1, 2, 3], 200));
    addTearDown(client.close);
    final reader = CloudMetadataReader(client);
    await expectLater(
      reader.read(Uri.parse('https://content.test/audio'), 'song.mp3'),
      throwsFormatException,
    );
    expect(reader.received, 0);
  });
  test(
    'MP3 local usa TPE1 como artista e TPE2 como artista de álbum',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'music-time-local-id3-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = await File('${root.path}/song.mp3').writeAsBytes(
        mp3Fixture(await File('assets/branding/icon.png').readAsBytes()),
      );
      final track = readLocalTracks([file.path]).single;
      expect(track.artist, 'Earth, Wind & Fire');
      expect(track.albumArtist, 'Artista do álbum');
    },
  );
  test(
    'sync sem audio facet usa tags embutidas, persiste e reutiliza eTag',
    () async {
      const clientId = '00000000-0000-0000-0000-000000000001';
      SharedPreferences.setMockInitialValues({
        'microsoft.client_id': clientId,
        'microsoft.folder_selected': true,
        'microsoft.folder_id': 'music',
        'microsoft.folder_path': '/drive/root:/Música',
      });
      final vault = MemoryVault();
      await vault.write(
        'microsoft.session',
        jsonEncode({
          'client_id': clientId,
          'access_token': 'fixture',
          'expires_at': '2099-01-01T00:00:00Z',
        }),
      );
      final store = await LibraryStore.open(':memory:');
      addTearDown(store.close);
      final image = await File('assets/branding/icon.png').readAsBytes();
      final file = mp3Fixture(image);
      var reads = 0;
      final providers = ProviderConnections(
        await SharedPreferences.getInstance(),
        store,
        vault: vault,
        client: MockClient((r) async {
          if (r.url.host == 'content.test') {
            reads++;
            return rangeResponse(r, file);
          }
          final body = switch (r.url.path) {
            '/v1.0/me/drive' => {'id': 'd'},
            '/v1.0/me/drive/items/music/children' => {
              'value': [
                {
                  'id': 'track',
                  'name': '03 - Arquivo.mp3',
                  'eTag': 'r1',
                  'parentReference': {'driveId': 'd'},
                },
              ],
            },
            '/v1.0/drives/d/items/track' => {
              '@microsoft.graph.downloadUrl': 'https://content.test/audio',
            },
            _ => <String, Object>{},
          };
          return http.Response(jsonEncode(body), 200);
        }),
      );
      addTearDown(providers.dispose);
      await providers.importMicrosoft();
      expect(providers.error, isNull);
      final track = (await store.loadTracks()).single;
      expect(track.artist, 'Earth, Wind & Fire');
      expect(track.albumArtist, 'Artista do álbum');
      expect(track.album, 'Álbum original');
      expect(track.cover, image);
      expect(track.cloudTagsVersion, 3);
      expect(track.duration.inSeconds, 199);
      expect(track.fileName, '03 - Arquivo.mp3');
      expect(providers.syncSummary?['tagsRead'], 1);
      await providers.importMicrosoft();
      expect(providers.error, isNull);
      expect(reads, 3);
      // An unchanged old metadata revision without a disc must be read once
      // with the new parser, while retaining the persistent track identity.
      await store.database.rawUpdate(
        "UPDATE tracks SET metadata=json_set(metadata,'\$.cloudTagsVersion',2,'\$.discNumber',NULL)",
      );
      await providers.importMicrosoft();
      expect(providers.error, isNull);
      final refreshed = (await store.loadTracks()).single;
      expect(refreshed.id, track.id);
      expect(refreshed.discNumber, 2);
      expect(refreshed.cloudTagsVersion, 3);
      expect(reads, 6);
      await providers.importMicrosoft();
      expect(reads, 6);
      expect((await store.downloadTasks()), isEmpty);
    },
  );
}
