import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/offline/media_cache.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/persistence/library_store.dart';

import 'finalization_rules_test.dart' show Remote;

Uint8List wave() {
  final bytes = Uint8List(44 + 44100 * 2 * 4), data = ByteData(44);
  void text(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, value.codeUnits);
  data.setUint32(4, bytes.length - 8, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 44100, Endian.little);
  data.setUint32(28, 88200, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(40, bytes.length - 44, Endian.little);
  bytes.setRange(0, 44, data.buffer.asUint8List());
  text(0, 'RIFF');
  text(8, 'WAVE');
  text(12, 'fmt ');
  text(36, 'data');
  return bytes;
}

void main() {
  final library = Platform.environment['MUSIC_TIME_LIBMPV'];
  test(
    'áudio em cache toca sem rede e play contínuo estende fila real',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final directory = await Directory.systemTemp.createTemp(
        'music-time-cache-native-',
      );
      final store = await LibraryStore.open(':memory:');
      const a = Track(
        id: 'native-a',
        title: 'A',
        artist: 'Autor',
        driveId: 'drive',
        itemId: 'a',
        genre: 'Rock',
      );
      const b = Track(
        id: 'native-b',
        title: 'B',
        artist: 'Autor',
        driveId: 'drive',
        itemId: 'b',
        genre: 'Rock',
      );
      await store.addTracks([a, b]);
      final remote = Remote();
      final cache = MediaCache(
        store,
        remote,
        directory: () async => directory,
        client: MockClient(
          (_) async => http.Response.bytes(
            wave(),
            200,
            headers: {'content-type': 'audio/wav'},
          ),
        ),
      );
      final downloads = DownloadManager(store, remote, cache: cache);
      final controller = PlayerController(resolver: downloads);
      try {
        cache.request(a);
        cache.request(b);
        await cache.idle;
        expect(remote.calls, 2);
        downloads.offlineOnly = true;
        await controller.restore([a], 0, Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(controller.error, isNull);
        expect(controller.playing, false);
        expect(controller.duration.inSeconds, 4);
        controller.continuous = (_, queue) async => [b];
        await controller.next(automatic: true);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(controller.current!.id, b.id);
        expect(controller.queue.map((t) => t.id), [a.id, b.id]);
        expect(controller.queueKeys.toSet().length, 2);
        expect(controller.error, isNull);
        expect(controller.playing, true);
        expect(remote.calls, 2);
        await controller.player.pause();
        final stale = Completer<List<Track>>();
        controller.continuous = (_, queue) => stale.future;
        final oldAttempt = controller.next(automatic: true);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        controller.continuous = (_, queue) async => [];
        stale.complete([a]);
        await oldAttempt;
        expect(controller.queue.map((t) => t.id), [a.id, b.id]);
        final pending = Completer<List<Track>>();
        controller.continuous = (_, queue) => pending.future;
        final attempt = controller.next(automatic: true);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await controller.clearQueue();
        pending.complete([a]);
        await attempt;
        expect(controller.queue, isEmpty);
        expect(controller.current, isNull);
      } finally {
        controller.dispose();
        downloads.dispose();
        cache.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    skip: library == null ? 'Requer libmpv do build Windows.' : false,
  );
}
