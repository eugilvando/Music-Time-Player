import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';

import 'finalization_native_test.dart' show wave;

void main() {
  test('completed local cache file advances continuously through native audio output', () async {
    MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    );
    final dir = await Directory.systemTemp.createTemp(
      'music-time-cache-stability-',
    );
    // Cache files have an opaque .audio extension, just like MediaCache output.
    final bytes = Uint8List(44 + 44100 * 2 * 60)..setRange(0, 44, wave());
    final header = ByteData.sublistView(bytes);
    header.setUint32(4, bytes.length - 8, Endian.little);
    header.setUint32(40, bytes.length - 44, Endian.little);
    final file = await File('${dir.path}/completed.audio').writeAsBytes(bytes);
    final controller = PlayerController();
    var starvations = 0;
    var watching = false;
    final buffering = controller.player.stream.buffering.listen((value) {
      if (watching && value) starvations++;
    });
    try {
      await controller.playQueue([
        Track(
          id: 'cache-fixture',
          title: 'Fixture',
          artist: 'Demo',
          localPath: file.path,
        ),
      ], 0);
      await Future<void>.delayed(const Duration(seconds: 1));
      final native = controller.player.platform as NativePlayer;
      expect(await native.getProperty('cache-on-disk'), 'no');
      final initial = controller.position;
      final watch = Stopwatch()..start();
      var maxDrift = 0;
      watching = true;
      final progress = controller.player.stream.position.listen((position) {
        maxDrift = max(
          maxDrift,
          (watch.elapsedMilliseconds - (position - initial).inMilliseconds)
              .abs(),
        );
      });
      await Future<void>.delayed(const Duration(seconds: 20));
      watching = false;
      await progress.cancel();
      expect(controller.error, isNull);
      expect(controller.playing, isTrue);
      expect(starvations, 0);
      expect(
        (controller.position - initial).inMilliseconds,
        greaterThan(19000),
      );
      expect(
        maxDrift,
        lessThan(500),
        reason: 'unexpected native playback clock stall',
      );
      // Aggregate diagnostics only: no filenames or library metadata.
      // ignore: avoid_print
      print(
        'Cached playback: 20s; buffering=$starvations; max clock drift=${maxDrift}ms; audio buffer=${await native.getProperty('audio-buffer')}s',
      );
    } finally {
      await buffering.cancel();
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
