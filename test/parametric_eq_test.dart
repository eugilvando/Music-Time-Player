import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_time/settings/parametric_eq.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/application/fade_analysis.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';

import 'dart:typed_data';

const autoEqFixture = '''Preamp: -6.0 dB
Filter 1: ON LSC Fc 105 Hz Gain 4.0 dB Q 0.70
Filter 2: ON PK Fc 1000 Hz Gain -3.0 dB Q 1.40
Filter 3: ON HSC Fc 10000 Hz Gain -2.0 dB Q 0.70
Filter 4: OFF PK Fc 4000 Hz Gain 8.0 dB Q 2.0
''';

void main() {
  test('AutoEQ imports all active filter types and round-trips backups', () {
    final profile = ParametricEqProfile.parse(
      '\uFEFF${autoEqFixture.replaceAll('\n', '\r\n')}',
      'Headphones',
    );
    expect(profile.filters.map((f) => f.type), ['LSC', 'PK', 'HSC']);
    expect(profile.preamp, -6);
    expect(profile.effectivePreamp, -6);
    expect(profile.nativeChain, contains('bass=f=105.0:t=q:w=0.7'));
    expect(profile.nativeChain, contains('treble=f=10000.0'));
    final encoded = jsonEncode({'Headphones': profile.toJson()});
    expect(decodeParametricProfiles(encoded)['Headphones']!.filters.length, 3);
    expect(
      AppData.validPreferenceType('visual.eq_autoeq_profiles', encoded),
      isTrue,
    );
    expect(AppData.validPreferenceType('visual.eq_per_output', true), isTrue);
    expect(
      AppData.validPreferenceType('visual.crossfade_setting', 'auto'),
      isTrue,
    );
    expect(
      AppData.validPreferenceType(
        'visual.eq_output_profiles',
        jsonEncode({
          'device': {
            'name': 'Headphones',
            'preset': 'autoeq:Headphones',
            'enabled': true,
          },
        }),
      ),
      isTrue,
    );
  });
  test('AutoEQ rejects malformed, unsupported and excessive filters', () {
    for (final text in [
      autoEqFixture.replaceFirst('LSC', 'XYZ'),
      autoEqFixture.replaceFirst('0.70', '0.00'),
      autoEqFixture.replaceFirst('105 Hz', '25000 Hz'),
      'Preamp: 0 dB\n',
      '${autoEqFixture}Preamp: -3 dB\n',
      'x' * 65537,
    ]) {
      expect(
        () => ParametricEqProfile.parse(text, 'Test'),
        throwsFormatException,
      );
    }
    expect(
      () => ParametricEqProfile('Test', 0, [
        const EqFilter('PK', 1000, double.nan, 1),
      ]),
      throwsFormatException,
    );
  });
  test('response and headroom preserve filter gains without positive clipping gain', () {
    expect(
      const EqFilter('PK', 1000, -3, 1.4).responseDb(1000),
      closeTo(-3, .001),
    );
    expect(const EqFilter('LSC', 105, 6, .7).responseDb(1), closeTo(6, .01));
    expect(
      const EqFilter('HSC', 10000, 6, .7).responseDb(23999),
      closeTo(6, .01),
    );
    expect(
      ParametricEqProfile('Boost', 0, [
        const EqFilter('PK', 1000, 8, 2),
      ]).effectivePreamp,
      lessThanOrEqualTo(-8),
    );
  });
  test(
    'automatic crossfade adapts to both durations and bounds short tracks',
    () {
      expect(
        automaticOverlapMs(
          const Duration(minutes: 3),
          const Duration(minutes: 4),
        ),
        5400,
      );
      expect(
        automaticOverlapMs(
          const Duration(minutes: 1),
          const Duration(minutes: 4),
        ),
        1800,
      );
      expect(
        automaticOverlapMs(const Duration(seconds: 4), Duration.zero),
        1000,
      );
      expect(automaticOverlapMs(Duration.zero, Duration.zero), 4000);
      expect(
        automaticOverlapMs(
          const Duration(minutes: 9),
          const Duration(minutes: 8),
        ),
        6000,
      );
    },
  );
  final lib = Platform.environment['MUSIC_TIME_LIBMPV'];
  test('native AutoEQ filters survive playback, disable and restore', () async {
    MediaKit.ensureInitialized(libmpv: lib);
    final folder = await Directory.systemTemp.createTemp('music-time-autoeq-');
    final bytes = Uint8List(44 + 48000 * 2 * 4),
        d = ByteData(44 + 48000 * 2 * 4);
    void text(int n, String value) =>
        bytes.setRange(n, n + value.length, value.codeUnits);
    text(0, 'RIFF');
    text(8, 'WAVE');
    text(12, 'fmt ');
    text(36, 'data');
    d.setUint32(4, bytes.length - 8, Endian.little);
    d.setUint32(16, 16, Endian.little);
    d.setUint16(20, 1, Endian.little);
    d.setUint16(22, 1, Endian.little);
    d.setUint32(24, 48000, Endian.little);
    d.setUint32(28, 96000, Endian.little);
    d.setUint16(32, 2, Endian.little);
    d.setUint16(34, 16, Endian.little);
    d.setUint32(40, bytes.length - 44, Endian.little);
    for (final range in [(4, 8), (16, 36), (40, 44)]) {
      bytes.setRange(range.$1, range.$2, d.buffer.asUint8List(), range.$1);
    }
    final file = await File('${folder.path}/silence.wav').writeAsBytes(bytes);
    final controller = PlayerController();
    try {
      final profile = ParametricEqProfile.parse(autoEqFixture, 'Test');
      await controller.setParametricEqualizer(true, profile);
      await controller.playQueue([
        Track(id: 'x', title: 'X', artist: 'Fixture', localPath: file.path),
      ], 0);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(controller.error, isNull);
      expect(controller.position.inMilliseconds, greaterThan(100));
      final native = controller.player.platform as NativePlayer;
      expect(await native.getProperty('af'), contains('bass'));
      await controller.setParametricEqualizer(false, profile);
      expect(await native.getProperty('af'), isEmpty);
      await controller.setParametricEqualizer(true, profile);
      expect(await native.getProperty('af'), contains('treble'));
      await controller.clearQueue();
    } finally {
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await folder.delete(recursive: true);
    }
  }, skip: lib == null ? 'Native audio library required' : false);
}
