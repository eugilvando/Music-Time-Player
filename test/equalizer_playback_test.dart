import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';

void main() {
  final library = Platform.environment['MUSIC_TIME_LIBMPV'];
  test(
    'equalizer decodes audio while enabled before opening and during playback',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final directory = await Directory.systemTemp.createTemp('music-time-eq-');
      final controller = PlayerController();
      final native = controller.player.platform as NativePlayer;
      final errors = <String>[];
      final log = controller.player.stream.log.listen((entry) {
        // Known startup diagnostics do not indicate a filter failure.
        final startup =
            entry.prefix == 'media_kit' &&
            entry.text.contains('_setProperty(osc,');
        final fileCache =
            entry.prefix == 'lavf' &&
            entry.text == 'Failed to create file cache.';
        if (entry.level == 'error' && !startup && !fileCache) {
          errors.add('${entry.prefix}: ${entry.text}');
        }
      });
      try {
        await native.setProperty('ao', 'null');
        for (final rate in [8000, 16000, 22050, 44100, 48000, 96000]) {
          final channels = rate == 44100 ? 2 : 1;
          final bytes = Uint8List(44 + rate * channels * 2 * 5);
          final data = ByteData.sublistView(bytes);
          void text(int at, String value) =>
              bytes.setRange(at, at + value.length, value.codeUnits);
          text(0, 'RIFF');
          data.setUint32(4, bytes.length - 8, Endian.little);
          text(8, 'WAVEfmt ');
          data.setUint32(16, 16, Endian.little);
          data.setUint16(20, 1, Endian.little);
          data.setUint16(22, channels, Endian.little);
          data.setUint32(24, rate, Endian.little);
          data.setUint32(28, rate * channels * 2, Endian.little);
          data.setUint16(32, channels * 2, Endian.little);
          data.setUint16(34, 16, Endian.little);
          text(36, 'data');
          data.setUint32(40, bytes.length - 44, Endian.little);
          final file = await File('${directory.path}/$rate.wav')
              .writeAsBytes(bytes);
          await controller.setEqualizer(true, [2, 3, 0, -2, 3]);
          expect(
            double.parse(await native.getProperty('replaygain-fallback')),
            -8,
          );
          await controller.playQueue([
            Track(
              id: '$rate',
              title: 'EQ fixture',
              artist: 'Test',
              localPath: file.path,
            ),
          ], 0);
          await Future<void>.delayed(const Duration(milliseconds: 350));
          expect(controller.playing, isTrue, reason: '$rate Hz');
          expect(controller.error, isNull, reason: '$rate Hz');
          expect(controller.position, greaterThan(Duration.zero));
          await controller.setEqualizer(true, [0, 1, -2, 1, 0]);
          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(controller.playing, isTrue);
          await controller.setEqualizer(false, [0, 0, 0, 0, 0]);
          expect(
            double.parse(await native.getProperty('replaygain-fallback')),
            0,
          );
          expect(await native.getProperty('af'), isEmpty);
          expect(controller.volume, 100);
        }
        expect(errors, isEmpty);
      } finally {
        await log.cancel();
        controller.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await directory.delete(recursive: true);
      }
    },
    skip: library == null,
  );
}
