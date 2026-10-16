import 'package:flutter/services.dart';

import '../settings/app_settings.dart';

class SystemAccentController {
  SystemAccentController(this.settings);
  final AppSettings settings;
  static const channel = MethodChannel('music_time/appearance');
  bool _disposed = false;
  int _revision = 0;

  Future<bool> initialize() async {
    channel.setMethodCallHandler((call) async {
      if (_disposed || call.method != 'accentChanged') return;
      _revision++;
      settings.receiveSystemAccent(
        call.arguments is int ? call.arguments as int : null,
      );
    });
    final revision = _revision;
    try {
      final color = await channel.invokeMethod<int>('getSystemAccent');
      if (!_disposed && revision == _revision) {
        settings.receiveSystemAccent(color);
      }
    } catch (_) {
      if (!_disposed && revision == _revision) {
        settings.receiveSystemAccent(null);
      }
    }
    return !_disposed && settings.systemAccent != null;
  }

  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
  }
}
