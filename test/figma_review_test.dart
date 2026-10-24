import 'support/flutter_sdk.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/main.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/design_preview.dart';
import 'package:music_time/presentation/library_screen.dart';
import 'package:music_time/presentation/player_bar.dart';
import 'package:music_time/presentation/playlists_dialog.dart';
import 'package:music_time/presentation/settings_dialog.dart';
import 'package:music_time/settings/app_settings.dart';

void main() {
  testWidgets(
    'Figma shell keeps playback across pages and swaps queue with lyrics',
    (tester) async {
      // media_kit debug retains native pointers in a temp file keyed by PID.
      // A cold, isolated capture worker may reuse a PID from a finished worker.
      // No player exists yet: discard only this process's stale pointer record.
      await tester.runAsync(() async {
        final stale = File(
          '${Directory.systemTemp.path}/com.alexmercerind.media_kit.NativeReferenceHolder.$pid',
        );
        if (await stale.exists()) await stale.delete();
      });
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => call.method == 'readAll'
                ? <String, String>{}
                : call.method == 'containsKey'
                ? false
                : null,
          );
      final prefs = await SharedPreferences.getInstance();
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mt-figma-test-'),
      ))!;
      final store = (await tester.runAsync(
        () => LibraryStore.open('${directory.path}/review.db'),
      ))!;
      for (final font in {
        'Material Symbols Rounded': 'MaterialSymbolsRounded',
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
      await tester.runAsync(
        () => prepareDesignPreview(directory, store, prefs),
      );
      await tester.runAsync(() async {
        final bytes = await File(materialIconFontPath()).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
      final settings = AppSettings(prefs);
      final boundary = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MusicTimeApp(settings: settings, store: store),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> capture(String name) async {
        await settle();
        expect(tester.takeException(), isNull, reason: name);
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/figma-review/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await settle();
      final dynamic state = tester.state(find.byType(LibraryScreen));
      for (var attempt = 0; attempt < 15 && state.loading; attempt++) {
        await settle();
      }
      expect(state.storageError, isNull);
      final controller = state.controller;
      final player = controller.player;
      expect(controller.queue.length, 18);
      expect(controller.playing, false);
      await capture('home');
      await tester.tap(find.byTooltip('Queue'));
      await settle();
      expect(find.byKey(const ValueKey('queue.floating')), findsOneWidget);
      final bar = tester.getRect(find.byType(PlayerBar));
      expect(bar.left, 0);
      expect(bar.right, 1440);
      await capture('home-queue');
      await tester.tap(find.byTooltip('Enable lyrics'));
      await settle();
      expect(find.byKey(const ValueKey('lyrics.side-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('queue.surface')), findsNothing);
      expect(
        tester.widget<LibraryScreen>(find.byType(LibraryScreen)).section.name,
        'home',
      );
      await capture('home-lyrics');
      await tester.tap(find.byTooltip('Disable lyrics'));
      await settle();
      for (final section in [
        'library',
        'artists',
        'albums',
        'favorites',
        'playlists',
        'history',
        'nowPlaying',
      ]) {
        await tester.tap(find.byKey(ValueKey('navigation.$section')));
        await settle();
        expect(
          identical(state, tester.state(find.byType(LibraryScreen))),
          true,
        );
        expect(identical(player, state.controller.player), true);
        await capture(section);
        if (section == 'library') {
          await tester.tap(
            find.byKey(const ValueKey('catalog.controls.toggle')),
          );
          await settle();
          await tester.tap(find.byTooltip('View'));
          await settle();
          await capture('view-modal');
          await tester.tap(find.text('Close').last);
          await settle();
          await tester.tap(find.byTooltip('Page filters'));
          await settle();
          await capture('filter-modal');
          await tester.tap(find.text('Cancel').last);
          await settle();
          await tester.tap(
            find.byKey(const ValueKey('catalog.controls.toggle')),
          );
          await settle();
        }
        if (section == 'artists') {
          await tester.tap(find.text('Northbound').first);
          await settle();
          await capture('artist-details');
        }
        if (section == 'albums') {
          await tester.tap(find.text('After the Rain').first);
          await settle();
          await capture('album-details');
        }
        if (section == 'playlists') {
          await tester.tap(
            find.byKey(const ValueKey('playlists.controls.toggle')),
          );
          await settle();
          await tester.tap(find.byKey(const ValueKey('playlists.view')));
          await settle();
          await tester.tap(find.text('Cards').first);
          await settle();
          expect(
            tester.widget<PlaylistsPage>(find.byType(PlaylistsPage)).store,
            same(store),
          );
          await capture('playlists-compact');
        }
      }
      for (final style in [
        'classic',
        'vinyl',
        'minimal',
        'cover_only',
        'lyrics_only',
      ]) {
        await settings.updateVisual('style', style);
        await capture('now-$style');
        expect(controller.queue.length, 18);
        expect(controller.playing, false);
      }
      await settings.updateVisual('sidebar_collapsed', true);
      await capture('sidebar-collapsed');
      await tester.tap(find.byKey(const ValueKey('navigation.settings')));
      await settle();
      for (final category in SettingsCategory.values) {
        final item = find.byKey(ValueKey('settings.${category.name}'));
        await tester.ensureVisible(item);
        await tester.tap(item);
        await capture('settings-${category.name}');
        expect(identical(player, state.controller.player), true);
      }
      await tester.tap(find.byKey(const ValueKey('navigation.nowPlaying')));
      await settle();
      await settings.persist('theme', 'light');
      settings.mode = ThemeMode.light;
      await settings.updateVisual('style', 'classic');
      await capture('light');
      tester.view.physicalSize = const Size(600, 700);
      await capture('narrow');
      await tester.pumpWidget(const SizedBox());
      await settle();
      await tester.pump(const Duration(seconds: 6));
      await settle();
      settings.dispose();
      await tester.runAsync(store.close);
    },
    tags: ['design-preview'],
  );
}
