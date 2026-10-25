import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../settings/sidebar_layout.dart';
import 'navigation.dart';
import 'ui_language.dart';
import 'design_icon.dart';

class SidebarSettings extends StatelessWidget {
  const SidebarSettings({super.key, required this.settings});
  final AppSettings settings;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) {
      final order = sidebarOrder(
        settings.visualList('sidebar_order', sidebarItems),
      );
      final visible = settings
          .visualList('sidebar_items', sidebarItems)
          .toSet();
      Future<void> move(int from, int to) async {
        final items = List<String>.of(order);
        items.insert(to, items.removeAt(from));
        await settings.updateVisual('sidebar_order', items);
      }

      return Column(
        children: [
          const UiText(
            'Organize sidebar items. Settings remains available in the footer.',
          ),
          for (var i = 0; i < order.length; i++)
            Builder(
              builder: (context) {
                final id = order[i];
                final section = AppSection.values.firstWhere(
                  (s) => s.name == id,
                );
                return ListTile(
                  key: ValueKey('sidebar.setting.$id'),
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    value: visible.contains(id),
                    onChanged: (value) {
                      if (value == true) {
                        visible.add(id);
                      } else {
                        visible.remove(id);
                      }
                      settings.updateVisual('sidebar_items', visible.toList());
                    },
                  ),
                  title: UiText(section.label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: ui(context, 'Move up'),
                        onPressed: i == 0 ? null : () => move(i, i - 1),
                        icon: const MtIcon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: ui(context, 'Move down'),
                        onPressed: i == order.length - 1
                            ? null
                            : () => move(i, i + 1),
                        icon: const MtIcon(Icons.arrow_downward),
                      ),
                    ],
                  ),
                );
              },
            ),
          TextButton(
            onPressed: () =>
                settings.resetVisualKeys({'sidebar_order', 'sidebar_items'}),
            child: const UiText('Restore sidebar'),
          ),
        ],
      );
    },
  );
}
