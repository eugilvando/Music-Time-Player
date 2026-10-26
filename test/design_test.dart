import 'support/flutter_sdk.dart';

import 'dart:io';
import 'dart:typed_data';
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
import 'package:music_time/presentation/settings_dialog.dart';
import 'package:music_time/presentation/sources_dialog.dart';
import 'package:music_time/presentation/now_playing_artwork.dart';
import 'package:music_time/presentation/design_icon.dart';

Future<Uint8List> demoCover(Color color, int number) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 256, 256),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color, Colors.black],
      ).createShader(const Rect.fromLTWH(0, 0, 256, 256)),
  );
  for (var i = 0; i < 6; i++) {
    canvas.drawRect(
      Rect.fromLTWH(i * 44.0, 150 - i * 12, 30, 150),
      Paint()..color = Colors.black.withValues(alpha: .38),
    );
  }
  final painter = TextPainter(
    text: TextSpan(
      text: 'DEMO\nMUSIC TIME\n$number',
      style: const TextStyle(
        fontFamily: 'Segoe UI',
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 230);
  painter.paint(canvas, const Offset(16, 20));
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

Future<File> demoWave(Directory directory) async {
  final bytes = Uint8List(44 + 8000 * 2 * 120);
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
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, bytes.length - 44, Endian.little);
  return File('${directory.path}/demo.wav').writeAsBytes(bytes);
}

void main() {
  final native = Platform.environment['MUSIC_TIME_LIBMPV'];
  testWidgets('cassete mantém proporção em área quadrada e preview pequeno', (
    tester,
  ) async {
    for (final width in [124.0, 300.0, 420.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: width,
                child: const NowPlayingArtwork(style: 'cassette'),
              ),
            ),
          ),
        ),
      );
      final ratio = find.descendant(
        of: find.byType(NowPlayingArtwork),
        matching: find.byType(AspectRatio),
      );
      final size = tester.getSize(ratio);
      expect(size.width / size.height, closeTo(1.55, .01));
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('animações param ao pausar e respeitam redução de movimento', (
    tester,
  ) async {
    Future<void> render(
      bool playing, {
      bool reduced = false,
      bool system = false,
    }) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: system),
          child: Scaffold(
            body: SizedBox(
              width: 300,
              height: 240,
              child: NowPlayingArtwork(
                style: 'vinyl',
                playing: playing,
                reduceMotion: reduced,
              ),
            ),
          ),
        ),
      ),
    );
    await render(true);
    await tester.pump(const Duration(seconds: 1));
    final turns = tester
        .widget<RotationTransition>(
          find
              .descendant(
                of: find.byType(NowPlayingArtwork),
                matching: find.byType(RotationTransition),
              )
              .first,
        )
        .turns;
    expect(turns.value, greaterThan(0));
    await render(false);
    final stopped = turns.value;
    await tester.pump(const Duration(seconds: 1));
    expect(turns.value, stopped);
    await render(true, reduced: true);
    await tester.pump(const Duration(seconds: 1));
    expect(turns.value, stopped);
    await render(true, system: true);
    await tester.pump(const Duration(seconds: 1));
    expect(turns.value, stopped);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'design preserva controlador, fila e posição em todas as páginas e produz prévias',
    (tester) async {
      MediaKit.ensureInitialized(libmpv: native);
      SharedPreferences.setMockInitialValues({'visual.language': 'pt'});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => call.method == 'readAll'
                ? <String, String>{}
                : call.method == 'containsKey'
                ? false
                : null,
          );
      final settings = AppSettings(
        (await tester.runAsync(SharedPreferences.getInstance))!,
      );
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('music-time-design-'),
      ))!;
      final wave = (await tester.runAsync(() => demoWave(directory)))!;
      for (final font in {
        'Inter': 'Inter',
        'Bricolage Grotesque': 'BricolageGrotesque',
      }.entries) {
        await tester.runAsync(() async {
          final bytes = await File('assets/fonts/${font.value}.ttf')
              .readAsBytes();
          await (FontLoader(
            font.key,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        });
      }
      final windows = Platform.environment['WINDIR'];
      if (windows != null) {
        final font = File('$windows/Fonts/segoeui.ttf');
        final bytes = await tester.runAsync(font.readAsBytes);
        await tester.runAsync(() async {
          await (FontLoader(
            'Segoe UI',
          )..addFont(Future.value(ByteData.sublistView(bytes!)))).load();
        });
      }
      final iconFont = File(materialIconFontPath());
      await tester.runAsync(() async {
        final bytes = await iconFont.readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
      await tester.runAsync(
        () => File('${directory.path}/demo.lrc').writeAsString(
          '[00:00.00]Demonstração de letras locais\n[00:02.00]Linha de teste sincronizada\n[00:05.00]<00:05.00>Tempo <00:05.50>real\n[00:08.00]Última linha',
        ),
      );
      final tracks = <Track>[];
      for (var i = 0; i < 6; i++) {
        final cover = await tester.runAsync(
          () => demoCover(Colors.primaries[i * 2], i + 1),
        );
        tracks.add(
          Track(
            id: 'demo-$i',
            title: 'DEMO · Faixa ${i + 1}',
            artist: 'Artista de teste ${i + 1}',
            album: 'DEMO · Álbum ${i + 1}',
            year: 2020 + i,
            localPath: wave.path,
            cover: cover,
            duration: const Duration(seconds: 120),
          ),
        );
      }
      await tester.runAsync(() => store.addTracks(tracks));

      final boundary = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MusicTimeApp(settings: settings, store: store),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump(const Duration(milliseconds: 350));
      }

      await settle();
      final original = tester.state(find.byType(LibraryScreen));
      final controller = (original as dynamic).controller as PlayerController;
      for (
        var attempt = 0;
        attempt < 12 && (original as dynamic).loading;
        attempt++
      ) {
        await settle();
      }
      expect((original as dynamic).storageError, isNull);
      // Render fixtures are explicitly DEMO. Native play/pause/seek are covered separately.
      controller.queue.addAll(tracks);
      controller.queueKeys.addAll(
        List.generate(tracks.length, (index) => index),
      );
      controller.queueIndex = 0;
      controller.current = tracks.first;
      controller.duration = const Duration(seconds: 120);
      controller.position = const Duration(seconds: 2);
      controller.toggleShuffle();
      controller.toggleShuffle();
      await settle();
      final player = controller.player;
      final listening = controller.session;
      Future<void> navigate(String section) async {
        final target = find.byKey(ValueKey('navigation.$section'));
        final shell = tester.state<ScaffoldState>(find.byType(Scaffold).first);
        if (find.byTooltip('Menu').evaluate().isNotEmpty &&
            !shell.isDrawerOpen) {
          await tester.tap(find.byTooltip('Menu'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pump(const Duration(milliseconds: 350));
        }
        final scrollable = find
            .descendant(
              of: find.byKey(const ValueKey('navigation.sidebar')),
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pump();
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(target, 160, scrollable: scrollable);
        }
        await tester.ensureVisible(target);
        await tester.pump();
        await tester.tap(target);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 350));
        await settle();
        expect(
          tester.widget<LibraryScreen>(find.byType(LibraryScreen)).section.name,
          section,
        );
        expect(
          identical(tester.state(find.byType(LibraryScreen)), original),
          isTrue,
        );
        expect(identical(controller.player, player), isTrue);
        expect(identical(controller.session, listening), isTrue);
      }

      Future<void> capture(String name) async {
        if (Platform.environment['MUSIC_TIME_CAPTURE_DESIGN'] != '1') return;
        // Let real SQLite/cover futures finish after fake-time widget frames.
        for (var attempt = 0; attempt < 10; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
        // Page rendering starts separate cover reads and image decoding.
        for (var attempt = 0; attempt < 2; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pump();
        }
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render
              .toImage(pixelRatio: 1)
              .timeout(const Duration(seconds: 10));
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final folder = Directory('build/design-previews');
          await folder.create(recursive: true);
          await File('${folder.path}/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await navigate('library');
      expect(find.text('Fila de reprodução'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byTooltip('Fechar fila'));
      await settle();
      expect(find.text('Fila de reprodução'), findsNothing);
      await tester.tap(find.byTooltip('Fila'));
      await settle();
      expect(find.text('Fila de reprodução'), findsOneWidget);
      expect(controller.queue.length, 6);
      await tester.tap(find.byTooltip('Recolher barra lateral'));
      await settle();
      expect(find.byKey(const ValueKey('navigation.sidebar')), findsOneWidget);
      expect(find.byKey(const ValueKey('navigation.downloads')), findsNothing);
      expect(find.byKey(const ValueKey('navigation.history')), findsOneWidget);
      expect(find.byTooltip('Expandir barra lateral'), findsOneWidget);
      expect(settings.preferences.getBool('visual.sidebar_collapsed'), isTrue);
      expect(
        identical(tester.state(find.byType(LibraryScreen)), original),
        isTrue,
      );
      expect(identical(controller.player, player), isTrue);
      expect(controller.queue.length, 6);
      final settingsFooter = tester.getRect(
        find.byKey(const ValueKey('navigation.settings.footer')),
      );
      final settingsIcon = find.descendant(
        of: find.byKey(const ValueKey('navigation.settings')),
        matching: find.byType(MtIcon),
      );
      expect(
        tester.getCenter(settingsIcon).dx,
        closeTo(settingsFooter.center.dx, .1),
      );
      expect(
        tester.getCenter(settingsIcon).dy,
        closeTo(settingsFooter.center.dy, .1),
      );
      await capture('sidebar-compact');
      await tester.tap(find.byTooltip('Expandir barra lateral'));
      await settle();
      expect(find.byKey(const ValueKey('navigation.sidebar')), findsOneWidget);
      expect(settings.preferences.getBool('visual.sidebar_collapsed'), isFalse);
      await navigate('nowPlaying');
      expect(find.byKey(const ValueKey('page.heading')), findsNothing);
      for (final style in [
        'classic',
        'vinyl',
        'minimal',
        'cover_only',
        'lyrics_only',
      ]) {
        await settings.updateVisual('style', style);
        await settle();
        expect(controller.playing, isFalse);
        expect(controller.queue.length, 6);
        expect(controller.current?.id, 'demo-0');
        expect(controller.error, isNull);
        expect(tester.takeException(), isNull);
        await capture('now-playing-$style');
      }
      await settings.updateVisual('style', 'minimal');
      await settle();
      await tester.tap(find.byTooltip('Ativar letras'));
      await settle();
      controller.position = const Duration(seconds: 5);
      controller.toggleShuffle();
      controller.toggleShuffle();
      await settle();
      for (
        var attempt = 0;
        attempt < 10 && find.textContaining('Tempo').evaluate().isEmpty;
        attempt++
      ) {
        await settle();
      }
      expect(find.textContaining('Tempo', findRichText: true), findsWidgets);
      await settings.setLyricsOffset('demo-0', 500);
      await settle();
      expect(find.text('Ajuste: 500 ms'), findsOneWidget);
      await settings.setLyricsOffset('demo-0', 0);
      controller.position = const Duration(milliseconds: 5500);
      controller.toggleShuffle();
      controller.toggleShuffle();
      await settle();
      final wordLine = find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.textSpan?.toPlainText() == 'Tempo real',
      );
      final span = tester.widget<Text>(wordLine).textSpan as TextSpan;
      expect(
        (span.children!.last as TextSpan).style!.color,
        Theme.of(tester.element(wordLine)).colorScheme.primary,
      );
      await capture('now-playing-lyrics');
      final lyricsPosition = controller.position;
      await tester.tap(find.byTooltip('Desativar letras'));
      await settle();
      expect(find.byTooltip('Ativar letras'), findsOneWidget);
      expect(settings.nowPlayingStyle, 'minimal');
      expect(find.text('Ajuste: 0 ms'), findsNothing);
      expect(controller.position, lyricsPosition);
      expect(controller.queue.length, 6);
      await tester.tap(find.byTooltip('Ativar letras'));
      await settle();
      expect(find.byTooltip('Desativar letras'), findsOneWidget);
      for (
        var attempt = 0;
        attempt < 10 && find.text('Ajuste: 0 ms').evaluate().isEmpty;
        attempt++
      ) {
        await settle();
      }
      expect(find.text('Ajuste: 0 ms'), findsOneWidget);
      expect(identical(controller.player, player), isTrue);
      for (final section in [
        'home',
        'library',
        'artists',
        'albums',
        'playlists',
        'history',
        'settings',
      ]) {
        await navigate(section);
        expect(
          find.byKey(const ValueKey('app.global-background')),
          findsOneWidget,
        );
        if (section == 'settings' || section == 'nowPlaying') {
          expect(find.byKey(const ValueKey('page.heading')), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await capture(section);
      }
      await tester.runAsync(() => settings.setLanguage('en'));
      await settle();
      expect(find.text('General and appearance'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
      await capture('settings-english');
      for (final section in [
        'data',
        'lastfm',
        'onedrive',
        'downloads',
        'about',
      ]) {
        final item = find.byKey(ValueKey('settings.$section'));
        await tester.ensureVisible(item);
        await tester.tap(item);
        await settle();
        expect(tester.takeException(), isNull);
        await capture('settings-$section-english');
      }
      await navigate('home');
      await capture('home-english');
      await navigate('albums');
      if (find.byKey(const ValueKey('catalog.view')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const ValueKey('catalog.controls.toggle')));
        await settle();
      }
      await tester.tap(find.byKey(const ValueKey('catalog.view')));
      await settle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      await capture('view-styles-english');
      await tester.tap(find.text('Close').last);
      await settle();
      await navigate('nowPlaying');
      await capture('now-playing-english');
      await tester.runAsync(() => settings.setLanguage('pt'));
      await settle();
      await navigate('artists');
      await tester.tap(find.text('Artista de teste 1').first);
      await settle();
      expect(
        find.byKey(const ValueKey('catalog.controls.toggle')),
        findsNothing,
      );
      expect(find.text('Discografia'), findsOneWidget);
      expect(find.text('DEMO · Álbum 1'), findsWidgets);
      await capture('artist-details');
      await tester.ensureVisible(find.text('DEMO · Álbum 1').first);
      await settle();
      await tester.tap(find.text('DEMO · Álbum 1').first);
      await settle();
      expect(
        find.byKey(const ValueKey('catalog.controls.toggle')),
        findsNothing,
      );
      expect(find.text('DEMO · Faixa 1'), findsWidgets);
      await capture('album-details');
      await tester.tap(find.byTooltip('Voltar'));
      await settle();
      expect(find.text('DEMO · Álbum 1'), findsWidgets);
      await tester.ensureVisible(find.byTooltip('Voltar'));
      await tester.tap(find.byTooltip('Voltar'));
      await settle();
      await navigate('settings');
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings.onedrive')),
      );
      await tester.tap(find.byKey(const ValueKey('settings.onedrive')));
      await settle();
      final addSourceMenu = find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuButton<String> &&
            widget.tooltip == 'Adicionar fonte',
      );
      for (
        var attempt = 0;
        attempt < 100 &&
            !tester.widget<PopupMenuButton<String>>(addSourceMenu).enabled;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(
        tester.widget<PopupMenuButton<String>>(addSourceMenu).enabled,
        true,
      );
      await tester.tap(find.byTooltip('Adicionar fonte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OneDrive pessoal'));
      await tester.pumpAndSettle();
      await settle();
      expect(find.byType(ProviderSettingsPage), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Conectar pelo navegador'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(SettingsPage),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      );
      expect(find.text('Conectar pelo navegador'), findsOneWidget);
      expect(find.text('ID do aplicativo (cliente)'), findsNothing);
      expect(find.text('Alternativa: conectar por código'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await capture('onedrive');
      for (final scale in [1.0, 1.5, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final size in [
          const Size(480, 600),
          const Size(800, 600),
          const Size(1280, 720),
        ]) {
          tester.view.physicalSize = size;
          await settle();
          for (final section in [
            'nowPlaying',
            'home',
            'library',
            'artists',
            'albums',
            'settings',
          ]) {
            await navigate(section);
            expect(
              tester.takeException(),
              isNull,
              reason: '$section | $size | escala $scale',
            );
          }
        }
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();

      await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.runAsync(store.close);
      settings.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    },
    skip: native == null,
  );
}
