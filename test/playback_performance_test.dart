import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';

import 'finalization_native_test.dart' show wave;

void main() {
  test(
    'Smart Flow prepares one look-ahead without recursively filling the queue',
    () async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      final controller = PlayerController();
      final tracks = [
        for (var i = 0; i < 40; i++)
          Track(id: 'manual-$i', title: 'Fixture', artist: 'Demo'),
      ];
      controller.queue.addAll(tracks);
      controller.queueKeys.addAll([for (var i = 0; i < 40; i++) 100 + i]);
      controller.queueIndex = 0;
      controller.current = tracks.first;
      var calls = 0;
      try {
        controller.configureSmartFlow((queue, anchors) async {
          calls++;
          return {
            for (final i in anchors)
              i: Track(id: 'suggested-$i', title: 'Suggestion', artist: 'Demo'),
          };
        });
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(calls, 1);
        expect(controller.queue.length, 52);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(calls, 1);
      } finally {
        controller.dispose();
      }
    },
  );

  test(
    'audio clock does not invalidate library or repeat recommendation work',
    () async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      final dir = await Directory.systemTemp.createTemp(
        'music-time-performance-',
      );
      final audio = await File('${dir.path}/fixture.wav').writeAsBytes(wave());
      final controller = PlayerController();
      var events = 0, ticks = 0, recommendations = 0;
      controller.addListener(() => events++);
      controller.progress.addListener(() => ticks++);
      try {
        await controller.playQueue([
          for (final id in ['a', 'b'])
            Track(id: id, title: id, artist: 'Fixture', localPath: audio.path),
        ], 0);
        controller.configureSmartFlow((_, _) async {
          recommendations++;
          return {};
        });
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final before = events, work = recommendations;
        await Future<void>.delayed(const Duration(milliseconds: 1800));
        expect(ticks, greaterThan(3));
        expect(events, before, reason: 'position must not rebuild library');
        expect(recommendations, work);
        expect(controller.position, greaterThan(const Duration(seconds: 1)));
        expect(controller.buffering, isFalse);
        expect(controller.error, isNull);
        await controller.toggle();
        expect(events, greaterThan(before));
        await controller.seek(const Duration(milliseconds: 500));
        expect(controller.error, isNull);
      } finally {
        controller.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await dir.delete(recursive: true);
      }
    },
  );
}
