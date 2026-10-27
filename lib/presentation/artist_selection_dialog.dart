import 'design_icon.dart';

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
  List<Track> seeds = const [],
  String? seedLabel,
  required List<Track> eligible,
  required AppSettings settings,
  required ArtistSimilarity similarity,
  required Future<void> Function(List<Track>, int, String) onPlay,
  required Future<void> Function(List<Track>) onSave,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ArtistSelectionDialog(
    artist: artist,
    seeds: seeds,
    seedLabel: seedLabel,
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
    required this.seeds,
    required this.seedLabel,
    required this.radio,
    required this.action,
    required this.eligible,
    required this.settings,
    required this.similarity,
    required this.onPlay,
    required this.onSave,
  });
  final String artist;
  final List<Track> seeds;
  final String? seedLabel;
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
  bool localRadio = false;
  bool fallbackMix = false;
  SimilarityResult? similarityResult;
  int similarCount = 0, matchedCount = 0, generation = 0;
  String get selectionType => widget.seeds.isNotEmpty
      ? !radio || fallbackMix
            ? localRadio
                  ? 'Local item mix'
                  : 'Item mix'
            : localRadio
            ? 'Local item radio'
            : 'Item radio'
      : !radio || fallbackMix
      ? localRadio
            ? 'Local artist mix'
            : 'Artist mix'
      : localRadio
      ? 'Local artist radio'
      : 'Artist radio';
  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    generate();
  }

  Future<void> generate({bool refresh = false}) async {
    final request = ++generation;
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final hasArtist = widget.eligible.any(
        (t) => trackByArtist(t, widget.artist),
      );
      final response = hasArtist
          ? await widget.similarity.lookup(
              widget.artist,
              refresh: refresh,
              offline: widget.settings.visualBool(
                'offline_only',
                fallback: false,
              ),
            )
          : null;
      if (!mounted || request != generation) return;
      final count = widget.settings.artistSelectionSize(radio: radio);
      final work = (
        tracks: widget.eligible,
        artist: widget.artist,
        count: count,
        radio: radio,
        similar: response?.names ?? <String>[],
        local: false,
      );
      final result = widget.seeds.isEmpty
          ? await compute(prepareArtistPreview, work)
          : await compute(prepareItemPreview, (
              work: work,
              seeds: widget.seeds,
            ));
      if (!mounted || request != generation) return;
      if (mounted) {
        setState(() {
          selection = result.tracks;
          similarityResult = response;
          similarCount = result.similar;
          matchedCount = result.matched;
          localRadio = result.local;
          fallbackMix = result.fallbackMix;
        });
      }
      if (mounted && firstGeneration && result.tracks.isNotEmpty) {
        firstGeneration = false;
        if (widget.action == 'play') {
          final title =
              '${ui(context, selectionType)} · ${widget.seedLabel ?? widget.artist}';
          Navigator.pop(context);
          await widget.onPlay(List<Track>.of(result.tracks), 0, title);
        } else if (widget.action == 'save') {
          await widget.onSave(List<Track>.of(result.tracks));
        }
      }
      firstGeneration = false;
    } catch (_) {
      if (mounted && request == generation) {
        firstGeneration = false;
        setState(() => failure = 'Cannot generate selection. Try again.');
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    scrollable: true,
    title: Text(
      '${ui(context, selectionType)} · ${widget.seedLabel ?? widget.artist}',
    ),
    content: SizedBox(
      width: 640,
      height: 430,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading) const LinearProgressIndicator(),
          if (widget.seeds.isNotEmpty)
            Text('${ui(context, 'Seed artist')}: ${widget.artist}'),
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
                      const UiText(
                        'Uses all visible library sources; page search and filters do not limit this selection. Offline mode is respected.',
                      ),
                      if (!loading) ...[
                        Text(
                          '$similarCount ${ui(context, localRadio ? 'related artists' : 'similar artists')} · $matchedCount ${ui(context, 'in your library')}',
                        ),
                        if (localRadio)
                          const UiText(
                            'Local fallback applied automatically from genres and artist credits.',
                          ),
                        if (fallbackMix && selection.isNotEmpty)
                          const UiText(
                            'No related tracks were available; continuing with the seed artist/items.',
                          ),
                        if (similarityResult?.cached == true)
                          const UiText('Using saved similar artists.'),
                        if (similarityResult != null &&
                            similarityResult!.issue != SimilarityIssue.none)
                          UiText(switch (similarityResult!.issue) {
                            SimilarityIssue.missingKey => 'Last.fm key is missing or invalid. Local matching is used when possible.',
                            SimilarityIssue.network => 'Last.fm is unavailable. Saved data or local recommendations are used when possible.',
                            SimilarityIssue.offline => 'Offline mode: only saved similar artists and local recommendations are available.',
                            SimilarityIssue.noResults => 'Last.fm returned no recommendations. Local matching was attempted automatically.',
                            SimilarityIssue.none => '',
                          }),
                      ],
                      if (failure != null) UiText(failure!),
                      if (!loading && selection.isEmpty) ...[
                        UiText(
                          !widget.eligible.any(
                                (t) => trackByArtist(t, widget.artist),
                              )
                              ? 'No eligible tracks for this artist.'
                              : radio && localRadio
                              ? 'No related artists with eligible tracks were found locally. Use Artist mix.'
                              : radio
                              ? 'No similar artists with eligible library tracks. Check Last.fm or use Artist mix.'
                              : 'No eligible tracks for this artist.',
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
        onPressed: loading || saving ? null : () => generate(),
        child: const UiText('Regenerate'),
      ),
      TextButton(
        onPressed:
            loading ||
                saving ||
                widget.settings.visualBool('offline_only', fallback: false)
            ? null
            : () => generate(refresh: true),
        child: const UiText('Refresh Last.fm'),
      ),
      if (!radio || selection.isNotEmpty)
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
      if (!radio || selection.isNotEmpty)
        FilledButton.icon(
          onPressed: loading || saving || selection.isEmpty
              ? null
              : () async {
                  final snapshot = List<Track>.of(selection);
                  final title =
                      '${ui(context, selectionType)} · ${widget.seedLabel ?? widget.artist}';
                  Navigator.pop(context);
                  await widget.onPlay(snapshot, 0, title);
                },
          icon: const MtIcon(Icons.play_arrow),
          label: const UiText('Play'),
        ),
    ],
  );
}
