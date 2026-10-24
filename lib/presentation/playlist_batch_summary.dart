import 'design_icon.dart';

import 'package:flutter/material.dart';

import '../library/playlist_batch_import.dart';
import 'ui_language.dart';

Future<void> showPlaylistBatchSummary(
  BuildContext context,
  List<PlaylistImportResult> results,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    title: const UiText('Import summary'),
    content: SizedBox(
      width: 600,
      height: 360,
      child: ListView(
        children: [
          Text(
            '${results.where((r) => r.id != null && r.pending == 0).length} ${ui(context, 'Imported')}',
          ),
          Text(
            '${results.where((r) => r.id != null && r.pending > 0).length} ${ui(context, 'Imported with pending items')}',
          ),
          Text(
            '${results.where((r) => r.failure != null).length} ${ui(context, 'Failures')}',
          ),
          for (final r in results)
            ListTile(
              leading: MtIcon(
                r.failure != null
                    ? Icons.error_outline
                    : r.pending > 0
                    ? Icons.warning_amber
                    : Icons.check_circle_outline,
              ),
              title: Text(r.name),
              subtitle: Text(
                r.failure != null
                    ? ui(
                        context,
                        r.failure == 'read'
                            ? 'Cannot read file'
                            : r.failure == 'save'
                            ? 'Cannot save playlist'
                            : 'Invalid or unsupported playlist',
                      )
                    : '${r.found} ${ui(context, 'found')} / ${r.pending} ${ui(context, 'items not found')}',
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const UiText('Close'),
      ),
    ],
  ),
);
