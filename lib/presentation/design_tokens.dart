import 'package:flutter/material.dart';

import 'ui_language.dart';

/// Shared geometry from MT Design. Text scaling remains controlled by Flutter.
abstract final class MtDesign {
  static const sidebar = 210.0;
  static const sidebarCollapsed = 60.0;
  static const topbar = 64.0;
  static const pageInset = 24.0;
  static const queue = 300.0;
  static const lyrics = 480.0;
  static const headingFont = 'Bricolage Grotesque';
  static const bodyFont = 'Inter';
}

/// A compact segmented filter that scrolls instead of overflowing at large text.
class MtSegments<T> extends StatelessWidget {
  const MtSegments({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.keyPrefix,
  });
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.onSurface.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items.entries)
              Semantics(
                selected: item.key == value,
                child: TextButton(
                  key: keyPrefix == null
                      ? null
                      : ValueKey('$keyPrefix.${item.key}'),
                  onPressed: () => onChanged(item.key),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: item.key == value
                        ? colors.primary
                        : Colors.transparent,
                    foregroundColor: item.key == value
                        ? colors.onPrimary
                        : colors.onSurface,
                    shape: const StadiumBorder(),
                    textStyle: Theme.of(context).textTheme.bodySmall,
                  ),
                  child: UiText(item.value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
