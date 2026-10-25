import 'design_icon.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../library/playlist_recommendations.dart';

import '../domain/track.dart';
import '../library/catalog.dart';
import '../library/m3u8.dart';
import 'ui_language.dart';

Future<String?> pickPlaylistTrack(
  BuildContext context,
  List<Track> tracks, {
  List<String> suggested = const [],
  String? expected,
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _TrackPicker(tracks: tracks, suggested: suggested, expected: expected),
);

class PlaylistImportReview extends StatefulWidget {
  const PlaylistImportReview({
    super.key,
    required this.report,
    required this.tracks,
  });
  final PlaylistImportReport report;
  final List<Track> tracks;
  @override
  State<PlaylistImportReview> createState() => _PlaylistImportReviewState();
}

class _PlaylistImportReviewState extends State<PlaylistImportReview> {
  late final byId = {for (final t in widget.tracks) t.id: t};
  late final issues = widget.report.entries.where((e) => e.unresolved).toList();
  final collapsed = <PlaylistImportEntry>{};
  Map<int, List<String>> recommendations = {};
  @override
  void initState() {
    super.initState();
    compute(recommendPlaylistReplacements, (issues, widget.tracks)).then((
      values,
    ) {
      if (mounted) setState(() => recommendations = values);
    });
  }

  Future<void> locate(PlaylistImportEntry entry) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TrackPicker(
        tracks: widget.tracks,
        suggested:
            recommendations[entry.line] ??
            [...entry.candidates, ...entry.suggestions],
        expected:
            '${expectedPlaylistTitle(entry)}${entry.artist.isEmpty ? '' : ' • ${entry.artist}'}',
      ),
    );
    if (result != null && mounted) {
      setState(() {
        entry.selected = result;
        entry.removed = false;
        collapsed.add(entry);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    title: const UiText('Revisar importação'),
    content: SizedBox(
      width: 760,
      height: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.report.ids.length} ${ui(context, 'faixas localizadas')} · ${widget.report.unresolved} ${ui(context, 'referências pendentes')}',
          ),
          const SizedBox(height: 12),
          const UiText(
            'Localize as referências não encontradas ou remova-as somente desta importação. Os arquivos originais são preservados.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: issues.length,
              itemBuilder: (context, i) {
                final e = issues[i];
                final selected = byId[e.selected];
                if (e.selected != null && !e.removed && collapsed.contains(e)) {
                  return ListTile(
                    key: ValueKey('playlist.resolved.${e.line}'),
                    leading: const MtIcon(
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                    title: Text(
                      selected == null
                          ? e.selected!
                          : '${selected.title} • ${selected.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const UiText('Faixa confirmada'),
                    trailing: IconButton(
                      tooltip: ui(context, 'Alterar faixa confirmada'),
                      onPressed: () => setState(() => collapsed.remove(e)),
                      icon: const MtIcon(Icons.expand_more),
                    ),
                    onTap: () => setState(() => collapsed.remove(e)),
                  );
                }
                final uri = Uri.tryParse(e.reference);
                final reference =
                    uri?.scheme == 'https' || uri?.scheme == 'http'
                    ? ui(context, 'Referência remota não suportada')
                    : e.reference;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${ui(context, 'Expected track')}: ${expectedPlaylistTitle(e)}${e.artist.isEmpty ? '' : ' • ${e.artist}'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${e.line}: $reference',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (e.selected != null && !e.removed)
                        Text(byId[e.selected]?.title ?? e.selected!)
                      else
                        UiText(
                          e.removed
                              ? 'Removida da importação'
                              : e.candidates.length > 1
                              ? 'Referência ambígua'
                              : 'Faixa não encontrada',
                        ),
                      for (final id
                          in (recommendations[e.line] ?? const <String>[]).take(
                            3,
                          ))
                        if (byId[id] != null && !collapsed.contains(e))
                          TextButton.icon(
                            icon: const MtIcon(Icons.swap_horiz),
                            label: Text(
                              '${ui(context, 'Use')}: ${byId[id]!.title} • ${byId[id]!.artist} • ${byId[id]!.album}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () => setState(() {
                              e.selected = id;
                              e.removed = false;
                              collapsed.add(e);
                            }),
                          ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (e.selected != null && !e.removed)
                            IconButton(
                              tooltip: ui(context, 'Recolher faixa confirmada'),
                              onPressed: () => setState(() => collapsed.add(e)),
                              icon: const MtIcon(Icons.expand_less),
                            ),
                          TextButton.icon(
                            onPressed: () => locate(e),
                            icon: const MtIcon(Icons.search),
                            label: const UiText('Localizar faixa'),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => e.removed = !e.removed),
                            child: UiText(
                              e.removed
                                  ? 'Restaurar referência'
                                  : 'Remover da importação',
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const UiText('Cancelar'),
      ),
      FilledButton(
        onPressed: widget.report.unresolved == 0 && widget.report.ids.isNotEmpty
            ? () => Navigator.pop(context, widget.report.ids)
            : null,
        child: const UiText('Importar faixas revisadas'),
      ),
    ],
  );
}

class _TrackPicker extends StatefulWidget {
  const _TrackPicker({
    required this.tracks,
    required this.suggested,
    this.expected,
  });
  final String? expected;
  final List<Track> tracks;
  final List<String> suggested;
  @override
  State<_TrackPicker> createState() => _TrackPickerState();
}

class _TrackPickerState extends State<_TrackPicker> {
  String query = '';
  late final searchable = [
    for (final t in widget.tracks)
      (t, searchKey('${t.title} ${t.artist} ${t.album} ${t.fileName}')),
  ];
  @override
  Widget build(BuildContext context) {
    final text = searchKey(query);
    final ordered = List.of(searchable);
    if (text.isEmpty) {
      ordered.sort(
        (a, b) => widget.suggested
            .indexOf(a.$1.id)
            .compareTo(widget.suggested.indexOf(b.$1.id)),
      );
    }
    final values = ordered
        .where(
          (e) => text.isEmpty
              ? widget.suggested.contains(e.$1.id)
              : e.$2.contains(text),
        )
        .take(100)
        .map((e) => e.$1)
        .toList();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      title: const UiText('Localizar faixa'),
      content: SizedBox(
        width: 680,
        height: 420,
        child: Column(
          children: [
            if (widget.expected != null)
              Text(
                '${ui(context, 'Expected track')}: ${widget.expected}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: ui(
                  context,
                  'Buscar músicas, artistas, álbuns e playlists',
                ),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            if (text.isEmpty)
              const UiText(
                'Suggestions use title, artist, duration and file name. Confirm the correct recording.',
              ),
            Expanded(
              child: ListView.builder(
                itemCount: values.length,
                itemBuilder: (context, i) {
                  final t = values[i];
                  return ListTile(
                    title: Text(t.title),
                    subtitle: Text(
                      '${t.artist} · ${t.album}\n${t.account} · ${t.sourcePath}',
                      maxLines: 3,
                    ),
                    onTap: () => Navigator.pop(context, t.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const UiText('Cancelar'),
        ),
      ],
    );
  }
}
