import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/playback_transition_settings.dart';
import 'package:music_time/presentation/settings_card.dart';

void main() {
  testWidgets(
    'crossfade modes persist and playback controls remain separated',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'visual.crossfade_seconds': 0.0,
        'visual.smart_play': true,
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      await tester.runAsync(() async {
        final bytes = await File('assets/fonts/Inter.ttf').readAsBytes();
        await (FontLoader(
          'Inter',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
      final boundary = GlobalKey();
      Widget page() => MaterialApp(
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter'),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SettingsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Crossfade'),
                        const SizedBox(height: 24),
                        CrossfadeSettings(settings: settings),
                      ],
                    ),
                  ),
                  SettingsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Play contínuo'),
                        const SizedBox(height: 24),
                        ContinuousPlaybackSettings(settings: settings),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(settings.crossfadeSetting, 'off');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Automático').last);
      await tester.pumpAndSettle();
      expect(AppSettings(settings.preferences).crossfadeSetting, 'auto');
      expect(find.text('Duração da transição'), findsNothing);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/settings-auto-wide.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual').last);
      await tester.pumpAndSettle();
      expect(settings.crossfadeSetting, 'manual');
      final style = find.ancestor(
        of: find.text('Estilo da transição'),
        matching: find.byType(PlaybackSettingField<String>),
      );
      final duration = find.byType(PlaybackSettingField<int>).first;
      expect(
        tester.getTopLeft(style).dy - tester.getBottomLeft(duration).dy,
        greaterThanOrEqualTo(23),
      );
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/settings-manual-narrow.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
