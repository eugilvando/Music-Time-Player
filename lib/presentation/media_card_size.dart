import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'ui_language.dart';

const mediaCardSizes = <String, double>{
  'Extra Small': 96 / 196,
  'Small': 144 / 196,
  'Medium': 1,
  'Large': 256 / 196,
  'Extra Large': 320 / 196,
};

class MediaCardSizeScope extends InheritedWidget {
  const MediaCardSizeScope({
    super.key,
    required this.value,
    required this.onChanged,
    required super.child,
    this.settings,
    this.contextKey = 'catalog',
  });
  final String value;
  final ValueChanged<String> onChanged;
  final AppSettings? settings;
  final String contextKey;
  double get factor =>
      value == 'Larger' ? 320 / 196 : mediaCardSizes[value] ?? 1;
  double get gridWidth => 196 * factor;
  double get compactArtwork => switch (value) {
    'Extra Small' || 'Small' => 36,
    'Large' => 64,
    'Extra Large' || 'Larger' => 80,
    _ => 48,
  };
  double get compactWidth => switch (value) {
    'Extra Small' || 'Small' => 196,
    'Extra Large' || 'Larger' => 320,
    _ => 256,
  };
  static double cardWidth(BuildContext context) =>
      of(context)?.gridWidth ?? 196;
  static double horizontalWidth(BuildContext context) =>
      of(context)?.compactWidth ?? 256;
  static double horizontalArtwork(BuildContext context) =>
      of(context)?.compactArtwork ?? 48;
  static double horizontalHeight(BuildContext context) =>
      (horizontalArtwork(context) + 16) *
      MediaQuery.textScalerOf(context).scale(1);
  static MediaCardSizeScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaCardSizeScope>();
  static double scale(BuildContext context) => of(context)?.factor ?? 1;
  static Widget homeSection(
    AppSettings settings,
    String section,
    Widget child,
  ) => MediaCardSizeScope(
    settings: settings,
    contextKey: 'home_$section',
    value: settings.visualChoice(
      'home_card_size_$section',
      settings.visualChoice(
        'home_card_size_default',
        settings.visualChoice('media_card_size', 'Medium'),
      ),
    ),
    onChanged: (value) => change(settings, 'home_card_size_$section', value),
    child: child,
  );
  static Widget wrap(AppSettings settings, Widget child) => AnimatedBuilder(
    animation: settings,
    builder: (_, _) => MediaCardSizeScope(
      settings: settings,
      value: settings.visualChoice('media_card_size', 'Medium'),
      onChanged: (v) => change(settings, 'media_card_size', v),
      child: child,
    ),
  );
  static Future<void> change(
    AppSettings settings,
    String key,
    String value,
  ) async {
    // Freeze the inherited Home size before the first edit in either context.
    // Existing sections retain their appearance when catalog size changes later.
    if (settings.preferences.getString('visual.home_card_size_default') ==
        null) {
      await settings.updateVisual(
        'home_card_size_default',
        settings.visualChoice('media_card_size', 'Medium'),
      );
    }
    await settings.updateVisual(key, value);
  }

  @override
  bool updateShouldNotify(MediaCardSizeScope old) => value != old.value;
}

class MediaCardSizePicker extends StatelessWidget {
  const MediaCardSizePicker({super.key, required this.scope});
  final MediaCardSizeScope scope;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    style: Theme.of(context).textTheme.bodyMedium,
    key: ValueKey('media.card.size.${scope.value}'),
    initialValue: scope.value == 'Larger'
        ? 'Extra Large'
        : mediaCardSizes.containsKey(scope.value)
        ? scope.value
        : 'Medium',
    isExpanded: true,
    decoration: InputDecoration(labelText: ui(context, 'Tamanho dos cards')),
    items: [
      for (final v in mediaCardSizes.keys)
        DropdownMenuItem(value: v, child: UiText(v)),
    ],
    onChanged: (v) {
      if (v != null) scope.onChanged(v);
    },
  );
}
