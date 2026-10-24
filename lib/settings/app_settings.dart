import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/home_catalog.dart' show homeSectionLabels;

class AppSettings extends ChangeNotifier {
  AppSettings(this.preferences) {
    final theme = preferences.getString('theme');
    mode = ThemeMode.values.firstWhere(
      (value) => value.name == theme,
      orElse: () => ThemeMode.dark,
    );
    final saved = preferences.getInt('accent');
    accent = accents.containsKey(saved) ? saved! : accents.keys.first;
  }

  static const accents = <int, String>{
    0xFFFF7668: 'Coral',
    0xFF448AFF: 'Azul',
    0xFF43A047: 'Verde',
    0xFF9575CD: 'Violeta',
    0xFFEC407A: 'Rosa',
    0xFFFFB300: 'Âmbar',
  };
  final SharedPreferences preferences;
  late ThemeMode mode;
  late int accent;
  int? systemAccent;
  void refreshFromPreferences() {
    mode = ThemeMode.values.firstWhere(
      (v) => v.name == preferences.getString('theme'),
      orElse: () => ThemeMode.dark,
    );
    final saved = preferences.getInt('accent');
    accent = accents.containsKey(saved) ? saved! : accents.keys.first;
    notifyListeners();
  }

  int get effectiveAccent => visualBool('system_accent', fallback: false)
      ? systemAccent ?? accent
      : accent;
  void receiveSystemAccent(int? value) {
    final valid = value != null && value >= 0xff000000 && value <= 0xffffffff
        ? value
        : null;
    if (systemAccent == valid) return;
    systemAccent = valid;
    notifyListeners();
  }

  bool saving = false;
  String? error;
  final _pending = <String, Object>{};
  final _versions = <String, int>{};
  int _nextWrite = 0;
  Future<void> _writeTail = Future.value();
  List<String> visualList(String key, List<String> fallback) =>
      (_pending['visual.$key'] as List<String>?) ??
      preferences.getStringList('visual.$key') ??
      fallback;

  String get language =>
      preferences.getString('visual.language') == 'pt' ? 'pt' : 'en';
  Future<void> setLanguage(String value) async {
    if (!{'pt', 'en'}.contains(value)) return;
    await persist('visual.language', value);
  }

  String get nowPlayingStyle {
    final value = preferences.getString('visual.style');
    return {'classic', 'vinyl', 'minimal', 'gallery', 'focus'}.contains(value)
        ? value!
        : 'vinyl';
  }

  bool visualBool(String key, {bool fallback = true}) =>
      (_pending['visual.$key'] as bool?) ??
      preferences.getBool('visual.$key') ??
      fallback;
  String visualChoice(String key, String fallback) =>
      (_pending['visual.$key'] as String?) ??
      preferences.getString('visual.$key') ??
      fallback;
  double visualNumber(String key, double fallback) =>
      (_pending['visual.$key'] as double?) ??
      preferences.getDouble('visual.$key') ??
      fallback;
  Set<String> get collectionFavorites =>
      (preferences.getStringList('collections.favorites') ?? []).toSet();
  int lyricsOffset(String trackId) =>
      preferences.getInt('lyrics.offset.$trackId') ?? 0;

  Future<void> updateVisual(String key, Object value) =>
      persist('visual.$key', value);
  int artistSelectionSize({bool radio = false}) => visualNumber(
    radio ? 'artist_radio_size' : 'artist_mix_size',
    40,
  ).round().clamp(1, 500);
  Future<void> setArtistSelectionSize(int value, {bool radio = false}) {
    if (value < 1 || value > 500) throw RangeError.range(value, 1, 500);
    return updateVisual(
      radio ? 'artist_radio_size' : 'artist_mix_size',
      value.toDouble(),
    );
  }

  Future<void> migrateHomeLayout() async {
    if (preferences.getBool('visual.artist_radio_1_2') != true) {
      final types = preferences.getStringList('visual.home_mix_types');
      if (types != null && !types.contains('artist_radio')) {
        await updateVisual('home_mix_types', [...types, 'artist_radio']);
      }
      await updateVisual('artist_radio_1_2', true);
    }
    if (preferences.getBool('visual.home_layout_0_7_3') == true) return;
    final previous = preferences.getStringList('visual.home_sections');
    if (previous != null) {
      await persist('visual.home_sections_before_0_7_3', previous);
    }
    await updateVisual('home_sections', homeSectionLabels.keys.toList());
    await updateVisual('home_layout_0_7_3', true);
  }

  Future<void> setLyricsOffset(String trackId, int milliseconds) =>
      persist('lyrics.offset.$trackId', milliseconds);
  Future<void> favoriteCollection(
    String key, {
    Iterable<String> aliases = const [],
  }) async {
    final values = collectionFavorites;
    if (values.contains(key) || aliases.any(values.contains)) {
      values.remove(key);
      values.removeAll(aliases);
    } else {
      values.add(key);
    }
    await persist('collections.favorites', values.toList());
  }

  Future<bool> write(String key, Object value) => switch (value) {
    bool value => preferences.setBool(key, value),
    String value => preferences.setString(key, value),
    double value => preferences.setDouble(key, value),
    int value => preferences.setInt(key, value),
    List<String> value => preferences.setStringList(key, value),
    _ => throw ArgumentError('Tipo de preferência inválido'),
  };

  Future<void> persist(String key, Object value) async {
    final previous = preferences.get(key);
    final version = ++_nextWrite;
    _versions[key] = version;
    _pending[key] = value;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final job = _writeTail.then((_) async {
        if (!await write(key, value)) throw StateError('Preferência não salva');
      });
      _writeTail = job.catchError((Object _) {});
      await job;
    } catch (_) {
      if (_versions[key] == version) {
        if (previous != null) {
          await write(key, previous);
        } else {
          await preferences.remove(key);
        }
      }
      error = 'Não foi possível salvar a configuração. Tente novamente.';
    } finally {
      if (_versions[key] == version) {
        _pending.remove(key);
        _versions.remove(key);
      }
      saving = _pending.isNotEmpty;
      notifyListeners();
    }
  }

  Future<void> resetAppearance() async {
    await update(theme: ThemeMode.dark, color: accents.keys.first);
    await resetVisualKeys({
      'system_accent',
      'font_title',
      'font_body',
      'font_secondary',
      'font_navigation',
      'animations',
      'reduce_motion',
    });
  }

  Future<void> resetNowPlaying() => resetVisualKeys({
    'style',
    'cover_shape',
    'cover_position',
    'cover_scale',
    'background',
    'background_intensity',
    'show_queue',
    'additional_info',
  });
  Future<void> resetGeneral() async {
    await resetVisualKeys({'system_accent', 'animations', 'reduce_motion'});
    await update(theme: ThemeMode.dark, color: accents.keys.first);
    await setLanguage('en');
    await setWindowBehavior('windows.close_to_tray', true);
    await setWindowBehavior('windows.minimize_to_tray', false);
  }

  Future<void> resetInterface() => resetVisualKeys({
    'style',
    'cover_shape',
    'cover_position',
    'cover_scale',
    'background',
    'background_intensity',
    'show_queue',
    'additional_info',
    'font_title',
    'font_body',
    'font_secondary',
    'font_navigation',
    'lyrics_font',
    'lyrics_spacing',
    'lyrics_auto_scroll',
    'bar_fields',
    'bar_items',
    'bar_item_order',
    'bar_icon_spacing',
  });
  Future<void> resetVisualKeys(Set<String> keys) async {
    await _writeTail;
    for (final key in keys) {
      if (!await preferences.remove('visual.$key')) {
        error = 'Não foi possível restaurar todas as preferências.';
        break;
      }
    }
    notifyListeners();
  }

  Future<void> resetVisual() async {
    if (saving) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      for (final key
          in preferences
              .getKeys()
              .where(
                (key) =>
                    key.startsWith('visual.') &&
                    !key.startsWith('visual.eq_') &&
                    key != 'visual.language',
              )
              .toList()) {
        if (!await preferences.remove(key)) throw StateError('Não salvo');
      }
    } catch (_) {
      error = 'Não foi possível restaurar todas as preferências.';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  bool get closeToTray => preferences.getBool('windows.close_to_tray') ?? true;
  bool get minimizeToTray =>
      preferences.getBool('windows.minimize_to_tray') ?? false;
  Future<void> setWindowBehavior(String key, bool value) => persist(key, value);

  Future<void> update({ThemeMode? theme, int? color}) async {
    if (saving) return;
    final previousMode = mode;
    final previousAccent = accent;
    mode = theme ?? mode;
    accent = color ?? accent;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final success = theme != null
          ? await preferences.setString('theme', mode.name)
          : await preferences.setInt('accent', accent);
      if (!success) throw StateError('Preferência não salva');
    } catch (_) {
      mode = previousMode;
      accent = previousAccent;
      error = 'Não foi possível salvar a aparência. Tente novamente.';
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
