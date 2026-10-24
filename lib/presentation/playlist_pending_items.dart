import 'design_icon.dart';

import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../library/playlist_batch_import.dart';
import '../persistence/library_store.dart';
import 'item_action_region.dart';
import 'playlist_import_review.dart';
import 'ui_language.dart';

class PlaylistPendingItems extends StatefulWidget {
  const PlaylistPendingItems({
    super.key,
    required this.store,
    required this.id,
    required this.rows,
    required this.queue,
    required this.busy,
    required this.onChanged,
    required this.onPlay,
    this.trackActions,
  });
  final LibraryStore store;
  final int id;
  final List<Map<String, Object?>> rows;
  final List<Track> queue;
  final bool busy;
  final Future<void> Function(Future<void> Function()) onChanged;
  final void Function(List<Track>, int) onPlay;
  final Widget Function(Track)? trackActions;
  @override
  State<PlaylistPendingItems> createState() => _PlaylistPendingItemsState();
}

class _PlaylistPendingItemsState extends State<PlaylistPendingItems> {
  bool missingOnly = false;
  @override
  Widget build(BuildContext context) {
    final hasPending = widget.rows.any((r) => r['track_id'] == null);
    final showMissingOnly = hasPending && missingOnly;
    final values = widget.rows
        .where((r) => !showMissingOnly || r['track_id'] == null)
        .toList();
    final byId = {for (final t in widget.queue) t.id: t};
    Widget item(int i) {
      final row = values[i], track = byId[values[i]['track_id']];
      final title = row['import_title'] as String? ?? '';
      return ItemActionRegion(
        key: ValueKey(row['id']),
        child: ListTile(
          dense: true,
          leading: MtIcon(
            track == null ? Icons.warning_amber : Icons.music_note,
          ),
          title: Text(
            track?.title ??
                (title.isEmpty ? ui(context, 'Unresolved item') : title),
          ),
          subtitle: track != null
              ? Text(track.artist)
              : Text(
                  '${row['import_artist'] ?? ''} · ${ui(context, row['resolution_reason'] == 'ambiguous'
                      ? 'Ambiguous reference'
                      : row['resolution_reason'] == 'unsupported'
                      ? 'Unsupported remote reference. Link a library track.'
                      : 'Item not found')}',
                ),
          onTap: track == null || widget.busy
              ? null
              : () {
                  final ordinal = widget.rows.indexWhere(
                    (r) => r['id'] == row['id'],
                  );
                  final index = widget.rows
                      .take(ordinal)
                      .where((r) => r['track_id'] != null)
                      .length;
                  widget.onPlay(widget.queue, index);
                },
          trailing: Padding(
            padding: const EdgeInsets.only(right: 32),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (track != null && widget.trackActions != null)
                  widget.trackActions!(track),
                PopupMenuButton<String>(
                  enabled: !widget.busy,
                  onSelected: (action) async {
                    if (action == 'link') {
                      final catalog = await widget.store.loadTracks(
                        includeCovers: false,
                        includeHidden: true,
                      );
                      if (!context.mounted) return;
                      final id = await pickPlaylistTrack(context, catalog);
                      if (id != null && mounted) {
                        await widget.onChanged(
                          () => widget.store.linkPlaylistOccurrence(
                            row['id'] as int,
                            id,
                          ),
                        );
                      }
                    } else if (action == 'reference') {
                      await showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          insetPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 24,
                          ),
                          titlePadding: const EdgeInsets.fromLTRB(
                            24,
                            24,
                            24,
                            16,
                          ),
                          contentPadding: const EdgeInsets.fromLTRB(
                            24,
                            8,
                            24,
                            24,
                          ),
                          actionsPadding: const EdgeInsets.fromLTRB(
                            24,
                            0,
                            24,
                            24,
                          ),
                          title: const UiText('Original reference'),
                          content: SelectableText(
                            '${row['original_reference'] ?? ''}',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const UiText('Close'),
                            ),
                          ],
                        ),
                      );
                    } else {
                      await widget.onChanged(
                        () =>
                            widget.store.removePlaylistEntry(row['id'] as int),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    if (track == null)
                      const PopupMenuItem(
                        value: 'link',
                        child: UiText('Find in library'),
                      ),
                    if (row['original_reference'] != null)
                      const PopupMenuItem(
                        value: 'reference',
                        child: UiText('Original reference'),
                      ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: UiText('Remove from playlist'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (hasPending)
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const UiText('All'),
                selected: !missingOnly,
                onSelected: (_) => setState(() => missingOnly = false),
              ),
              FilterChip(
                label: const UiText('Missing items'),
                selected: missingOnly,
                onSelected: (_) => setState(() => missingOnly = true),
              ),
              OutlinedButton.icon(
                onPressed: widget.busy
                    ? null
                    : () => widget.onChanged(() async {
                        final catalog = await widget.store.loadTracks(
                          includeCovers: false,
                          includeHidden: true,
                        );
                        await retryPlaylistReferences(
                          widget.store,
                          widget.id,
                          catalog,
                        );
                      }),
                icon: const MtIcon(Icons.refresh),
                label: const UiText('Retry resolution'),
              ),
            ],
          ),
        if (widget.queue.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: UiText('No playable tracks. Pending items are preserved.'),
          ),
        Expanded(
          child: values.isEmpty
              ? Center(
                  child: UiText(
                    showMissingOnly
                        ? 'No pending items'
                        : 'Add tracks to this playlist.',
                  ),
                )
              : showMissingOnly
              ? ListView.builder(
                  itemCount: values.length,
                  itemBuilder: (_, i) => item(i),
                )
              : ReorderableListView.builder(
                  itemCount: values.length,
                  onReorderItem: (a, b) async {
                    if (widget.busy) return;
                    final ids = values.map((r) => r['id'] as int).toList();
                    ids.insert(b, ids.removeAt(a));
                    await widget.onChanged(
                      () => widget.store.reorderPlaylist(widget.id, ids),
                    );
                  },
                  itemBuilder: (_, i) => item(i),
                ),
        ),
      ],
    );
  }
}

Widget playlistPendingBadge(BuildContext context, int count) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    MtIcon(
      Icons.warning_amber,
      size: 18,
      color: Theme.of(context).colorScheme.error,
    ),
    const SizedBox(width: 4),
    Flexible(child: Text('$count ${ui(context, 'items not found')}')),
  ],
);
