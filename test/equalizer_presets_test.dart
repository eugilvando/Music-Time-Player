import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/equalizer_panel.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/settings/equalizer_presets.dart';

void main() {
  test('presets respeitam bandas e backup rejeita valores inválidos', () {
    expect(equalizerPresets.length, 9);
    expect(validEqualizerPresets(equalizerPresets), isTrue);
    expect(
      validEqualizerPresets({
        'Bad': [0, 0, 0, 0, 13],
      }),
      isFalse,
    );
    expect(
      AppData.validPreferenceType('visual.eq_presets', '{"Meu":[1,2,3,4,5]}'),
      isTrue,
    );
    expect(
      AppData.validPreferenceType('visual.eq_presets', '{"Meu":[1,2]}'),
      isFalse,
    );
    expect(decodeEqualizerPresets('invalid'), isEmpty);
  });

  testWidgets('salva e exclui preset próprio e restaura em novo settings', (
    tester,
  ) async {
    MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    );
    SharedPreferences.setMockInitialValues({'visual.eq_60': 3.0});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final controller = PlayerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EqualizerPanel(controller: controller, settings: settings),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Salvar preset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Meu som');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(
      decodeEqualizerPresets(
        settings.visualChoice('eq_presets', '{}'),
      )['Meu som'],
      [3, 0, 0, 0, 0],
    );
    final restored = AppSettings(settings.preferences);
    expect(
      decodeEqualizerPresets(restored.visualChoice('eq_presets', '{}')).keys,
      ['Meu som'],
    );
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final backup = (await tester.runAsync(
      () => AppData.backup(store, settings.preferences),
    ))!;
    expect(
      AppData.parse(backup)['preferences']['visual.eq_presets'],
      contains('Meu som'),
    );
    await tester.runAsync(store.close);
    await tester.tap(find.text('Excluir preset'));
    await tester.pumpAndSettle();
    expect(
      decodeEqualizerPresets(settings.visualChoice('eq_presets', '{}')),
      isEmpty,
    );
    expect(settings.visualNumber('eq_60', 0), 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    settings.dispose();
    restored.dispose();
  });
}
