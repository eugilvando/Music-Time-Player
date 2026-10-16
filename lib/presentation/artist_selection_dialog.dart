import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../library/artist_selection.dart';
import '../library/artist_similarity.dart';
import '../settings/app_settings.dart';
import 'ui_language.dart';

Future<void> showArtistSelection(
  BuildContext context, {
  required String artist,
  required bool radio,
  String action = 'preview',
  required List<Track> eligible,
  required AppSettings settings,
  required ArtistSimilarity similarity,
  required Future<void> Function(List<Track>, int, String) onPlay,
  required Future<void> Function(List<Track>) onSave,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ArtistSelectionDialog(
    artist: artist,
    radio: radio,
    action: action,
    eligible: eligible,
    settings: settings,
    similarity: similarity,
    onPlay: onPlay,
    onSave: onSave,
  ),
);

class _ArtistSelectionDialog extends StatefulWidget {
  const _ArtistSelectionDialog({
    required this.artist,
    required this.radio,
    required this.action,
    required this.eligible,
    required this.settings,
    required this.similarity,
    required this.onPlay,
    required this.onSave,
  });
  final String artist;
  final bool radio;
  final String action;
  final List<Track> eligible;
  final AppSettings settings;
  final ArtistSimilarity similarity;
  final Future<void> Function(List<Track>, int, String) onPlay;
  final Future<void> Function(List<Track>) onSave;
  @override
  State<_ArtistSelectionDialog> createState() => _ArtistSelectionDialogState();
}

class _ArtistSelectionDialogState extends State<_ArtistSelectionDialog> {
  late bool radio = widget.radio;
  bool loading = true, saving = false;
  List<Track> selection = [];
  String? failure;
  bool firstGeneration = true;
  @override
  void initState() {
    super.initState();
    generate();
  }

  Future<void> generate() async {
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final similar =
          radio && widget.eligible.any((t) => trackByArtist(t, widget.artist))
          ? await widget.similarity.names(
              widget.artist,
              offline: widget.settings.visualBool(
                'offline_only',
                fallback: false,
              ),
            )
          : <String>[];
      final count = widget.settings.artistSelectionSize(radio: radio);
      final result = await compute(prepareArtistSelection, (
        tracks: widget.eligible,
        artist: widget.artist,
        count: count,
        radio: radio,
        similar: similar,
      ));
      if (mounted) {
        setState(() {
          selection = result;
        });
      }
      if (mounted && firstGeneration && result.isNotEmpty) {
        firstGeneration = false;
        if (widget.action == 'play') {
          final title =
              '${ui(context, radio ? 'Artist radio' : 'Artist mix')} · ${widget.artist}';
          Navigator.pop(context);
          await widget.onPlay(List<Track>.of(result), 0, title);
        } else if (widget.action == 'save') {
          await widget.onSave(List<Track>.of(result));
        }
      }
      firstGeneration = false;
    } catch (_) {
      if (mounted) {
        setState(() => failure = 'Cannot generate selection. Try again.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      '${ui(context, radio ? 'Artist radio' : 'Artist mix')} · ${widget.artist}',
    ),
    content: SizedBox(
      width: 640,
      height: 430,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading) const LinearProgressIndicator(),
          Text(
            '${selection.length} ${ui(context, 'tracks')} / ${widget.settings.artistSelectionSize(radio: radio)} ${ui(context, 'requested')}',
          ),
          Expanded(
            child: ListView.builder(
              itemCount: selection.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const UiText(
                        'Only eligible library tracks. Guests and album-artist credits are included.',
                      ),
                      if (failure != null) UiText(failure!),
                      if (!loading && selection.isEmpty) ...[
                        UiText(
                          !widget.eligible.any(
                                (t) => trackByArtist(t, widget.artist),
                              )
                              ? 'No eligible tracks for this artist.'
                              : radio
                              ? 'No similar artists with eligible library tracks. Check Last.fm or use Artist mix.'
                              : 'No eligible tracks for this artist.',
                        ),
                        if (radio)
                          TextButton(
                            onPressed: () {
                              radio = false;
                              generate();
                            },
                            child: const UiText('Use Artist mix'),
                          ),
                      ],
                    ],
                  );
                }
                final track = selection[i - 1];
                return ListTile(
                  dense: true,
                  leading: Text('$i'),
                  title: Text(track.title),
                  subtitle: Text(track.artist),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: loading || saving ? null : generate,
        child: const UiText('Regenerate'),
      ),
      TextButton(
        onPressed: loading || saving || selection.isEmpty
            ? null
            : () async {
                setState(() => saving = true);
                try {
                  await widget.onSave(List.of(selection));
                } finally {
                  if (mounted) setState(() => saving = false);
                }
              },
        child: const UiText('Save as playlist'),
      ),
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const UiText('Close'),
      ),
      FilledButton.icon(
        onPressed: loading || saving || selection.isEmpty
            ? null
            : () async {
                final snapshot = List<Track>.of(selection);
                final title =
                    '${ui(context, radio ? 'Artist radio' : 'Artist mix')} · ${widget.artist}';
                Navigator.pop(context);
                await widget.onPlay(snapshot, 0, title);
              },
        icon: const Icon(Icons.play_arrow),
        label: const UiText('Play'),
      ),
    ],
  );
}
