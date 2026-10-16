import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/platform/system_accent.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/persistence/app_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> colorEvent(int color) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      'music_time/appearance',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('accentChanged', color),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  test('acento acompanha eventos e preserva a cor manual', () async {
    SharedPreferences.setMockInitialValues({
      'accent': 0xFF448AFF,
      'visual.system_accent': true,
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    messenger.setMockMethodCallHandler(
      SystemAccentController.channel,
      (_) async => 0xff123456,
    );
    final service = SystemAccentController(settings);
    expect(await service.initialize(), isTrue);
    expect(settings.effectiveAccent, 0xff123456);
    await colorEvent(0xffabcdef);
    expect(settings.effectiveAccent, 0xffabcdef);
    await settings.updateVisual('system_accent', false);
    expect(settings.effectiveAccent, 0xFF448AFF);
    expect(settings.preferences.getInt('accent'), 0xFF448AFF);
    expect(AppData.validPreferenceType('visual.system_accent', true), isTrue);
    expect(
      AppData.validPreferenceType('visual.system_accent', 'invalid'),
      isFalse,
    );
    service.dispose();
    settings.dispose();
    messenger.setMockMethodCallHandler(SystemAccentController.channel, null);
  });
  test('canal indisponível usa fallback sem apagar a preferência', () async {
    SharedPreferences.setMockInitialValues({'visual.system_accent': true});
    final settings = AppSettings(await SharedPreferences.getInstance());
    messenger.setMockMethodCallHandler(
      SystemAccentController.channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    final service = SystemAccentController(settings);
    expect(await service.initialize(), isFalse);
    expect(settings.effectiveAccent, settings.accent);
    settings.receiveSystemAccent(1);
    expect(settings.systemAccent, isNull);
    expect(settings.visualBool('system_accent'), isTrue);
    service.dispose();
    settings.dispose();
    messenger.setMockMethodCallHandler(SystemAccentController.channel, null);
  });
}
