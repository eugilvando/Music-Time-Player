import 'design_icon.dart';

import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../settings/player_bar_layout.dart';
import 'ui_language.dart';

class PlayerBarOrganizer extends StatelessWidget {
  const PlayerBarOrganizer({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) {
      final order = playerBarOrder(settings);
      final visible = playerBarVisible(settings);
      Future<void> move(int from, int to) async {
        final next = List<String>.of(order);
        next.insert(to, next.removeAt(from));
        await settings.updateVisual('bar_item_order', next);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UiText(
            'Arraste para ordenar. Ative ou desative cada item; a barra muda imediatamente.',
          ),
          const SizedBox(height: 12),

          ReorderableListView.builder(
            key: const ValueKey('player.organizer'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: order.length,
            onReorderItem: move,
            itemBuilder: (context, index) {
              final id = order[index];
              return ListTile(
                key: ValueKey('player.organizer.$id'),
                contentPadding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: MtIcon(Icons.drag_handle),
                  ),
                ),
                title: UiText(playerBarItems[id]!),
                subtitle: UiText(switch (id) {
                  'cover' || 'info' => 'Identificação',
                  'previous' ||
                  'play' ||
                  'next' ||
                  'shuffle' ||
                  'repeat' => 'Controles',
                  'favorite' ||
                  'actions' ||
                  'offline' ||
                  'continuous' => 'Ações',
                  'elapsed' || 'progress' || 'duration' => 'Progresso',
                  'lyrics' ||
                  'queue' ||
                  'expand' ||
                  'lastfm' => 'Painéis e serviços',
                  _ => 'Áudio e estrutura',
                }),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<int>(
                      tooltip: ui(context, 'Mover item'),
                      onSelected: (to) => move(index, to),
                      itemBuilder: (_) => [
                        if (index > 0)
                          PopupMenuItem(
                            value: index - 1,
                            child: const UiText('Mover para a esquerda'),
                          ),
                        if (index < order.length - 1)
                          PopupMenuItem(
                            value: index + 1,
                            child: const UiText('Mover para a direita'),
                          ),
                      ],
                      icon: const MtIcon(Icons.swap_horiz),
                    ),
                    Switch(
                      key: ValueKey('player.visibility.$id'),
                      value: visible.contains(id),
                      onChanged: (enabled) {
                        final next = Set<String>.of(visible);
                        if (enabled) {
                          next.add(id);
                        } else {
                          next.remove(id);
                        }
                        settings.updateVisual(
                          'bar_items',
                          order.where(next.contains).toList(),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const UiText('Espaçamento dos ícones'),
          Slider(
            key: const ValueKey('player.iconSpacing'),
            value: settings.visualNumber('bar_icon_spacing', 4).clamp(0, 24),
            min: 0,
            max: 24,
            divisions: 24,
            label: '${settings.visualNumber('bar_icon_spacing', 4).round()} px',
            onChanged: (value) =>
                settings.updateVisual('bar_icon_spacing', value),
          ),
          TextButton.icon(
            onPressed: () async {
              await settings.updateVisual(
                'bar_item_order',
                playerBarItems.keys.toList(),
              );
              await settings.updateVisual(
                'bar_items',
                playerBarItems.keys
                    .where((id) => !id.startsWith('separator'))
                    .toList(),
              );
              await settings.updateVisual('bar_icon_spacing', 4.0);
            },
            icon: const MtIcon(Icons.restore),
            label: const UiText('Restaurar barra padrão'),
          ),
        ],
      );
    },
  );
}
