import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/platform/output_equalizer.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/settings/parametric_eq.dart';

import 'parametric_eq_test.dart' show autoEqFixture;

class RecordingEqPlayer extends PlayerController {
  bool enabled = false;
  String? profile;
  List<double>? gains;
  @override
  Future<void> setEqualizer(bool value, List<double> levels) async {
    enabled = value;
    profile = null;
    gains = List.of(levels);
  }

  @override
  Future<void> setParametricEqualizer(
    bool value,
    ParametricEqProfile preset,
  ) async {
    enabled = value;
    profile = preset.name;
    gains = null;
  }
}

void main() {
  test('device profiles switch, unknown outputs disable EQ, mappings survive restart', () async {
    MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    );
    final profile = ParametricEqProfile.parse(autoEqFixture, 'Headphones');
    SharedPreferences.setMockInitialValues({
      'visual.eq_autoeq_profiles': jsonEncode({'Headphones': profile.toJson()}),
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    final player = RecordingEqPlayer();
    AudioOutput? output = const AudioOutput('a', 'Headphones');
    final coordinator = OutputEqualizer(
      player,
      settings,
      readOutput: () async => output,
    );
    try {
      await coordinator.refresh();
      await coordinator.setAutomatic(true);
      await coordinator.bindPreset('autoeq:Headphones');
      expect(player.enabled, isTrue);
      expect(player.profile, 'Headphones');
      output = const AudioOutput('b', 'Speakers');
      await coordinator.refresh();
      expect(player.enabled, isFalse);
      await coordinator.bindPreset('builtin:Rock');
      expect(player.enabled, isTrue);
      expect(player.gains, [4, 2, -2, 3, 4]);
      output = const AudioOutput('a', 'Headphones');
      await coordinator.refresh();
      expect(player.profile, 'Headphones');
      final restored = OutputEqualizer(
        player,
        AppSettings(settings.preferences),
        readOutput: () async => output,
      );
      await restored.refresh();
      expect(player.profile, 'Headphones');
      restored.dispose();
      output = null;
      await coordinator.refresh();
      expect(player.enabled, isFalse);
      output = const AudioOutput('a', 'Headphones');
      await coordinator.refresh();
      expect(player.enabled, isTrue);
      await settings.updateVisual('eq_autoeq_profiles', '{}');
      await coordinator.refresh();
      expect(player.enabled, isFalse);
      expect(coordinator.error, isNotNull);
    } finally {
      coordinator.dispose();
      player.dispose();
      settings.dispose();
    }
  });
  test('manual device snapshots preserve independent gain settings', () async {
    MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    );
    SharedPreferences.setMockInitialValues({
      'visual.eq_60': 3.0,
      'visual.eq_enabled': true,
    });
    final settings = AppSettings(await SharedPreferences.getInstance()),
        player = RecordingEqPlayer();
    AudioOutput? output = const AudioOutput('a', 'A');
    final coordinator = OutputEqualizer(
      player,
      settings,
      readOutput: () async => output,
    );
    try {
      await coordinator.refresh();
      await coordinator.setAutomatic(true);
      output = const AudioOutput('b', 'B');
      await coordinator.refresh();
      await settings.updateVisual('eq_60', -4.0);
      await coordinator.bindPreset('manual');
      output = const AudioOutput('a', 'A');
      await coordinator.refresh();
      expect(player.gains!.first, 3);
      output = const AudioOutput('b', 'B');
      await coordinator.refresh();
      expect(player.gains!.first, -4);
      coordinator.suspended = true;
      output = const AudioOutput('a', 'A');
      await coordinator.refresh();
      expect(player.gains!.first, -4);
      coordinator.suspended = false;
      await coordinator.refresh();
      expect(player.gains!.first, 3);
    } finally {
      coordinator.dispose();
      player.dispose();
      settings.dispose();
    }
  });
}
