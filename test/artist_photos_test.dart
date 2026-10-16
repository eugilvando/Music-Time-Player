import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/presentation/artist_portrait.dart';

void main() {
  test(
    'imagem personalizada tem prioridade e funciona offline sem consultar API',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'music-time-custom-photo-',
      );
      addTearDown(() => root.delete(recursive: true));
      final key = sha256.convert(utf8.encode('artist')).toString();
      final custom = File('${root.path}/artist-custom/$key.jpg');
      await custom.parent.create(recursive: true);
      await custom.writeAsBytes([1, 2, 3]);
      final auto = File('${root.path}/artist-photos/$key.jpg');
      await auto.parent.create(recursive: true);
      await auto.writeAsBytes([4, 5]);
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        throw StateError('Sem rede');
      });
      addTearDown(client.close);
      final photos = ArtistPhotos(client: client, directory: () async => root);
      expect(await photos.photo('ARTIST', cachedOnly: true), [1, 2, 3]);
      expect(await photos.photo('Ausente', cachedOnly: true), isNull);
      expect(requests, 0);
      await photos.clearDiskCache(() async => auto.delete());
      expect(await custom.exists(), true);
      expect(await photos.photo('Artist', cachedOnly: true), [1, 2, 3]);
    },
  );
  test('foto exata é armazenada e recuperada sem rede', () async {
    final root = await Directory.systemTemp.createTemp('music-time-photos');
    addTearDown(() => root.delete(recursive: true));
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      if (request.url.path.endsWith('search.php')) {
        return http.Response(
          jsonEncode({
            'artists': [
              {
                'strArtist': 'Artist',
                'strArtistThumb':
                    'https://www.theaudiodb.com/images/artist.jpg',
              },
            ],
          }),
          200,
        );
      }
      return http.Response.bytes(
        [255, 216, 255, 217],
        200,
        headers: {'content-type': 'image/jpeg'},
      );
    });
    final photos = ArtistPhotos(client: client, directory: () async => root);
    expect(await photos.photo('Artist'), [255, 216, 255, 217]);
    expect(requests, 2);
    final offline = ArtistPhotos(
      client: MockClient((_) async => throw StateError('offline')),
      directory: () async => root,
    );
    expect(await offline.photo('ARTIST'), [255, 216, 255, 217]);
    expect(requests, 2);
  });
  test('nome divergente não baixa a foto de outro artista', () async {
    final root = await Directory.systemTemp.createTemp('music-time-photos');
    addTearDown(() => root.delete(recursive: true));
    var requests = 0;
    final photos = ArtistPhotos(
      directory: () async => root,
      client: MockClient((_) async {
        requests++;
        return http.Response(
          jsonEncode({
            'artists': [
              {
                'strArtist': 'Outro',
                'strArtistThumb': 'https://www.theaudiodb.com/images/other.jpg',
              },
            ],
          }),
          200,
        );
      }),
    );
    expect(await photos.photo('Artist'), isNull);
    expect(requests, 1);
  });
}
