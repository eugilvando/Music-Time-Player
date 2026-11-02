import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/application/fade_analysis.dart';
import 'package:music_time/library/smart_play.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/settings/parametric_eq.dart';

import 'parametric_eq_test.dart' show autoEqFixture;

void main() {
  const a = Track(id: 'a', artist: 'One', title: 'A', year: 1993);
  const b = Track(id: 'b', artist: 'One', title: 'B', year: 2008);
  const c = Track(id: 'c', artist: 'Two', title: 'C', year: 1999);
  const d = Track(id: 'd', artist: 'Two', title: 'D', year: 1995);
  test('continuous modes use eligible catalog, credits and decades', () {
    List<String> ids(String mode) => smartTracks(
      [a, b, c, d],
      a,
      [a],
      mode: mode,
      random: Random(7),
    ).map((t) => t.id).toList();
    expect(ids('artist'), ['b']);
    expect(ids('era').toSet(), {'c', 'd'});
    expect(ids('double').first, 'b');
    expect(ids('shuffle').toSet(), {'b', 'c', 'd'});
    expect(
      smartTracks(
        [a, b, c, d],
        a,
        [a],
        mode: 'shuffle',
        offlineOnly: true,
        offline: {'d'},
      ),
      [d],
    );
  });
  final lib = Platform.environment['MUSIC_TIME_LIBMPV'];
  for (final mode in ['fixed', 'smart', 'mix', 'auto']) {
    test(
      'native local overlap, queue identity, seek and pause: $mode',
      () async {
        MediaKit.ensureInitialized(libmpv: lib);
        final directory = await Directory.systemTemp.createTemp(
          'music-time-fade-',
        );
        final bytes = Uint8List(44 + 44100 * 2 * 4);
        final data = ByteData.sublistView(bytes);
        void text(int offset, String value) =>
            bytes.setRange(offset, offset + value.length, value.codeUnits);
        text(0, 'RIFF');
        data.setUint32(4, bytes.length - 8, Endian.little);
        text(8, 'WAVE');
        text(12, 'fmt ');
        data.setUint32(16, 16, Endian.little);
        data.setUint16(20, 1, Endian.little);
        data.setUint16(22, 1, Endian.little);
        data.setUint32(24, 44100, Endian.little);
        data.setUint32(28, 88200, Endian.little);
        data.setUint16(32, 2, Endian.little);
        data.setUint16(34, 16, Endian.little);
        text(36, 'data');
        data.setUint32(40, bytes.length - 44, Endian.little);
        final file = await File('${directory.path}/silence.wav')
            .writeAsBytes(bytes);

        final controller = PlayerController()
          ..fadeSeconds = 2
          ..fadeMode = mode;
        try {
          final tracks = [
            for (final name in ['a', 'b', 'c'])
              Track(id: name, title: name, artist: name, localPath: file.path),
          ];
          expect(
            await smartOverlapMs(file.path, file.path, 2, mixOnly: true),
            2000,
          );
          if (mode == 'auto') {
            await controller.setParametricEqualizer(
              true,
              ParametricEqProfile.parse(autoEqFixture, 'Overlap'),
            );
          }
          await controller.playQueue(tracks, 0);
          final original = controller.player;
          final session = controller.session;
          await controller.insertTracks([tracks.last], 0);
          expect(controller.queueIndex, 1);
          expect(controller.session, same(session));
          for (
            var i = 0;
            i < 100 && identical(controller.player, original);
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(
            controller.player,
            isNot(same(original)),
            reason: 'should overlap before ordinary EOF',
          );
          if (mode == 'auto') {
            final native = controller.player.platform as NativePlayer;
            expect(await native.getProperty('af'), contains('bass'));
            expect(await native.getProperty('af'), contains('treble'));
          }
          expect(controller.current!.id, 'b');
          expect(controller.queueIndex, 2);
          await controller.seek(const Duration(milliseconds: 300));
          await controller.toggle();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          expect(controller.playing, false);
          expect(controller.error, isNull);
          expect(controller.transitioning, isFalse);
          controller.toggleShuffle();
          final activeKey = controller.queueKeys[controller.queueIndex];
          await controller.insertTracks([tracks.first, tracks.last], 0);
          expect(controller.queueKeys[controller.queueIndex], activeKey);
          controller.toggleShuffle();
          expect(controller.queueKeys[controller.queueIndex], activeKey);
          expect(controller.queueKeys.toSet().length, controller.queue.length);
          final album = [
            for (final name in ['one', 'two'])
              Track(
                id: name,
                title: name,
                artist: 'Band',
                album: 'Record',
                localPath: file.path,
              ),
          ];
          await controller.playQueue(album, 0);
          final albumPlayer = controller.player;
          await Future<void>.delayed(const Duration(milliseconds: 2600));
          expect(controller.player, same(albumPlayer));
          expect(controller.current!.id, 'one');
          expect(controller.transitioning, isFalse);
          await controller.clearQueue();
        } finally {
          controller.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await directory.delete(recursive: true);
        }
      },
      skip: lib == null ? 'Native libmpv required' : false,
    );
  }
}
