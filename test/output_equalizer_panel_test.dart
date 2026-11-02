import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/platform/output_equalizer.dart';
import 'package:music_time/presentation/equalizer_panel.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/settings/parametric_eq.dart';

import 'output_equalizer_test.dart' show RecordingEqPlayer;
import 'parametric_eq_test.dart' show autoEqFixture;

void main() {
  testWidgets('output profile selector updates EQ and fits a narrow window', (
    tester,
  ) async {
    MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    );
    SharedPreferences.setMockInitialValues({
      'visual.eq_autoeq_profiles': jsonEncode({
        'Meu fone': ParametricEqProfile.parse(
          autoEqFixture,
          'Meu fone',
        ).toJson(),
      }),
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    final player = RecordingEqPlayer();
    final outputs = OutputEqualizer(
      player,
      settings,
      readOutput: () async => const AudioOutput('headphones', 'Fone USB'),
    );
    await outputs.refresh();
    await tester.runAsync(() async {
      final bytes = await File('assets/fonts/Inter.ttf').readAsBytes();
      await (FontLoader(
        'Inter',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });
    await tester.binding.setSurfaceSize(const Size(650, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter'),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ListenableBuilder(
                listenable: settings,
                builder: (context, _) => EqualizerPanel(
                  controller: player,
                  settings: settings,
                  outputs: outputs,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    expect(outputs.automatic, true);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('AutoEQ: Meu fone').last);
    await tester.pumpAndSettle();
    expect(player.profile, 'Meu fone');
    expect(player.enabled, true);
    expect(outputs.binding?['preset'], 'autoeq:Meu fone');
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/eq-output-profile.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    outputs.dispose();
    player.dispose();
    settings.dispose();
  });
}
