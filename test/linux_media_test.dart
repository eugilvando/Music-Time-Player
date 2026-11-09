import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_time/platform/linux_media.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';

import 'finalization_native_test.dart' show wave;

void main() {
  test(
    'MPRIS publishes metadata and handles pause, seek and queue changes on real session bus',
    () async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      final directory = await Directory.systemTemp.createTemp(
        'music-time-mpris-test-',
      );
      final file = await File('${directory.path}/fixture.wav')
          .writeAsBytes(wave());
      final player = PlayerController();
      final media = LinuxMedia(player, raise: () async {}, quit: () async {});
      final client = DBusClient.session();
      try {
        await player.restore(
          [
            for (final id in ['First', 'Second'])
              Track(
                id: id,
                title: id,
                artist: 'Fixture artist',
                album: 'Fixture album',
                localPath: file.path,
              ),
          ],
          0,
          Duration.zero,
        );
        await media.initialize();
        final remote = DBusRemoteObject(
          client,
          name: '${LinuxMedia.root}.MusicTime.instance$pid',
          path: DBusObjectPath('/org/mpris/MediaPlayer2'),
        );
        var metadata = await remote.getProperty(
          LinuxMedia.playback,
          'Metadata',
        );
        expect(metadata.toNative()['xesam:title'], 'First');
        expect(
          await remote.getProperty(LinuxMedia.root, 'DesktopEntry'),
          const DBusString('app.musictime.preview'),
        );
        await remote.callMethod(LinuxMedia.playback, 'Play', []);
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await remote.callMethod(LinuxMedia.playback, 'Pause', []);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(
          await remote.getProperty(LinuxMedia.playback, 'PlaybackStatus'),
          const DBusString('Paused'),
        );
        await remote.callMethod(LinuxMedia.playback, 'Next', []);
        metadata = await remote.getProperty(LinuxMedia.playback, 'Metadata');
        expect(metadata.toNative()['xesam:title'], 'Second');
        await remote.setProperty(
          LinuxMedia.playback,
          'Volume',
          const DBusDouble(.4),
        );
        expect(player.volume, 40);
        final before = player.current?.id;
        await remote.callMethod(LinuxMedia.playback, 'SetPosition', [
          DBusObjectPath('/obsolete'),
          const DBusInt64(500000),
        ]);
        expect(player.current?.id, before);
        expect(
          await remote.callMethod(LinuxMedia.root, 'Raise', []),
          isA<DBusMethodSuccessResponse>(),
        );
      } finally {
        await client.close();
        await media.dispose();
        player.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await directory.delete(recursive: true);
      }
    },
    skip:
        !Platform.isLinux ||
            Platform.environment['DBUS_SESSION_BUS_ADDRESS'] == null
        ? 'Requires Linux session bus'
        : false,
  );
}
