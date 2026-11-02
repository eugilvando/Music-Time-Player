import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../application/player_controller.dart';
import '../settings/app_settings.dart';
import '../settings/equalizer_presets.dart';
import '../settings/parametric_eq.dart';

class AudioOutput {
  const AudioOutput(this.id, this.name);
  final String id, name;
}

Future<void> applyConfiguredEqualizer(
  PlayerController controller,
  AppSettings settings, {
  String? preset,
  bool? enabled,
}) async {
  final id = preset ?? settings.visualChoice('eq_preset', 'manual');
  final active = enabled ?? settings.visualBool('eq_enabled', fallback: false);
  if (id.startsWith('autoeq:')) {
    final profile = decodeParametricProfiles(
      settings.visualChoice('eq_autoeq_profiles', '{}'),
    )[id.substring(7)];
    if (profile == null) {
      throw const FormatException('Perfil AutoEQ indisponível.');
    }
    await controller.setParametricEqualizer(active, profile);
  } else {
    final gains = id.startsWith('builtin:')
        ? equalizerPresets[id.substring(8)]
        : id.startsWith('custom:')
        ? decodeEqualizerPresets(settings.visualChoice('eq_presets', '{}'))[id
              .substring(7)]
        : [
            for (final f in PlayerController.equalizerFrequencies)
              settings.visualNumber('eq_$f', 0),
          ];
    if (gains == null) throw const FormatException('Preset indisponível.');
    await controller.setEqualizer(active, gains);
  }
}

class OutputEqualizer extends ChangeNotifier {
  OutputEqualizer(
    this.controller,
    this.settings, {
    Future<AudioOutput?> Function()? readOutput,
  }) : readOutput = readOutput ?? systemOutput;
  final PlayerController controller;
  final AppSettings settings;
  final Future<AudioOutput?> Function() readOutput;
  AudioOutput? current;
  String? error;
  Timer? _timer;
  bool _reading = false, _disposed = false, _started = false;
  bool _suspended = false;
  bool get suspended => _suspended;
  set suspended(bool value) {
    if (_suspended == value) return;
    _suspended = value;
    _generation++;
    _signature = '';
  }

  String _signature = '';
  Future<void> _jobs = Future.value();
  int _generation = 0;
  bool get automatic => settings.visualBool('eq_per_output', fallback: false);
  Map<String, dynamic> get bindings {
    try {
      final data = jsonDecode(
        settings.visualChoice('eq_output_profiles', '{}'),
      );
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic>? get binding {
    final value = bindings[current?.id];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    settings.addListener(_settingsChanged);
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void _settingsChanged() => _schedule();
  Future<void> refresh() async {
    if (_reading || _disposed || suspended) return;
    _reading = true;
    try {
      final output = await readOutput();
      if (_disposed) return;
      if (current?.id != output?.id || current?.name != output?.name) {
        current = output;
        notifyListeners();
      }
      _schedule();
      await _jobs;
    } catch (_) {
      if (!_disposed) {
        current = null;
        _schedule();
        error = 'Não foi possível identificar a saída de áudio.';
        notifyListeners();
      }
    } finally {
      _reading = false;
    }
  }

  void _schedule() {
    if (_disposed || suspended) return;
    final choice = binding;
    final id = choice?['preset'] is String
        ? choice!['preset'] as String
        : 'manual';
    final enabled = current != null && choice?['enabled'] == true;
    final storedGains = choice?['gains'];
    final manualGains =
        storedGains is List &&
            storedGains.length == 5 &&
            storedGains.every(
              (v) => v is num && v.isFinite && v >= -12 && v <= 12,
            )
        ? storedGains.cast<num>().map((v) => v.toDouble()).toList()
        : null;
    final signature =
        '$automatic|${current?.id}|$id|$enabled|${jsonEncode(choice)}|${settings.visualChoice('eq_autoeq_profiles', '{}')}|${settings.visualChoice('eq_presets', '{}')}';
    if (_signature == signature) return;
    _signature = signature;
    final generation = ++_generation;
    if (!automatic) {
      notifyListeners();
      return;
    }
    _jobs = _jobs.catchError((Object _) {}).then((_) async {
      if (_disposed || suspended || generation != _generation) return;
      try {
        if (id == 'manual' && manualGains != null) {
          await controller.setEqualizer(enabled, manualGains);
        } else {
          await applyConfiguredEqualizer(
            controller,
            settings,
            preset: id,
            enabled: enabled,
          );
        }
        if (_disposed || suspended || generation != _generation) return;
        final values = id == 'manual'
            ? manualGains
            : id.startsWith('builtin:')
            ? equalizerPresets[id.substring(8)]
            : id.startsWith('custom:')
            ? decodeEqualizerPresets(
                settings.visualChoice('eq_presets', '{}'),
              )[id.substring(7)]
            : null;
        if (values != null) {
          for (var i = 0; i < values.length; i++) {
            if (_disposed || suspended || generation != _generation) return;
            await settings.updateVisual(
              'eq_${PlayerController.equalizerFrequencies[i]}',
              values[i],
            );
          }
        }
        await settings.updateVisual('eq_preset', id);
        await settings.updateVisual('eq_enabled', enabled);
        error = settings.error;
      } catch (_) {
        // A missing or invalid binding must not keep the last headphone's EQ.
        await controller.setEqualizer(false, const [0, 0, 0, 0, 0]);
        if (_disposed || suspended || generation != _generation) return;
        await settings.updateVisual('eq_enabled', false);
        error =
            'O perfil desta saída está indisponível. Equalização desativada.';
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> setAutomatic(bool value) async {
    if (value && current != null && binding == null) {
      await rememberCurrent(force: true);
    }
    await settings.updateVisual('eq_per_output', value);
    _schedule();
    await _jobs;
  }

  Future<void> rememberCurrent({bool force = false}) async {
    if ((!automatic && !force) || current == null) return;
    await _saveBinding(
      settings.visualChoice('eq_preset', 'manual'),
      settings.visualBool('eq_enabled', fallback: false),
    );
  }

  Future<void> bindPreset(String id) async {
    if (current == null) return;
    await _saveBinding(id == 'off' ? 'manual' : id, id != 'off');
    _schedule();
    await _jobs;
  }

  Future<void> _saveBinding(String preset, bool enabled) async {
    final map = bindings;
    map[current!.id] = {
      'name': current!.name,
      'preset': preset,
      'enabled': enabled,
      if (preset == 'manual')
        'gains': [
          for (final f in PlayerController.equalizerFrequencies)
            settings.visualNumber('eq_$f', 0),
        ],
    };
    await settings.updateVisual('eq_output_profiles', jsonEncode(map));
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    if (_started) settings.removeListener(_settingsChanged);
    super.dispose();
  }

  static Future<String> _pactl(List<String> args) async {
    final process = await Process.start(
      'pactl',
      args,
      environment: {'LC_ALL': 'C'},
    );
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 2));
      await errors;
      if (code != 0) throw StateError('pactl unavailable');
      return await output;
    } finally {
      process.kill();
    }
  }

  static Future<AudioOutput?> systemOutput() async {
    if (Platform.isWindows) {
      final value = await const MethodChannel('music_time/audio_output')
          .invokeMapMethod<String, dynamic>('getDefaultOutput');
      if (value == null || value['id'] is! String) return null;
      return AudioOutput(
        'windows:${value['id']}',
        value['name'] as String? ?? 'Windows',
      );
    }
    if (Platform.isLinux) {
      final id = (await _pactl(['get-default-sink'])).trim();
      if (id.isEmpty) return null;
      final sinks =
          jsonDecode(await _pactl(['--format=json', 'list', 'sinks'])) as List;
      final sink = sinks
          .whereType<Map>()
          .where((s) => s['name'] == id)
          .firstOrNull;
      return AudioOutput('linux:$id', sink?['description'] as String? ?? id);
    }
    return null;
  }
}
