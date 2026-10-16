import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/main.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/library_screen.dart';

import '../test/design_test.dart' show demoWave;
import '../test/support/flutter_sdk.dart';

Future<Uint8List> artwork(int index, String title, String artist) async {
  const palette = [
    0xffe97668,
    0xff638ff2,
    0xffa279d7,
    0xff5cbfac,
    0xffdda46b,
    0xff75b5d2,
    0xffd47ca0,
    0xff96b67c,
  ];
  final color = Color(palette[index % palette.length]);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const bounds = Rect.fromLTWH(0, 0, 512, 512);
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(color, Colors.black, .55)!, color],
      ).createShader(bounds),
  );
  for (var i = 0; i < 6; i++) {
    canvas.drawCircle(
      Offset(330 + i * 12, 130 + i * 25),
      140 - i * 15,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: .15 + i * .025),
    );
  }
  canvas.drawRect(
    const Rect.fromLTWH(0, 320, 512, 192),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Color(0xaa0d1719)],
      ).createShader(bounds),
  );
  void text(
    String value,
    Offset where,
    double size,
    FontWeight weight,
    Color color,
  ) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Segoe UI',
          color: color,
          fontSize: size,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 438);
    p.paint(canvas, where);
  }

  text(
    'MUSIC TIME / DEMO',
    const Offset(36, 35),
    15,
    FontWeight.w600,
    Colors.white70,
  );
  text(
    title.toUpperCase(),
    const Offset(36, 348),
    35,
    FontWeight.w700,
    Colors.white,
  );
  text(artist, const Offset(38, 445), 22, FontWeight.w400, Colors.white70);
  final picture = recorder.endRecording();
  final image = await picture.toImage(512, 512);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return data;
}

void main() {
  testWidgets('capture current UI with an isolated fictional library', (
    tester,
  ) async {
    debugPrint('DEMO initialize playback engine');
    MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    );
    // This is a rendering fixture, deliberately kept outside the baseline suite.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'visual.language': 'en',
      'visual.artist_photos': false,
      'visual.animations': false,
      'visual.reduce_motion': true,
      'visual.show_queue': false,
      'collections.favorites': ['playlist:1', 'artist:Aster Vale'],
      'visual.style': 'classic',
      'visual.home_mix_types': [
        'artists',
        'artist_radio',
        'favorites',
        'discover',
      ],
      'visual.home_sections': [
        'mixes',
        'continue',
        'favorite_albums',
        'favorite_playlists',
        'discover_albums',
        'recent_artists',
      ],
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => call.method == 'readAll'
              ? <String, String>{}
              : call.method == 'containsKey'
              ? false
              : null,
        );
    await tester.runAsync(() async {
      final fonts = Directory('${Platform.environment['WINDIR']}/Fonts');
      for (final family in ['Segoe UI', 'Ahem']) {
        final loader = FontLoader(family);
        for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
          loader.addFont(
            Future.value(
              ByteData.sublistView(
                await File('${fonts.path}/$name').readAsBytes(),
              ),
            ),
          );
        }
        await loader.load();
      }
      final icons = await File(materialIconFontPath()).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    });
    debugPrint('DEMO fonts ready');
    final settings = AppSettings(await SharedPreferences.getInstance());
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('music-time-public-demo-'),
    ))!;
    final wave = (await tester.runAsync(() => demoWave(directory)))!;
    await tester.runAsync(
      () => File('${directory.path}/demo.lrc').writeAsString(
        '[00:00.00]A little light across the water\n[00:20.00]We watch the morning open wide\n[00:45.00]The quiet rhythm brings us closer\n[01:10.00]A new horizon comes alive',
      ),
    );
    const artists = [
      'Aster Vale',
      'Northlight',
      'Mira Coast',
      'Paper Skies',
      'Arden',
      'Blue Atlas',
    ];
    const albums = [
      'Glass Horizon',
      'Soft Geometry',
      'Night Signals',
      'Open Circuits',
      'Quiet Tide',
      'Blue Hours',
      'Light Studies',
      'After the Rain',
      'Morning Lines',
      'Slow Orbit',
      'New Coordinates',
      'Golden Distance',
    ];
    const titles = [
      'First Light',
      'Between the Waves',
      'A New Horizon',
      'Afterglow',
    ];
    debugPrint('DEMO fixture storage ready');
    final tracks = <Track>[];
    for (var album = 0; album < albums.length; album++) {
      final artist = artists[album ~/ 2];
      final cover = (await tester.runAsync(
        () => artwork(album, albums[album], artist),
      ))!;
      for (var song = 0; song < 4; song++) {
        tracks.add(
          Track(
            id: 'demo-$album-$song',
            title: titles[song],
            artist: artist,
            albumArtist: artist,
            album: albums[album],
            genre: 'Ambient',
            year: 2021 + album % 5,
            trackNumber: song + 1,
            discNumber: 1,
            format: 'WAV',
            localPath: wave.path,
            fileName: 'demo.wav',
            cover: cover,
            duration: const Duration(minutes: 2),
            addedAt: DateTime(2026, 10, 1 + album),
          ),
        );
      }
    }
    debugPrint('DEMO artwork ready');
    await tester.runAsync(() async {
      await store.addTracks(tracks);
      await store.setFavorites(tracks.take(12).map((t) => t.id).toList(), true);
      for (var i = 0; i < 12; i++) {
        await store.recordHistory(
          tracks[i].id,
          DateTime.utc(2026, 10, 16, 12, i),
          const Duration(seconds: 90),
        );
      }
      await store.importPlaylist(
        'Evening Focus',
        tracks.take(16).map((t) => t.id).toList(),
      );
      await store.importPlaylist(
        'Slow Mornings',
        tracks.skip(12).take(16).map((t) => t.id).toList(),
      );
      await store.importPlaylist(
        'New Horizons',
        tracks.skip(24).map((t) => t.id).toList(),
      );
    });
    final boundary = GlobalKey();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    Future<void> settle([int rounds = 3]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 180)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    debugPrint('DEMO catalog ready');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MusicTimeApp(settings: settings, store: store),
      ),
    );
    debugPrint('DEMO app mounted');
    await settle(10);
    debugPrint('DEMO app settled');
    final dynamic state = tester.state(find.byType(LibraryScreen));
    final controller = state.controller as PlayerController;
    controller.queue.addAll(tracks.take(12));
    controller.queueKeys.addAll(List.generate(12, (i) => i));
    controller.queueIndex = 0;
    controller.current = tracks.first;
    controller.queueTitle = 'Evening Focus';
    controller.duration = const Duration(minutes: 2);
    controller.position = const Duration(seconds: 36);
    controller.toggleShuffle();
    controller.toggleShuffle();
    await settle();
    Future<void> navigate(String name) async {
      debugPrint('DEMO navigate $name');
      final target = find.byKey(ValueKey('navigation.$name'));
      await tester.ensureVisible(target);
      await tester.pump();
      await tester.tap(target);
      await settle(4);
    }

    Future<void> capture(String name) async {
      debugPrint('DEMO capture $name');
      await settle(5);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final out = Directory('docs/images');
        await out.create(recursive: true);
        await File('${out.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await navigate('home');
    await capture('home');
    await navigate('library');
    await capture('library');
    await navigate('albums');
    await capture('albums');
    await navigate('artists');
    await capture('artists');
    await navigate('playlists');
    await capture('playlists');
    await settings.updateVisual('show_queue', true);
    await navigate('nowPlaying');
    await capture('now-playing');
    await settings.updateVisual('show_queue', false);
    await navigate('settings');
    await capture('settings');
    await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
    await settle();
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(() async {
      await store.close();
      settings.dispose();
      final prefix =
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}music-time-public-demo-';
      if (!directory.absolute.path.startsWith(prefix)) {
        throw StateError('Unexpected demo temporary directory');
      }
      await directory.delete(recursive: true);
    });
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
