import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';

import 'finalization_native_test.dart' show wave;

void main() {
  test(
    'both features play the inserted track then continue the queue',
    () async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      final dir = await Directory.systemTemp.createTemp('music-time-flow-');
      final file = await File('${dir.path}/fixture.wav').writeAsBytes(wave());
      Track track(String id) =>
          Track(id: id, title: id, artist: 'Demo', localPath: file.path);
      final a = track('a'), b = track('b'), c = track('c'), d = track('d');
      final p = PlayerController();
      try {
        await p.restore([a, b], 0, Duration.zero);
        p.configureSmartFlow((_, _) async => {0: c});
        await p.prepareFlow();
        expect(p.queue, [a, c, b]);
        await p.next();
        expect(p.current?.id, 'c');
        expect(p.error, isNull);
        p.configureSmartFlow(null);
        expect(p.queue, [
          a,
          c,
          b,
        ]); // Preserve the currently playing suggestion.
        await p.next();
        p.continuous = (current, queue) async {
          expect(queue, [a, c, b]);
          expect(p.automaticIndices, {1});
          return [d];
        };
        await p.next(automatic: true);
        expect(p.current?.id, 'd');
        expect(p.automaticOrigin(3), 'queue');
        expect(p.queueKeys.toSet().length, p.queue.length);
        expect(p.error, isNull);
        await p.player.pause();
        p.configureSmartFlow((_, _) async => {});
        p.toggleShuffle();
        await p.prepareFlow();
        p.toggleShuffle();
        expect(p.queue, [a, c, b, d]);
      } finally {
        p.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await dir.delete(recursive: true);
      }
    },
    skip: Platform.environment['MUSIC_TIME_LIBMPV'] == null
        ? 'Native playback library required'
        : false,
  );
}
