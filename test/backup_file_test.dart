import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/persistence/backup_file.dart';
import 'package:music_time/persistence/backup_archive.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/domain/track.dart';

import 'provider_auth_test.dart' show MemoryVault;

void main() {
  late Directory dir;
  late LibraryStore from, to;
  late SharedPreferences prefs;
  final vault = MemoryVault();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'visual.smart_flow': true,
      'visual.smart_flow_mode': 'double',
    });
    prefs = await SharedPreferences.getInstance();
    dir = await Directory.systemTemp.createTemp('mt-backup305-');
    from = await LibraryStore.open('${dir.path}/from.db');
    to = await LibraryStore.open('${dir.path}/to.db');
  });
  tearDown(() async {
    await from.close();
    await to.close();
    await dir.delete(recursive: true);
  });
  Future<void> seed({int count = 1, int size = 512}) async {
    for (var i = 0; i < count; i++) {
      final bytes = Uint8List(size)..fillRange(0, size, i + 1);
      final hash = sha256.convert(bytes).toString();
      await from.addTracks([
        Track(
          id: 't$i',
          title: 'Synthetic $i',
          artist: 'Test',
          localPath: 'C:/synthetic/$i.mp3',
        ),
      ]);
      await from.database.insert('artworks', {
        'hash': hash,
        'bytes': bytes,
        'byte_count': size,
      });
      await from.database.update(
        'tracks',
        {'cover_hash': hash},
        where: 'id=?',
        whereArgs: ['t$i'],
      );
    }
    await from.database.insert('artworks', {
      'hash': 'orphan',
      'bytes': Uint8List.fromList([1]),
      'byte_count': 1,
    });
  }

  test('Smart Flow preferences export and restore in legacy format', () async {
    final file = File('${dir.path}/prefs.mtbackup');
    await BackupFile.write(file, from, prefs, vault, {'preferences'});
    final archive = await BackupFile.read(file);
    await prefs.setBool('visual.smart_flow', false);
    await BackupArchive.restore(to, prefs, vault, archive, {'preferences'});
    expect(prefs.getBool('visual.smart_flow'), true);
  });
  for (final encrypted in [false, true]) {
    test(
      'streamed images and preferences round trip encrypted=$encrypted',
      () async {
        await seed();
        final password = encrypted ? 'synthetic-passphrase-305' : null;
        final file = File('${dir.path}/images.mtbackup');
        final sections = {
          'library',
          'preferences',
          'artwork',
          if (encrypted) ...['providers', 'credentials'],
        };
        if (encrypted) {
          await vault.write('lastfm.api_secret', 'synthetic-secret-305');
        }
        final progress = <String>[];
        await BackupFile.write(
          file,
          from,
          prefs,
          vault,
          sections,
          password: password,
          onProgress: progress.add,
        );
        expect(await BackupFile.encrypted(file), encrypted);
        final archive = await BackupFile.read(file, password: password);
        if (encrypted) {
          expect(
            archive['secrets']['lastfm.api_secret'],
            'synthetic-secret-305',
          );
        }
        await to.addTracks([
          const Track(
            id: 't0',
            title: 'Synthetic 0',
            artist: 'Test',
            localPath: 'C:/synthetic/0.mp3',
          ),
        ]);
        await to.database.update(
          'tracks',
          {
            'cover': Uint8List.fromList([99]),
          },
          where: 'id=?',
          whereArgs: ['t0'],
        );
        await BackupArchive.restore(to, prefs, vault, archive, sections);
        expect(await to.trackCover('t0'), await from.trackCover('t0'));
        expect(await to.database.query('artworks'), hasLength(1));
        expect(progress.any((p) => p.startsWith('Salvando capas:')), true);
        if (encrypted) {
          await expectLater(
            BackupFile.read(file, password: 'wrong-passphrase'),
            throwsFormatException,
          );
        }
        final bytes = await file.readAsBytes();
        await file.writeAsBytes(bytes.sublist(0, bytes.length - 8));
        await expectLater(
          BackupFile.read(file, password: password),
          throwsFormatException,
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
  test(
    'cover backup larger than 128 MB restores without aggregate decoding',
    () async {
      await seed(count: 6, size: 23 * 1024 * 1024);
      final file = File('${dir.path}/large.mtbackup');
      final sections = {'library', 'artwork'};
      await BackupFile.write(file, from, prefs, vault, sections);
      expect(await file.length(), greaterThan(128 * 1024 * 1024));
      final archive = await BackupFile.read(file);
      await BackupArchive.restore(to, prefs, vault, archive, sections);
      final size = (await to.database.rawQuery(
        'SELECT SUM(byte_count) AS n FROM artworks',
      )).single['n'];
      expect(size, 6 * 23 * 1024 * 1024);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'failed export preserves existing destination and removes partial file',
    () async {
      final file = await File('${dir.path}/existing.mtbackup')
          .writeAsString('previous');
      await expectLater(
        BackupFile.write(file, from, prefs, vault, {'artwork'}),
        throwsFormatException,
      );
      expect(await file.readAsString(), 'previous');
      expect(await dir.list().where((f) => f.path.endsWith('.part')).length, 0);
    },
  );
  test(
    'playlist-only and legacy inline covers survive selective restore',
    () async {
      await from.addTracks([
        const Track(
          id: 'legacy',
          title: 'Legacy',
          artist: 'Test',
          localPath: 'C:/legacy.mp3',
        ),
      ]);
      final bytes = Uint8List.fromList([9, 8, 7]);
      await from.database.update(
        'tracks',
        {'cover': bytes},
        where: 'id=?',
        whereArgs: ['legacy'],
      );
      await from.importPlaylist('Synthetic playlist', ['legacy']);
      await from.database.update('playlists', {'cover': bytes});
      final file = File('${dir.path}/inline.mtbackup');
      final sections = {'library', 'playlists', 'artwork'};
      await BackupFile.write(file, from, prefs, vault, sections);
      await BackupArchive.restore(
        to,
        prefs,
        vault,
        await BackupFile.read(file),
        sections,
      );
      expect(await to.trackCover('legacy'), bytes);
      expect((await to.database.query('playlists')).single['cover'], bytes);
      final playlistFile = File('${dir.path}/playlist.mtbackup');
      await BackupFile.write(playlistFile, from, prefs, vault, {
        'playlists',
        'artwork',
      });
      await BackupArchive.restore(
        to,
        prefs,
        vault,
        await BackupFile.read(playlistFile),
        {'playlists', 'artwork'},
      );
      expect(await to.database.query('tracks'), hasLength(1));
      expect((await to.database.query('playlists')).last['cover'], bytes);
    },
  );
  test('changed artwork after verification rolls back restore', () async {
    await seed();
    final file = File('${dir.path}/changed.mtbackup');
    final sections = {'library', 'artwork'};
    await BackupFile.write(file, from, prefs, vault, sections);
    final archive = await BackupFile.read(file);
    final bytes = await file.readAsBytes();
    // Change the image payload just before the final frame (37 bytes + length).
    bytes[bytes.length - 42] ^= 1;
    await file.writeAsBytes(bytes);
    await expectLater(
      BackupArchive.restore(to, prefs, vault, archive, sections),
      throwsFormatException,
    );
    expect(await to.database.query('tracks'), isEmpty);
    expect(await to.database.query('artworks'), isEmpty);
  });
}
