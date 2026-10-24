import 'design_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../domain/track.dart';
import '../offline/download_manager.dart';
import 'collection_browser.dart' show validOfflineFiles;
import 'ui_language.dart';

class TrackAvailabilityButton extends StatefulWidget {
  const TrackAvailabilityButton({
    super.key,
    required this.track,
    required this.downloads,
  });
  final Track? track;
  final DownloadManager downloads;
  @override
  State<TrackAvailabilityButton> createState() =>
      _TrackAvailabilityButtonState();
}

class _TrackAvailabilityButtonState extends State<TrackAvailabilityButton> {
  Set<String> statuses = {};
  int generation = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    listen(true);
    refresh();
  }

  void listen(bool add) {
    if (add) {
      widget.downloads.addListener(schedule);
      widget.downloads.cache?.addListener(schedule);
    } else {
      widget.downloads.removeListener(schedule);
      widget.downloads.cache?.removeListener(schedule);
    }
  }

  @override
  void didUpdateWidget(covariant TrackAvailabilityButton old) {
    super.didUpdateWidget(old);
    if (old.track?.id != widget.track?.id ||
        old.track?.revision != widget.track?.revision) {
      statuses = {};
      refresh();
    }
  }

  void schedule() {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (widget.downloads.running || widget.downloads.cache?.current != null) {
        schedule();
      } else {
        refresh();
      }
    });
  }

  Future<void> refresh() async {
    final request = ++generation, track = widget.track;
    if (track == null) {
      if (mounted) setState(() => statuses = {});
      return;
    }
    try {
      final permanent = await widget.downloads.store.offlineFile(track.id);
      final cached = await widget.downloads.store.database.query(
        'media_cache',
        where: 'track_id=? AND revision=?',
        whereArgs: [track.id, track.revision],
      );
      final candidates = <Map<String, Object?>>[
        if (track.localPath != null) {'id': 'local', 'path': track.localPath},
        if (permanent?['path'] is String)
          {
            'id': 'permanent',
            'path': permanent!['path'],
            if ((permanent['received'] as int? ?? 0) > 0)
              'bytes': permanent['received'],
          },
        for (final row in cached)
          {'id': 'cache', 'path': row['path'], 'bytes': row['bytes']},
      ];
      final valid = await compute(validOfflineFiles, candidates);
      if (mounted && request == generation) setState(() => statuses = valid);
    } catch (_) {
      if (mounted && request == generation) setState(() => statuses = {});
    }
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    listen(false);
    super.dispose();
  }

  String get status => statuses.contains('local')
      ? 'Arquivo local'
      : statuses.contains('permanent')
      ? 'Download permanente'
      : statuses.contains('cache')
      ? 'Em cache'
      : widget.track?.localPath == null && widget.track?.available == true
      ? 'Disponível por streaming'
      : 'Indisponível';
  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('player.availability'),
    tooltip: ui(context, status),
    icon: MtIcon(
      statuses.isEmpty
          ? Icons.cloud_outlined
          : statuses.contains('permanent')
          ? Icons.offline_pin
          : statuses.contains('cache')
          ? Icons.cached
          : Icons.folder_open,
    ),
    color: statuses.isEmpty ? null : Theme.of(context).colorScheme.primary,
    onPressed: widget.track == null
        ? null
        : () async {
            await refresh();
            if (!context.mounted) return;
            await showDialog<void>(
              context: context,
              builder: (dialog) => AlertDialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                title: const UiText('Disponibilidade da faixa'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.track!.title),
                    const SizedBox(height: 16),
                    for (final item in {
                      'local': 'Arquivo local',
                      'permanent': 'Download permanente',
                      'cache': 'Em cache',
                    }.entries)
                      ListTile(
                        dense: true,
                        leading: MtIcon(
                          statuses.contains(item.key)
                              ? Icons.check_circle
                              : Icons.remove_circle_outline,
                        ),
                        title: UiText(item.value),
                      ),
                    if (statuses.isEmpty) UiText(status),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const UiText('Fechar'),
                  ),
                ],
              ),
            );
          },
  );
}
