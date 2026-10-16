import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/main.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/library_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/settings/equalizer_presets.dart';

void main() {
  final library = Platform.environment['MUSIC_TIME_LIBMPV'];
  test(
    'motor Windows restaura pausado, reproduz e faz seek em WAV real',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final directory = await Directory.systemTemp.createTemp(
        'music-time-audio-',
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
      await File('${directory.path}/silence.lrc')
          .writeAsString('[00:00.00]Letra local de teste');
      final controller = PlayerController();
      try {
        final track = Track(
          id: 'wave',
          title: 'Teste',
          artist: 'Teste',
          localPath: file.path,
        );
        await controller.restore([track], 0, const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(controller.error, isNull);
        expect(controller.playing, isFalse);
        expect(controller.session, isNull);
        expect(controller.duration.inSeconds, 4);
        final native = controller.player.platform as NativePlayer;
        for (final preset in equalizerPresets.values) {
          await controller.setEqualizer(true, preset);
          expect(await native.getProperty('af'), contains('equalizer'));
          expect(controller.playing, isFalse);
          expect(controller.queueIndex, 0);
        }
        await controller.setEqualizer(true, [2, 0, -2, 0, 0]);
        expect(await native.getProperty('af'), contains('equalizer'));
        expect(controller.queueIndex, 0);
        expect(controller.playing, isFalse);
        await controller.setEqualizer(false, [0, 0, 0, 0, 0]);
        expect(await native.getProperty('af'), isEmpty);
        final started = controller.player.stream.playing.firstWhere(
          (value) => value,
        );
        await controller.toggle();
        await started.timeout(const Duration(seconds: 10));
        expect(controller.session, isNotNull);
        await controller.seek(const Duration(seconds: 2));
        expect(controller.seeking, isFalse);
        await controller.player.pause();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(controller.playing, isFalse);
        final key = controller.queueKeys.single;
        await controller.enqueue(track, asNext: true);
        expect(controller.queue.length, 2);
        controller.reorderQueue(0, 1);
        expect(controller.queueIndex, 1);
        expect(controller.queueKeys[1], key);
        final beforePosition = controller.position;
        final beforeSession = controller.session!;
        await controller.refreshMetadata([
          Track(
            id: track.id,
            title: 'Título atualizado',
            artist: 'Artista atualizado',
            album: 'Álbum atualizado',
            localPath: track.localPath,
          ),
        ]);
        expect(controller.current!.title, 'Título atualizado');
        expect(controller.queue.map((t) => t.album), [
          'Álbum atualizado',
          'Álbum atualizado',
        ]);
        expect(controller.queueIndex, 1);
        expect(controller.queueKeys[1], key);
        expect(controller.playing, false);
        expect(controller.position, beforePosition);
        expect(controller.session!.startedAt, beforeSession.startedAt);
        expect(controller.session!.listened, beforeSession.listened);
        await controller.removeQueueEntry(0);
        expect(controller.queueKeys.single, key);
        await controller.clearQueue();
        expect(controller.current, isNull);
        expect(controller.queue, isEmpty);
      } finally {
        controller.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await directory.delete(recursive: true);
      }
    },
    skip: library == null
        ? 'Execute com MUSIC_TIME_LIBMPV apontando para libmpv-2.dll do build Windows.'
        : false,
  );
  testWidgets('redimensionamento e tema preservam biblioteca e player', (
    tester,
  ) async {
    MediaKit.ensureInitialized(libmpv: library);
    SharedPreferences.setMockInitialValues({});
    final resources = await tester.runAsync(
      () async => (
        await SharedPreferences.getInstance(),
        await LibraryStore.open(':memory:'),
      ),
    );
    final settings = AppSettings(resources!.$1);
    final store = resources.$2;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MusicTimeApp(settings: settings, store: store));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    final original = tester.state(find.byType(LibraryScreen));
    for (final size in [
      const Size(480, 600),
      const Size(800, 600),
      const Size(1280, 720),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(
        identical(tester.state(find.byType(LibraryScreen)), original),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const ValueKey('navigation.settings')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const ValueKey('settings.appearance')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.ensureVisible(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Light').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(settings.mode, ThemeMode.light);
    expect(
      identical(tester.state(find.byType(LibraryScreen)), original),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('navigation.library')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.runAsync(store.close);
    settings.dispose();
  }, skip: library == null);
}
