import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'ui_language.dart';

const mediaCardSizes = <String, double>{
  'Small': .8,
  'Medium': 1,
  'Large': 1.2,
  'Extra Large': 1.45,
  'Larger': 1.7,
};

class MediaCardSizeScope extends InheritedWidget {
  const MediaCardSizeScope({
    super.key,
    required this.value,
    required this.onChanged,
    required super.child,
  });
  final String value;
  final ValueChanged<String> onChanged;
  double get factor => mediaCardSizes[value] ?? 1;
  static MediaCardSizeScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaCardSizeScope>();
  static double scale(BuildContext context) => of(context)?.factor ?? 1;
  static Widget homeSection(
    AppSettings settings,
    String section,
    Widget child,
  ) => MediaCardSizeScope(
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
    key: ValueKey('media.card.size.${scope.value}'),
    initialValue: mediaCardSizes.containsKey(scope.value)
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
