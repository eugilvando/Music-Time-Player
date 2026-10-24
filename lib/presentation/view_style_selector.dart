import 'rounded_select.dart';
import 'design_icon.dart';
import 'media_card_size.dart';

import 'package:flutter/material.dart';

import 'ui_language.dart';

/// Compact toolbar entry. Each layout has a button and its own style field.
class ViewStyleButton extends StatelessWidget {
  const ViewStyleButton({
    super.key,
    required this.value,
    required this.families,
    required this.onChanged,
    this.actions = const {},
  });
  final String value;
  final Map<String, Map<String, String>> families;
  final Map<String, String> actions;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: ui(context, 'Visualização'),
    icon: const MtIcon(Icons.view_module_outlined),
    onPressed: () async {
      final sizes = MediaCardSizeScope.of(context);
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          title: const UiText('Visualização'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final family in families.entries)
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: family.value.containsKey(value)
                                  ? Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer
                                  : null,
                              foregroundColor: family.value.containsKey(value)
                                  ? Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer
                                  : null,
                            ),
                            onPressed: () => Navigator.pop(
                              context,
                              family.value.containsKey(value)
                                  ? value
                                  : family.value.keys.first,
                            ),
                            icon: MtIcon(ViewStyleSelector.icons[family.key]),
                            label: UiText(
                              ViewStyleSelector.labels[family.key] ??
                                  family.key,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 160,
                          child: RoundedSelect(
                            child: DropdownButton<String>(
                              style: Theme.of(context).textTheme.bodyMedium,
                              key: ValueKey('view.style.${family.key}'),
                              isExpanded: true,
                              value: family.value.containsKey(value)
                                  ? value
                                  : family.value.keys.first,
                              items: [
                                for (final style in family.value.entries)
                                  DropdownMenuItem(
                                    value: style.key,
                                    child: UiText(
                                      style.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (style) {
                                if (style != null) {
                                  Navigator.pop(context, style);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (sizes != null) ...[
                    const Divider(),
                    MediaCardSizePicker(scope: sizes),
                  ],
                  if (actions.isNotEmpty) const Divider(),
                  for (final action in actions.entries)
                    TextButton(
                      onPressed: () => Navigator.pop(context, action.key),
                      child: UiText(action.value),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const UiText('Fechar'),
            ),
          ],
        ),
      );
      if (context.mounted && result != null) onChanged(result);
    },
  );
}

/// The button chooses a layout family; the adjacent field lists its styles.
class ViewStyleSelector extends StatelessWidget {
  const ViewStyleSelector({
    super.key,
    required this.value,
    required this.families,
    required this.onChanged,
  });
  final String value;
  final Map<String, Map<String, String>> families;
  final ValueChanged<String> onChanged;
  static const labels = {
    'list': 'List',
    'grid': 'Grid',
    'cards': 'Cards',
    'carousel': 'Carousel',
  };
  static const icons = {
    'list': Icons.view_list_outlined,
    'grid': Icons.grid_view,
    'cards': Icons.view_agenda_outlined,
    'carousel': Icons.view_carousel_outlined,
  };
  @override
  Widget build(BuildContext context) {
    final family = families.keys.firstWhere(
      (key) => families[key]!.containsKey(value),
      orElse: () => families.keys.first,
    );
    final styles = families[family]!;
    return Wrap(
      spacing: 8,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<String>(
          key: const ValueKey('view.family'),
          tooltip: ui(context, 'View type'),
          onSelected: (key) => onChanged(families[key]!.keys.first),
          itemBuilder: (_) => [
            for (final key in families.keys)
              PopupMenuItem(
                value: key,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [MtIcon(icons[key]), UiText(labels[key] ?? key)],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                MtIcon(icons[family], size: 20),
                UiText(labels[family] ?? family),
                const MtIcon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 154,
          child: RoundedSelect(
            child: DropdownButton<String>(
              key: const ValueKey('view.style'),
              isExpanded: true,
              value: styles.containsKey(value) ? value : styles.keys.first,
              items: [
                for (final entry in styles.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: UiText(entry.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (style) {
                if (style != null) onChanged(style);
              },
            ),
          ),
        ),
        if (MediaCardSizeScope.of(context) case final sizes?)
          SizedBox(width: 142, child: MediaCardSizePicker(scope: sizes)),
      ],
    );
  }
}
