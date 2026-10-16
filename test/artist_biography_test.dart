import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/presentation/artist_biography.dart';

void main() {
  test('biography accepts a single exact match, strips markup and works from offline cache', () async {
    final root = await Directory.systemTemp.createTemp('music-time-bio-');
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.queryParameters['s'], 'Artist A');
      return http.Response(
        jsonEncode({
          'artists': [
            {
              'strArtist': 'Artist A',
              'strBiographyEN': '<p>A brief biography.</p>',
            },
          ],
        }),
        200,
      );
    });
    try {
      final api = ArtistBiographies(
        client: client,
        directory: () async => root,
      );
      expect(await api.load('Artist A'), 'A brief biography.');
      expect(
        await ArtistBiographies(
          client: client,
          directory: () async => root,
        ).load('Artist A', offline: true),
        'A brief biography.',
      );
      expect(requests, 1);
    } finally {
      client.close();
      await root.delete(recursive: true);
    }
  });
  test('ambiguous or different names never supply a biography', () async {
    final root = await Directory.systemTemp.createTemp('music-time-bio-');
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'artists': [
            {'strArtist': 'Same Name', 'strBiographyEN': 'One'},
            {'strArtist': 'Same Name', 'strBiographyEN': 'Two'},
          ],
        }),
        200,
      ),
    );
    try {
      final api = ArtistBiographies(
        client: client,
        directory: () async => root,
      );
      expect(await api.load('Same Name'), isNull);
      expect(await api.load('Different'), isNull);
      expect(await api.load('Uncached', offline: true), isNull);
    } finally {
      client.close();
      await root.delete(recursive: true);
    }
  });
}
