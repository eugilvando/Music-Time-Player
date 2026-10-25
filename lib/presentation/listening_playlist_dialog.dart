import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../library/listening_insights.dart';
import '../library/listening_playlist.dart';
import '../library/insight_artist_templates.dart';
import '../library/catalog.dart';
import '../library/m3u8.dart';
import '../persistence/library_store.dart';
import 'design_icon.dart';
import 'playlist_import_review.dart';
import 'ui_language.dart';

String insightText(BuildContext context, String en, String pt) =>
    Localizations.of<UiLanguage>(context, UiLanguage)?.code == 'pt' ? pt : en;

class ListeningPlaylistDialog extends StatefulWidget {
  const ListeningPlaylistDialog({
    super.key,
    required this.report,
    required this.catalog,
    required this.store,
    required this.offlineIds,
    required this.onPlay,
    required this.onSaved,
    this.offlineOnly = false,
    this.artistTemplates,
  });
  final ListeningReport report;
  final List<Track> catalog;
  final LibraryStore store;
  final Set<String> offlineIds;
  final bool offlineOnly;
  final InsightArtistTemplates? artistTemplates;
  final Future<void> Function(List<Track>, int, String) onPlay;
  final VoidCallback onSaved;
  @override
  State<ListeningPlaylistDialog> createState() =>
      _ListeningPlaylistDialogState();
}

class _ListeningPlaylistDialogState extends State<ListeningPlaylistDialog> {
  late final name = TextEditingController(
    text:
        'Last.fm · ${widget.report.from.toLocal().toIso8601String().substring(0, 10)} — ${widget.report.until.toLocal().toIso8601String().substring(0, 10)}',
  );
  String criterion = 'top';
  late final artists =
      {
          ...widget.catalog.expand(
            (t) => [...t.artistNames, ...t.albumArtistNames],
          ),
          ...widget.report.artists.map((r) => r.title),
        }.where((a) => a.trim().isNotEmpty).toList()
        ..sort((a, b) => artistNameKey(a).compareTo(artistNameKey(b)));
  late String artist = artists.firstOrNull ?? '';
  int limit = 30, perArtist = 3, generation = 0;
  late bool offline = widget.offlineOnly;
  bool busy = false, preparing = true;
  bool automaticName = true;
  String? error;
  PlaylistImportReport? selection;
  late final byId = {for (final track in widget.catalog) track.id: track};
  String t(String en, String pt) => insightText(context, en, pt);
  List<Track> get eligible => offline
      ? widget.catalog.where((t) => widget.offlineIds.contains(t.id)).toList()
      : widget.catalog;
  @override
  void initState() {
    super.initState();
    prepare();
  }

  @override
  void dispose() {
    generation++;
    name.dispose();
    super.dispose();
  }

  Future<void> prepare() async {
    final request = ++generation;
    setState(() {
      preparing = true;
      error = null;
      selection = null;
      if (automaticName && criterion.startsWith('artist_')) {
        name.text =
            '$artist · ${criterion == 'artist_radio'
                ? t('Artist radio', 'Rádio do artista')
                : criterion == 'artist_period'
                ? t('Most played in period', 'Mais ouvidas no período')
                : t('Last.fm most popular', 'Mais populares no Last.fm')}';
      }
    });
    try {
      final report = criterion.startsWith('artist_')
          ? await widget.artistTemplates!.prepare(
              criterion: criterion,
              artist: artist,
              report: widget.report,
              catalog: eligible,
              limit: limit,
              offline: widget.offlineOnly,
            )
          : await compute(prepareListeningPlaylist, (
              report: widget.report,
              catalog: eligible,
              criterion: criterion,
              limit: limit,
              perArtist: perArtist,
            ));
      if (mounted && generation == request) {
        setState(() {
          selection = report;
          preparing = false;
        });
      }
    } catch (_) {
      if (mounted && generation == request) {
        setState(() {
          preparing = false;
          error = t(
            'Could not prepare the selection. Check Last.fm settings or cached data. Artist radio needs similar artists present in your library.',
            'Não foi possível preparar a seleção. Confira o Last.fm ou os dados em cache. A rádio exige artistas similares presentes na biblioteca.',
          );
        });
      }
    }
  }

  List<Track> get selected {
    final ids = selection?.ids.toSet() ?? <String>{};
    return [
      for (final id in ids)
        if (byId[id] != null && (!offline || widget.offlineIds.contains(id)))
          byId[id]!,
    ];
  }

  Future<void> act(bool save) async {
    if (busy || preparing || selected.isEmpty || name.text.trim().isEmpty) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final values = selected;
      if (save) {
        await widget.store.importPlaylist(
          name.text.trim(),
          values.map((t) => t.id).toList(),
        );
        widget.onSaved();
      } else {
        await widget.onPlay(values, 0, name.text.trim());
      }
      if (mounted) Navigator.pop(context, save);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = t(
            'Action failed. Your selection is preserved.',
            'A ação falhou. Sua seleção foi preservada.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = selection;
    return AlertDialog(
      title: Text(t('Create a playlist', 'Criar playlist')),
      insetPadding: const EdgeInsets.all(24),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      content: SizedBox(
        width: 680,
        height: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(
                  'From your Last.fm listening · only music in your library',
                  'A partir do Last.fm · somente músicas da sua biblioteca',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                enabled: !busy,
                maxLength: 120,
                onChanged: (_) => setState(() => automaticName = false),
                decoration: InputDecoration(
                  labelText: t('Playlist name', 'Nome da playlist'),
                ),
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: criterion,
                decoration: InputDecoration(
                  labelText: t('Based on', 'Baseada em'),
                ),
                items: [
                  if (widget.artistTemplates != null) ...[
                    DropdownMenuItem(
                      value: 'artist_radio',
                      child: Text(
                        t(
                          'Artist radio · similar artists',
                          'Rádio do artista · artistas similares',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'artist_period',
                      child: Text(
                        t(
                          'Artist most played · selected period',
                          'Mais ouvidas do artista · período selecionado',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'artist_top',
                      child: Text(
                        t(
                          'Artist most popular · Last.fm global',
                          'Mais populares do artista · Last.fm global',
                        ),
                      ),
                    ),
                  ],
                  DropdownMenuItem(
                    value: 'top',
                    child: Text(t('Most played tracks', 'Faixas mais ouvidas')),
                  ),
                  DropdownMenuItem(
                    value: 'balanced',
                    child: Text(t('Balanced artists', 'Artistas equilibrados')),
                  ),
                  if (widget.report.complete &&
                      widget.report.invalid == 0 &&
                      widget.report.previousScrobbles > 0)
                    DropdownMenuItem(
                      value: 'rediscover',
                      child: Text(
                        t(
                          'Previous favorites, absent this period',
                          'Favoritas anteriores, ausentes neste período',
                        ),
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (v) {
                        if (v != null) {
                          criterion = v;
                          prepare();
                        }
                      },
              ),
              const SizedBox(height: 10),
              if (criterion.startsWith('artist_')) ...[
                Autocomplete<String>(
                  key: ValueKey('insights.artist.$criterion'),
                  initialValue: TextEditingValue(text: artist),
                  optionsBuilder: (value) => artists
                      .where(
                        (a) => searchKey(a).contains(searchKey(value.text)),
                      )
                      .take(20),
                  onSelected: (value) {
                    artist = value;
                    prepare();
                  },
                  fieldViewBuilder: (context, input, focus, submit) =>
                      TextFormField(
                        controller: input,
                        focusNode: focus,
                        onChanged: (value) {
                          if (artistNameKey(value) != artistNameKey(artist)) {
                            generation++;
                            setState(() {
                              selection = null;
                              preparing = false;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          labelText: t(
                            'Artist · choose a suggestion',
                            'Artista · escolha uma sugestão',
                          ),
                        ),
                        onFieldSubmitted: (_) => submit(),
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  t(
                    'Only library tracks are saved. Global popularity is different from your listening counts.',
                    'Somente faixas da biblioteca serão salvas. Popularidade global é diferente das suas contagens pessoais.',
                  ),
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: limit,
                      decoration: InputDecoration(
                        labelText: t('Tracks', 'Faixas'),
                      ),
                      items: [
                        for (final n in [10, 20, 30, 50, 100])
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              if (v != null) {
                                limit = v;
                                prepare();
                              }
                            },
                    ),
                  ),
                  if (!criterion.startsWith('artist_')) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: perArtist,
                        decoration: InputDecoration(
                          labelText: t('Max per artist', 'Máximo por artista'),
                        ),
                        items: [
                          for (final n in [1, 2, 3, 5, 10, 100])
                            DropdownMenuItem(value: n, child: Text('$n')),
                        ],
                        onChanged: busy || criterion.startsWith('artist_')
                            ? null
                            : (v) {
                                if (v != null) {
                                  perArtist = v;
                                  prepare();
                                }
                              },
                      ),
                    ),
                  ],
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t('Only available offline', 'Somente disponíveis offline'),
                ),
                value: offline,
                onChanged: busy || widget.offlineOnly
                    ? null
                    : (v) {
                        offline = v;
                        prepare();
                      },
              ),
              if (!widget.report.complete || widget.report.invalid > 0)
                Text(
                  t(
                    'Based on loaded data; history is incomplete.',
                    'Baseada nos dados carregados; histórico incompleto.',
                  ),
                ),
              if (preparing || busy) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (report != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${selected.length} ${t('matched', 'localizadas')} · ${report.unresolved} ${t('need review', 'para revisar')}',
                      ),
                    ),
                    TextButton(
                      onPressed: busy || preparing || report.unresolved == 0
                          ? null
                          : () async {
                              await showDialog<List<String>>(
                                context: context,
                                builder: (_) => PlaylistImportReview(
                                  report: report,
                                  tracks: eligible,
                                ),
                              );
                              if (mounted) setState(() {});
                            },
                      child: Text(t('Review items', 'Revisar itens')),
                    ),
                  ],
                ),
                Text(
                  t(
                    'Only matched, selected tracks will be saved. Unresolved items are excluded.',
                    'Somente faixas localizadas e selecionadas serão salvas. Pendências são excluídas.',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: selected.isEmpty
                    ? Center(
                        child: Text(
                          t(
                            'No matched tracks in this selection.',
                            'Nenhuma faixa localizada nesta seleção.',
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: selected.length,
                        itemBuilder: (_, i) {
                          final track = selected[i];
                          return ListTile(
                            dense: true,
                            leading: Text('${i + 1}'),
                            title: Text(track.title),
                            subtitle: Text(track.artist),
                            trailing: IconButton(
                              tooltip: t(
                                'Remove from selection',
                                'Remover da seleção',
                              ),
                              icon: const MtIcon(Icons.close),
                              onPressed: busy || preparing
                                  ? null
                                  : () => setState(() {
                                      for (final e in report!.entries) {
                                        if (e.trackId == track.id) {
                                          e.removed = true;
                                        }
                                      }
                                    }),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(t('Cancel', 'Cancelar')),
        ),
        OutlinedButton(
          onPressed:
              busy || preparing || selected.isEmpty || name.text.trim().isEmpty
              ? null
              : () => act(false),
          child: Text(t('Play now', 'Reproduzir agora')),
        ),
        FilledButton(
          onPressed:
              busy || preparing || selected.isEmpty || name.text.trim().isEmpty
              ? null
              : () => act(true),
          child: Text(
            '${t('Save playlist', 'Salvar playlist')} · ${selected.length}',
          ),
        ),
      ],
    );
  }
}
