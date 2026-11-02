import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';

void main() {
  final lib = Platform.environment['MUSIC_TIME_LIBMPV'];
  test(
    'Windows restores 24-bit audio and survives unavailable output',
    () async {
      MediaKit.ensureInitialized(libmpv: lib);
      final folder = await Directory.systemTemp.createTemp(
        'music-time-output-',
      );
      final bytes = Uint8List(44 + 48000 * 6 * 4);
      final data = ByteData.sublistView(bytes);
      void text(int offset, String value) =>
          bytes.setRange(offset, offset + value.length, value.codeUnits);
      text(0, 'RIFF');
      data.setUint32(4, bytes.length - 8, Endian.little);
      text(8, 'WAVE');
      text(12, 'fmt ');
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little);
      data.setUint16(22, 2, Endian.little);
      data.setUint32(24, 48000, Endian.little);
      data.setUint32(28, 48000 * 6, Endian.little);
      data.setUint16(32, 6, Endian.little);
      data.setUint16(34, 24, Endian.little);
      text(36, 'data');
      data.setUint32(40, bytes.length - 44, Endian.little);
      final file = await File('${folder.path}/silence24.wav')
          .writeAsBytes(bytes);
      final controller = PlayerController();
      final track = Track(
        id: '24bit',
        title: '24bit',
        artist: 'Test',
        localPath: file.path,
      );
      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 100 && !ready(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(ready(), isTrue);
      }

      try {
        await controller.restore([track], 0, const Duration(seconds: 1));
        await waitFor(() => controller.duration > Duration.zero);
        final native = controller.player.platform as NativePlayer;
        expect(await native.getProperty('ao'), 'wasapi');
        expect(await native.getProperty('current-ao'), 'wasapi');
        expect(await native.getProperty('audio-params/format'), 's32');
        expect(controller.playing, isFalse);
        await native.setProperty(
          'audio-device',
          'wasapi/music-time-missing-device',
        );
        await controller.playQueue([track], 0);
        await waitFor(() => controller.error != null);
        expect(await native.getProperty('ao'), 'wasapi');
        await native.setProperty('audio-device', 'auto');
        await controller.playQueue([track], 0);
        await waitFor(
          () => controller.playing && controller.position.inMilliseconds > 100,
        );
        expect(await native.getProperty('current-ao'), 'wasapi');
        expect(controller.error, isNull);
        await controller.clearQueue();
      } finally {
        controller.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await folder.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows || lib == null
        ? 'Windows native audio required'
        : false,
  );
}
