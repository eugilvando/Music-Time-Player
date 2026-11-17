import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../application/player_controller.dart';
import '../domain/track.dart';
import '../domain/queue_navigation.dart';
import 'design_icon.dart';
import 'now_playing_artwork.dart';
import 'queue_drag_row.dart';
import 'ui_language.dart';

class QueuePanel extends StatefulWidget {
  const QueuePanel({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onSave,
    required this.onSavePlaylist,
    required this.onPlay,
    required this.trackActions,
  });
  final PlayerController controller;
  final VoidCallback onClose;
  final Future<void> Function() onSave, onSavePlaylist;
  final Future<void> Function(int) onPlay;
  final Widget Function(Track, int) trackActions;
  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  final scroll = ScrollController();
  bool following = true;
  int? occurrence;
  int previousIndex = -1;
  double rowHeight = 80;
  PlayerController get player => widget.controller;
  @override
  void initState() {
    super.initState();
    player.addListener(changed);
    changed();
  }

  @override
  void dispose() {
    player.removeListener(changed);
    scroll.dispose();
    super.dispose();
  }

  void changed() {
    final index = player.queueIndex;
    final key = index >= 0 && index < player.queueKeys.length
        ? player.queueKeys[index]
        : null;
    if (key != occurrence || previousIndex != index) {
      occurrence = key;
      previousIndex = index;
      if (following) reveal();
    }
  }

  void reveal({bool resume = false}) {
    if (resume) setState(() => following = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !following ||
          !scroll.hasClients ||
          player.queueIndex < 0) {
        return;
      }
      final target =
          (player.queueIndex * rowHeight -
                  (scroll.position.viewportDimension - rowHeight) / 2)
              .clamp(0.0, scroll.position.maxScrollExtent);
      scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Widget dropTarget(int index, Widget child, {Key? key}) =>
      DragTarget<List<Track>>(
        key: key,
        onWillAcceptWithDetails: (_) => !player.opening,
        onAcceptWithDetails: (details) async {
          await player.insertTracks(details.data, index);
          await widget.onSave();
        },
        builder: (context, candidates, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: candidates.isEmpty
                ? Colors.transparent
                : Theme.of(context).colorScheme.primaryContainer,
            border: Border(
              top: BorderSide(
                width: 2,
                color: candidates.isEmpty
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          child: child,
        ),
      );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: player,
    builder: (context, _) {
      rowHeight =
          80 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
      final colors = Theme.of(context).colorScheme;
      return Material(
        key: const ValueKey('queue.surface'),
        color: colors.surfaceContainerHigh.withValues(alpha: .94),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UiText(
                            'Fila de reprodução',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            player.queueTitle ?? ui(context, 'Sua fila'),
                            key: const ValueKey('queue.context'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: ui(context, 'Fechar fila'),
                      onPressed: widget.onClose,
                      icon: const MtIcon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Row(
                  key: const ValueKey('queue.toolbar'),
                  children: [
                    IconButton(
                      key: const ValueKey('queue.current'),
                      tooltip: ui(context, 'Ir para a faixa atual'),
                      isSelected: following,
                      onPressed: player.current == null
                          ? null
                          : () => reveal(resume: true),
                      icon: const MtIcon(Icons.my_location),
                    ),
                    IconButton(
                      tooltip:
                          '${ui(context, 'Repetir')}: ${ui(context, switch (player.repeat) {
                            PlaybackRepeat.off => 'desligado',
                            PlaybackRepeat.queue => 'fila',
                            PlaybackRepeat.track => 'faixa',
                          })}',
                      isSelected: player.repeat != PlaybackRepeat.off,
                      onPressed: () {
                        player.cycleRepeat();
                        widget.onSave();
                      },
                      icon: MtIcon(
                        player.repeat == PlaybackRepeat.track
                            ? Icons.repeat_one
                            : Icons.repeat,
                      ),
                    ),
                    IconButton(
                      tooltip: ui(context, 'Aleatório'),
                      isSelected: player.shuffle,
                      onPressed: () {
                        player.toggleShuffle();
                        widget.onSave();
                      },
                      icon: const MtIcon(Icons.shuffle),
                    ),
                    IconButton(
                      key: const ValueKey('queue.save'),
                      tooltip: ui(context, 'Salvar playlist'),
                      onPressed: player.queue.isEmpty
                          ? null
                          : widget.onSavePlaylist,
                      icon: const MtIcon(Icons.playlist_add),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        '${player.queue.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    PopupMenuButton<String>(
                      key: const ValueKey('queue.actions'),
                      tooltip: ui(context, 'Opções da playlist'),
                      icon: const MtIcon(Icons.more_horiz),
                      onSelected: (action) async {
                        if (action == 'save') {
                          await widget.onSavePlaylist();
                        }
                        if (action == 'clear') {
                          await player.clearQueue();
                          await widget.onSave();
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          key: const ValueKey('queue.save-playlist'),
                          value: 'save',
                          enabled: player.queue.isNotEmpty,
                          child: const UiText('Save queue as playlist'),
                        ),
                        PopupMenuItem(
                          key: const ValueKey('queue.clear'),
                          value: 'clear',
                          enabled: !player.opening && player.queue.isNotEmpty,
                          child: const UiText('Limpar fila'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, size) =>
                      NotificationListener<UserScrollNotification>(
                        onNotification: (notification) {
                          if (notification.direction != ScrollDirection.idle &&
                              following) {
                            setState(() => following = false);
                          }
                          return false;
                        },
                        child: ReorderableListView.builder(
                          key: const ValueKey('queue.list'),
                          scrollController: scroll,
                          buildDefaultDragHandles: false,
                          itemExtent: rowHeight,
                          itemCount: player.queue.length,
                          onReorderStart: (_) =>
                              setState(() => following = false),
                          onReorderItem: (oldIndex, newIndex) {
                            player.reorderQueue(oldIndex, newIndex);
                            widget.onSave();
                          },
                          footer: dropTarget(
                            player.queue.length,
                            SizedBox(
                              height: math.max(
                                88,
                                size.maxHeight -
                                    player.queue.length * rowHeight,
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: UiText(
                                    player.queue.isEmpty
                                        ? 'Arraste faixas para a fila.'
                                        : 'Solte aqui para adicionar ao final',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              ),
                            ),
                            key: const ValueKey('queue.drop.end'),
                          ),
                          itemBuilder: (context, index) {
                            final current = index == player.queueIndex;
                            final track = player.queue[index];
                            return dropTarget(
                              index,
                              QueueDragRow(
                                index: index,
                                child: Container(
                                  height: rowHeight,
                                  decoration: BoxDecoration(
                                    color: current
                                        ? colors.primaryContainer
                                        : index.isOdd
                                        ? colors.onSurface.withValues(
                                            alpha: .035,
                                          )
                                        : null,
                                    border: Border(
                                      left: BorderSide(
                                        width: 4,
                                        color: current
                                            ? colors.primary
                                            : Colors.transparent,
                                      ),
                                    ),
                                  ),
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                      leading: SizedBox.square(
                                        dimension: 40,
                                        child: TrackCover(track: track),
                                      ),
                                      title: Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: current
                                                  ? FontWeight.w800
                                                  : FontWeight.w500,
                                              color: current
                                                  ? colors.onPrimaryContainer
                                                  : null,
                                            ),
                                      ),
                                      subtitle: Text(
                                        '${current ? '${ui(context, player.playing ? 'Em reprodução' : 'Pausado')} · ' : ''}${track.artist}${player.automaticOrigin(index) == null ? '' : ' · ${ui(context, player.automaticOrigin(index) == 'flow' ? 'Smart Flow' : 'Fila inteligente')}'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      selected: current,
                                      onTap: player.opening
                                          ? null
                                          : () => widget.onPlay(index),
                                      trailing: widget.trackActions(
                                        track,
                                        index,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              key: ValueKey(player.queueKeys[index]),
                            );
                          },
                        ),
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
