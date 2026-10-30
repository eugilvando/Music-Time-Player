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
          const SizedBox(height: 12),
          ReorderableListView.builder(
            key: const ValueKey('sidebar.organizer'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: order.length,
            onReorderItem: move,
            itemBuilder: (context, i) {
              final id = order[i];
              final section = AppSection.values.firstWhere((s) => s.name == id);
              return ListTile(
                key: ValueKey('sidebar.setting.$id'),
                contentPadding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: MtIcon(Icons.drag_handle),
                  ),
                ),
                title: UiText(section.label),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<int>(
                      tooltip: ui(context, 'Mover item'),
                      icon: const MtIcon(Icons.swap_vert),
                      onSelected: (to) => move(i, to),
                      itemBuilder: (_) => [
                        if (i > 0)
                          PopupMenuItem(
                            value: i - 1,
                            child: const UiText('Move up'),
                          ),
                        if (i < order.length - 1)
                          PopupMenuItem(
                            value: i + 1,
                            child: const UiText('Move down'),
                          ),
                      ],
                    ),
                    Switch(
                      key: ValueKey('sidebar.visibility.$id'),
                      value: visible.contains(id),
                      onChanged: (enabled) {
                        final next = Set<String>.of(visible);
                        if (enabled) {
                          next.add(id);
                        } else {
                          next.remove(id);
                        }
                        settings.updateVisual(
                          'sidebar_items',
                          order.where(next.contains).toList(),
                        );
                      },
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
