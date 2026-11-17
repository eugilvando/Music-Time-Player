import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/queue_panel.dart';
import 'package:music_time/presentation/fullscreen_now_playing.dart';
import 'package:music_time/presentation/player_bar.dart';
import 'package:music_time/lyrics/lyrics.dart';
import 'package:music_time/lyrics/lyrics_view.dart';

import 'support/flutter_sdk.dart';

void main() {
  setUpAll(
    () => MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    ),
  );
  Future<PlayerController> player(
    WidgetTester tester,
    int count,
    int index,
  ) async {
    final p = (await tester.runAsync(() async => PlayerController()))!;
    p.queue.addAll([
      for (var i = 0; i < count; i++)
        Track(id: 'track-$i', title: 'Faixa $i', artist: 'Artista fictício'),
    ]);
    p.queueKeys.addAll([for (var i = 0; i < count; i++) i + 100]);
    p.queueIndex = index;
    p.current = p.queue[index];
    addTearDown(p.dispose);
    return p;
  }

  Widget queue(PlayerController p) => QueuePanel(
    controller: p,
    onClose: () {},
    onSave: () async {},
    onSavePlaylist: () async {},
    onPlay: (_) async {},
    trackActions: (_, _) => const SizedBox(width: 24),
  );
  testWidgets(
    'queue follows current occurrence, yields to manual scrolling and resumes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = await player(tester, 80, 50);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: queue(p))));
      await tester.pumpAndSettle();
      expect(find.text('Faixa 50').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('queue.list')),
        const Offset(0, 350),
      );
      await tester.pumpAndSettle();
      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      final offset = list.scrollController!.offset;
      p.queueIndex = 70;
      p.current = p.queue[70];
      p.cycleRepeat();
      await tester.pumpAndSettle();
      expect(list.scrollController!.offset, closeTo(offset, .1));
      await tester.tap(find.byKey(const ValueKey('queue.current')));
      await tester.pumpAndSettle();
      expect(find.text('Faixa 70').hitTestable(), findsOneWidget);
      p.queueIndex = 4;
      p.current = p.queue[4];
      p.cycleRepeat();
      await tester.pumpAndSettle();
      expect(find.text('Faixa 4').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('album drop below last queue item appends in order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final p = await player(tester, 2, 0);
    const tracks = [
      Track(id: 'album-1', title: 'Um', artist: 'Demo'),
      Track(id: 'album-2', title: 'Dois', artist: 'Demo'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Draggable<List<Track>>(
                data: tracks,
                feedback: Text('Álbum'),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Text('Arrastar álbum'),
                ),
              ),
              Expanded(child: queue(p)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragFrom(
      tester.getCenter(find.text('Arrastar álbum')),
      tester.getCenter(find.byKey(const ValueKey('queue.drop.end'))) -
          tester.getCenter(find.text('Arrastar álbum')),
    );
    await tester.pumpAndSettle();
    expect(p.queue.map((t) => t.id), [
      'track-0',
      'track-1',
      'album-1',
      'album-2',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'full screen modes keep integrated controls and exit with Escape',
    (tester) async {
      SharedPreferences.setMockInitialValues({'visual.lyrics_online': false});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final p = await player(tester, 1, 0);
      final png = (await tester.runAsync(
        () => File('assets/branding/icon.png').readAsBytes(),
      ))!;
      p.current = Track(
        id: 'demo',
        title: 'Maré de Dentro',
        artist: 'Clara Horizonte',
        album: 'Entre Estações',
        cover: png,
      );
      for (final font in {
        'Inter': 'assets/fonts/Inter.ttf',
        'MaterialIcons': materialIconFontPath(),
        'Material Symbols Rounded': 'assets/fonts/MaterialSymbolsRounded.ttf',
      }.entries) {
        final data = (await tester.runAsync(
          () => File(font.value).readAsBytes(),
        ))!;
        await (FontLoader(
          font.key,
        )..addFont(Future.value(ByteData.sublistView(data)))).load();
      }
      var exits = 0;
      final boundary = GlobalKey();
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in [const Size(1440, 900), const Size(600, 700)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              fontFamily: 'Inter',
              colorSchemeSeed: const Color(0xffdf4a32),
            ),
            home: RepaintBoundary(
              key: boundary,
              child: FullscreenNowPlaying(
                controller: p,
                settings: settings,
                onExit: () => exits++,
                onQueue: () {},
                loadLyrics: (_, _) async => const LyricsDocument([
                  LyricLine('A cidade dorme devagar', at: Duration.zero),
                  LyricLine(
                    'E o vento vem me encontrar',
                    at: Duration(seconds: 10),
                  ),
                  LyricLine(
                    'Guardo o sol no teu olhar',
                    at: Duration(seconds: 20),
                  ),
                ]),
                controls: (_) => PlayerBar(
                  controller: p,
                  settings: settings,
                  favorite: false,
                  onFavorite: () {},
                  onDetails: () {},
                  onQueue: () {},
                  onExpand: () {},
                  onSave: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PlayerBar), findsNothing);
        expect(find.byType(LyricsView), findsNothing);
        expect(find.text('Maré de Dentro'), findsOneWidget);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        if (size.width > 1000) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('build/review-3.0.7').create(recursive: true);
            await File('build/review-3.0.7/fullscreen-cover.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        final toggle = tester.widget<SegmentedButton<bool>>(
          find.byKey(const ValueKey('fullscreen.mode')),
        );
        toggle.onSelectionChanged!({true});
        await tester.pumpAndSettle();
        expect(find.byType(LyricsView), findsOneWidget);
        expect(find.text('Maré de Dentro'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        if (size.width > 1000) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('build/review-3.0.7/fullscreen-lyrics.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        toggle.onSelectionChanged!({false});
        await tester.pumpAndSettle();
      }
      expect(exits, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
