import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/catalog_query.dart';

import 'provider_auth_test.dart' show MemoryVault;

void main() {
  test(
    'backup restaura catálogo, capa, repetições e preferências sem credenciais',
    () async {
      SharedPreferences.setMockInitialValues({
        'theme': 'light',
        'visual.font_body': 18.0,
        'microsoft.client_id': 'private-configuration',
        'lastfm.api_secret': 'never-export',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = await LibraryStore.open(':memory:');
      try {
        final track = Track(
          id: 'a',
          title: 'Canção',
          artist: 'Artista',
          localPath: 'C:/songs/a.mp3',
          cover: Uint8List.fromList([1, 2, 3]),
        );
        await store.addTracks([track]);
        await store.registerLocalSource('folder', 'Minha pasta', ['a']);
        await store.importPlaylist('Repetições', ['a', 'a']);
        await store.setFavorite('a', true);
        await store.savePlayback(
          [track, track],
          1,
          const Duration(seconds: 12),
        );
        final backup = await AppData.backup(store, prefs);
        expect(backup, isNot(contains('never-export')));
        expect(backup, isNot(contains('private-configuration')));
        await store.addTracks([
          const Track(
            id: 'b',
            title: 'Outra',
            artist: 'Outro',
            localPath: 'C:/b.mp3',
          ),
        ]);
        await prefs.setString('theme', 'dark');
        await AppData.restore(store, prefs, backup);
        expect((await store.loadTracks()).single.cover, [1, 2, 3]);
        expect(
          (await store.catalogPage(
            CatalogSqlQuery(filters: CatalogFilters(), text: 'CANCAO'),
          )).tracks.single.id,
          'a',
        );
        expect(
          (await store.playlistEntries(
            (await store.playlists()).single['id'] as int,
          )).length,
          2,
        );
        expect((await store.loadPlayback()).index, 1);
        expect((await store.loadPlayback()).position.inSeconds, 12);
        expect(prefs.getString('theme'), 'light');
        expect(prefs.getString('lastfm.api_secret'), 'never-export');
      } finally {
        await store.close();
      }
    },
  );
  test('backup incompatível ou com referência ausente reverte catálogo e preferências', () async {
    SharedPreferences.setMockInitialValues({'theme': 'dark'});
    final prefs = await SharedPreferences.getInstance();
    final store = await LibraryStore.open(':memory:');
    try {
      await store.addTracks([
        const Track(
          id: 'a',
          title: 'Preservada',
          artist: 'Artista',
          localPath: 'C:/a.mp3',
        ),
      ]);
      final doc = jsonDecode(
        await AppData.backup(store, prefs),
      ) as Map<String, dynamic>;
      doc['tables']['queue'] = [
        {'ordinal': 0, 'track_id': 'missing'},
      ];
      doc['preferences']['theme'] = 'light';
      await expectLater(
        AppData.restore(store, prefs, jsonEncode(doc)),
        throwsA(anything),
      );
      expect((await store.loadTracks()).single.title, 'Preservada');
      expect(prefs.getString('theme'), 'dark');
      doc['version'] = 999;
      expect(() => AppData.parse(jsonEncode(doc)), throwsFormatException);
      doc['version'] = 1;
      doc['preferences']['visual.font_body'] = 'invalid';
      expect(() => AppData.parse(jsonEncode(doc)), throwsFormatException);
      doc['preferences'].remove('visual.font_body');
      doc['preferences']['microsoft.session'] = 'token';
      expect(() => AppData.parse(jsonEncode(doc)), throwsFormatException);
    } finally {
      await store.close();
    }
  });
  test('reset na inicialização limpa app e cofre sem apagar originais ou outros segredos', () async {
    SharedPreferences.setMockInitialValues({
      'theme': 'light',
      'microsoft.client_id': 'id',
      'microsoft.sources': <String>['abcdefghijklmnop'],
    });
    final prefs = await SharedPreferences.getInstance();
    final root = await Directory.systemTemp.createTemp(
      'music-time-reset-test-',
    );
    final store = await LibraryStore.open('${root.path}/music_time.db');
    final vault = MemoryVault();
    try {
      await vault.write('microsoft.session', 'token');
      await vault.write(
        'microsoft.source.abcdefghijklmnop.session',
        'fixture-extra',
      );
      await vault.write('lastfm.api_secret', 'secret');
      await vault.write('other-app', 'preserved');
      final offline = await Directory('${root.path}/offline').create();
      final hash = 'a' * 64;
      final original = await File('${offline.path}/$hash.audio')
          .writeAsString('original');
      final managed = await File('${offline.path}/${'b' * 64}.audio')
          .writeAsString('download');
      final unknown = await File('${offline.path}/keep.mp3')
          .writeAsString('keep');
      await store.addTracks([
        Track(
          id: 'a',
          title: 'Original',
          artist: 'Artista',
          localPath: original.path,
        ),
      ]);
      await store.registerLocalSource('folder', 'Pasta', ['a']);
      await store.removeLocalSource('folder');
      await AppData.stage(root);
      expect(
        await AppData.applyPending(root, store, prefs, vault),
        contains('resetado'),
      );
      expect(await store.database.query('tracks'), isEmpty);
      expect(prefs.getKeys(), isEmpty);
      expect(await vault.read('microsoft.session'), isNull);
      expect(
        await vault.read('microsoft.source.abcdefghijklmnop.session'),
        isNull,
      );
      expect(await vault.read('lastfm.api_secret'), isNull);
      expect(await vault.read('other-app'), 'preserved');
      expect(await original.readAsString(), 'original');
      expect(await unknown.exists(), isTrue);
      expect(await managed.exists(), isFalse);
      expect(await AppData.requestFile(root).exists(), isFalse);
      expect(await AppData.applyPending(root, store, prefs, vault), isNull);
    } finally {
      await store.close();
      await root.delete(recursive: true);
    }
  });
}
