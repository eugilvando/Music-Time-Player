import '../library/listening_playlist.dart';

import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../infrastructure/lastfm.dart';
import '../library/catalog.dart';
import '../library/listening_insights.dart';
import '../library/m3u8.dart';
import '../persistence/library_store.dart';
import '../settings/app_settings.dart';
import 'design_icon.dart';
import 'listening_playlist_dialog.dart';
import 'now_playing_artwork.dart';
import 'artist_portrait.dart';
import '../library/insight_artist_templates.dart';

String listeningCsvCell(String text) {
  final safe = RegExp(r'^[\s]*[=+\-@]').hasMatch(text) ? "'$text" : text;
  return '"${safe.replaceAll('"', '""')}"';
}

String listeningReportCsv(ListeningReport report) =>
    '\uFEFF${[
      ['Last.fm profile', report.user],
      ['From (UTC)', report.from.toUtc().toIso8601String()],
      ['Until exclusive (UTC)', report.until.toUtc().toIso8601String()],
      ['Updated (UTC)', report.updatedAt.toIso8601String()],
      ['Coverage', report.complete && report.invalid == 0 ? 'complete' : 'partial'],
      ['Loaded scrobbles', '${report.scrobbles}'],
      ['Entity', 'Title', 'Artist', 'Scrobbles'],
      for (final r in report.tracks) ['Track', r.title, r.artist, '${r.count}'],
      for (final r in report.artists) ['Artist', r.title, r.artist, '${r.count}'],
      for (final r in report.albums) ['Album', r.title, r.artist, '${r.count}'],
      ['Activity day (local)', 'Scrobbles'],
      for (final day in report.days.keys.toList()..sort()) [day, '${report.days[day]}'],
    ].map((row) => row.map(listeningCsvCell).join(',')).join('\r\n')}\r\n';

class ListeningInsightsPage extends StatefulWidget {
  const ListeningInsightsPage({
    super.key,
    required this.repository,
    required this.settings,
    required this.store,
    required this.catalog,
    required this.catalogRevision,
    required this.availableOffline,
    required this.onPlay,
    required this.onSaved,
    required this.onConfigure,
    required this.onOpen,
  });
  final ListeningInsightsRepository repository;
  final AppSettings settings;
  final LibraryStore store;
  final List<Track> catalog;
  final int catalogRevision;
  final Future<Set<String>> Function() availableOffline;
  final Future<void> Function(List<Track>, int, String) onPlay;
  final VoidCallback onSaved, onConfigure;
  final void Function(String, CatalogGroup) onOpen;
  @override
  State<ListeningInsightsPage> createState() => _ListeningInsightsPageState();
}

class _ListeningInsightsPageState extends State<ListeningInsightsPage> {
  ListeningReport? data;
  ListeningRequest? request;
  PlaylistImportReport? matches;
  ListeningCatalogMatches? libraryIndex;
  Map<String, PlaylistImportEntry> resolvedTracks = {};
  int matchGeneration = 0;
  String period = '30', tab = 'overview', reportGroup = 'month';
  late String profile;
  late bool offline;
  bool loading = false, openingPlaylist = false, exporting = false;
  String? error;
  int generation = 0, currentPage = 0, totalPages = 0, offset = 0;
  int periodSelection = 0;
  DateTimeRange? custom;
  String t(String en, String pt) => insightText(context, en, pt);
  String get currentProfile =>
      (widget.settings.preferences.getString('lastfm.profile_user') ?? '')
          .trim();
  bool get currentOffline =>
      widget.settings.visualBool('offline_only', fallback: false);
  String get cacheKey {
    final now = DateTime.now();
    return custom == null
        ? '$period:${now.year}-${now.month}-${now.day}:${now.timeZoneOffset.inMinutes}'
        : 'custom:${custom!.start.toIso8601String()}:${custom!.end.toIso8601String()}:${now.timeZoneOffset.inMinutes}';
  }

  @override
  void initState() {
    super.initState();
    profile = currentProfile;
    offline = currentOffline;
    load();
  }

  @override
  void didUpdateWidget(covariant ListeningInsightsPage old) {
    super.didUpdateWidget(old);
    if (profile != currentProfile || offline != currentOffline) {
      request?.cancelled = true;
      generation++;
      if (profile != currentProfile) {
        data = null;
        matches = null;
      }
      profile = currentProfile;
      offline = currentOffline;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    } else if (old.catalogRevision != widget.catalogRevision && data != null) {
      final report = data!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) resolve(report);
      });
    }
  }

  @override
  void dispose() {
    request?.cancelled = true;
    generation++;
    super.dispose();
  }

  Future<void> resolve(ListeningReport report) async {
    final ticket = ++matchGeneration;
    final available = offline ? await widget.availableOffline() : null;
    if (!mounted || !identical(data, report) || ticket != matchGeneration) {
      return;
    }
    final catalog = widget.catalog
        .where((t) => available == null || available.contains(t.id))
        .toList();
    final index = await compute(resolveListeningCatalog, (report, catalog));
    if (mounted && identical(data, report) && ticket == matchGeneration) {
      setState(() {
        libraryIndex = index;
        matches = index.matches;
        resolvedTracks = {
          for (var i = 0; i < report.tracks.length; i++)
            report.tracks[i].key: index.matches.entries[i],
        };
      });
    }
  }

  Future<void> load({bool refresh = false, bool more = false}) async {
    request?.cancelled = true;
    final ticket = ++generation;
    final token = ListeningRequest();
    request = token;
    final user = profile, key = cacheKey;
    if (user.isEmpty) {
      if (mounted) {
        setState(() {
          loading = false;
          error = null;
        });
      }
      return;
    }
    setState(() {
      loading = true;
      error = null;
      currentPage = 0;
      totalPages = 0;
    });
    try {
      var cached = more ? data : await widget.repository.cached(user, key);
      if (!mounted || ticket != generation) return;
      if (!refresh && cached != null) {
        setState(() {
          data = cached;
          matches = null;
        });
        await resolve(cached);
        if (!mounted || ticket != generation) return;
        if (offline ||
            (!more &&
                DateTime.now().toUtc().difference(cached.updatedAt) <
                    const Duration(minutes: 15))) {
          setState(() => loading = false);
          return;
        }
      }
      if (offline) {
        setState(() {
          loading = false;
          error = t(
            'Offline: no saved report for this period.',
            'Offline: nenhum relatório salvo para este período.',
          );
        });
        return;
      }
      final now = DateTime.now().toUtc();
      final until = more && cached != null
          ? cached.until
          : custom == null
          ? now
          : (DateTime(
                  custom!.end.year,
                  custom!.end.month,
                  custom!.end.day + 1,
                ).toUtc().isBefore(now)
                ? DateTime(
                    custom!.end.year,
                    custom!.end.month,
                    custom!.end.day + 1,
                  ).toUtc()
                : now);
      final local = now.toLocal();
      final from = more && cached != null
          ? cached.from
          : custom?.start.toUtc() ??
                (period == 'all'
                    ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
                    : DateTime(
                        local.year,
                        local.month,
                        local.day - int.parse(period) + 1,
                      ).toUtc());
      var progressAt = DateTime.fromMillisecondsSinceEpoch(0);
      final result = await widget.repository.load(
        user: user,
        period: key,
        from: from,
        until: until,
        request: token,
        resume: more ? cached : null,
        onProgress: (page, total) {
          if (mounted &&
              ticket == generation &&
              (page == total ||
                  DateTime.now().difference(progressAt).inMilliseconds > 500)) {
            progressAt = DateTime.now();
            setState(() {
              currentPage = page;
              totalPages = total;
            });
          }
        },
      );
      if (!mounted || ticket != generation) return;
      setState(() {
        data = result;
        matches = null;
        loading = false;
        offset = 0;
      });
      await resolve(result);
    } on ListeningCancelled {
      if (mounted && ticket == generation) setState(() => loading = false);
    } catch (exception) {
      if (!mounted || ticket != generation) return;
      setState(() {
        loading = false;
        error = exception is LastFmException && exception.code == 6
            ? t(
                'Last.fm profile not found. Check your username.',
                'Perfil Last.fm não encontrado. Confira seu usuário.',
              )
            : exception is LastFmException &&
                  (exception.code == 10 || exception.code == 26)
            ? t(
                'Last.fm API key is invalid or suspended.',
                'A chave Last.fm é inválida ou está suspensa.',
              )
            : t(
                'Could not load Last.fm. Check your API key, username and connection. Previous data is preserved.',
                'Não foi possível carregar o Last.fm. Confira chave, usuário e conexão. Os dados anteriores foram preservados.',
              );
      });
    }
  }

  Future<void> playlist() async {
    if (openingPlaylist || data == null || matches == null) return;
    final report = data!, user = profile;
    setState(() => openingPlaylist = true);
    try {
      final offlineIds = await widget.availableOffline();
      if (!mounted || user != profile) return;
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ListeningPlaylistDialog(
          report: report,
          catalog: List.of(widget.catalog),
          store: widget.store,
          offlineIds: offlineIds,
          offlineOnly: offline,
          artistTemplates: InsightArtistTemplates(
            widget.store,
            widget.repository.api,
          ),
          onPlay: widget.onPlay,
          onSaved: widget.onSaved,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = t(
            'Could not open the playlist builder.',
            'Não foi possível abrir o gerador de playlists.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => openingPlaylist = false);
    }
  }

  Future<void> export() async {
    if (data == null || exporting) return;
    final report = data!;
    setState(() => exporting = true);
    try {
      final location = await getSaveLocation(
        suggestedName:
            'MusicTime-Lastfm-${report.from.toIso8601String().substring(0, 10)}.csv',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
      );
      if (location != null) {
        final text = await compute(listeningReportCsv, report);
        await XFile.fromData(
          utf8.encode(text),
          mimeType: 'text/csv',
        ).saveTo(location.path);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = t(
            'Could not export the report.',
            'Não foi possível exportar o relatório.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> choosePeriod(String value) async {
    if (value == 'custom') {
      final now = DateTime.now();
      final chosen = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1970),
        lastDate: now,
        initialDateRange:
            custom ??
            DateTimeRange(
              start: DateTime(now.year, now.month, now.day - 29),
              end: now,
            ),
      );
      if (!mounted) return;
      if (chosen == null) {
        setState(() => periodSelection++);
        return;
      }
      custom = chosen;
    } else {
      custom = null;
    }
    setState(() {
      period = value;
      offset = 0;
      data = null;
      matches = null;
    });
    await load();
  }

  Widget card(Widget child) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
  Widget title(String text) => Text(
    text,
    style: Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.bold),
  );
  Widget ranking(String kind, List<ListeningRank> values, {int? take}) {
    final rows = take == null
        ? values.skip(offset).take(50).toList()
        : values.take(take).toList();
    List<Track> local(ListeningRank row) {
      final index = libraryIndex;
      if (index == null || matches == null) return [];
      if (kind == 'tracks') {
        final id = resolvedTracks[row.key]?.trackId;
        return id != null && index.byId[id] != null ? [index.byId[id]!] : [];
      }
      final ids = kind == 'artists'
          ? index.artists[searchKey(row.title)]
          : index.albums[listeningTrackKey(row.artist, row.title)];
      return [
        for (final id in (ids ?? <String>[]).toSet())
          if (index.byId[id] != null) index.byId[id]!,
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              t(
                'No listening data in this period.',
                'Nenhuma escuta neste período.',
              ),
            ),
          ),
        for (var i = 0; i < rows.length; i++)
          Builder(
            builder: (context) {
              final row = rows[i], found = local(rows[i]);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text('${(take == null ? offset : 0) + i + 1}'),
                    ),
                    if (kind == 'artists')
                      SizedBox.square(
                        dimension: 40,
                        child: ArtistPortrait(
                          artist: row.title,
                          fallbackTrack: found.firstOrNull,
                          enabled: widget.settings.visualBool('artist_photos'),
                          cachedOnly: offline,
                        ),
                      )
                    else
                      SizedBox.square(
                        dimension: 40,
                        child: TrackCover(
                          track: found.firstOrNull,
                          album: kind == 'albums',
                        ),
                      ),
                  ],
                ),
                title: Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  kind == 'artists'
                      ? '${row.count} scrobbles'
                      : '${row.artist} · ${row.count} scrobbles',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: found.isEmpty
                    ? null
                    : () => widget.onOpen(
                        kind == 'tracks' ? 'songs' : kind,
                        CatalogGroup('insights:${row.key}', row.title, found),
                      ),
                trailing: PopupMenuButton<String>(
                  tooltip: t('Actions', 'Ações'),
                  onSelected: (action) {
                    if (action == 'playlist') {
                      playlist();
                    } else if (found.isNotEmpty) {
                      widget.onPlay(found, 0, row.title);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'play',
                      enabled: found.isNotEmpty,
                      child: Text(
                        t('Play in library', 'Reproduzir na biblioteca'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'playlist',
                      enabled: data != null,
                      child: Text(
                        t(
                          'Create playlist from this period',
                          'Criar playlist deste período',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        if (take == null && values.length > 50)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${offset + 1}–${math.min(offset + 50, values.length)} / ${values.length}',
              ),
              IconButton(
                tooltip: t('Previous', 'Anterior'),
                onPressed: offset == 0
                    ? null
                    : () => setState(() => offset = math.max(0, offset - 50)),
                icon: const MtIcon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: t('Next', 'Próxima'),
                onPressed: offset + 50 >= values.length
                    ? null
                    : () => setState(() => offset += 50),
                icon: const MtIcon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }

  Widget activity(ListeningReport report) {
    final keys = report.days.keys.toList()..sort();
    if (keys.isEmpty) {
      return Text(
        t('No listening activity yet.', 'Nenhuma atividade de escuta.'),
      );
    }
    final start = report.from.millisecondsSinceEpoch == 0 || !report.complete
        ? DateTime.parse(keys.first)
        : report.from.toLocal();
    final end = report.until.toLocal();
    final span = math.max(
      1,
      DateTime.utc(end.year, end.month, end.day)
              .difference(DateTime.utc(start.year, start.month, start.day))
              .inDays +
          1,
    );
    final slots = math.min(span, 31),
        counts = List.filled(math.min(span, 31), 0);
    for (final entry in report.days.entries) {
      final date = DateTime.parse(entry.key);
      final delta = DateTime.utc(
        date.year,
        date.month,
        date.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
      final index = (delta * slots ~/ span).clamp(0, slots - 1);
      counts[index] += entry.value;
    }
    final peak = math.max(1, counts.reduce(math.max));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title(t('Listening activity', 'Atividade de escuta')),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < slots; i++)
                Expanded(
                  child: Tooltip(
                    message:
                        '${DateTime(start.year, start.month, start.day + (i * span ~/ slots)).toIso8601String().substring(0, 10)} · ${counts[i]} scrobbles',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Semantics(
                        label: '${counts[i]} scrobbles',
                        child: Container(
                          height: math.max(2, counts[i] / peak * 150),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${DateTime(start.year, start.month, start.day).toIso8601String().substring(0, 10)} — ${end.toIso8601String().substring(0, 10)} · ${t('local dates', 'datas locais')}',
        ),
      ],
    );
  }

  Widget reports(ListeningReport report) {
    final groups = <String, int>{};
    for (final row in report.days.entries) {
      final date = DateTime.parse(row.key);
      final key = switch (reportGroup) {
        'year' => row.key.substring(0, 4),
        'month' => row.key.substring(0, 7),
        _ => DateTime(
          date.year,
          date.month,
          date.day - date.weekday + 1,
        ).toIso8601String().substring(0, 10),
      };
      groups.update(key, (v) => v + row.value, ifAbsent: () => row.value);
    }
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title(t('Listening reports', 'Relatórios de escuta')),
          Text(
            t(
              'Grouped within the selected period; calendar periods may be partial.',
              'Agrupados dentro do intervalo escolhido; períodos do calendário podem estar parciais.',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: reportGroup,
            items: [
              DropdownMenuItem(
                value: 'week',
                child: Text(t('Weekly', 'Semanal')),
              ),
              DropdownMenuItem(
                value: 'month',
                child: Text(t('Monthly', 'Mensal')),
              ),
              DropdownMenuItem(
                value: 'year',
                child: Text(t('Yearly', 'Anual')),
              ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => reportGroup = v);
            },
          ),
          const SizedBox(height: 12),
          for (final date in dates.take(100))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(date),
              trailing: Text('${groups[date]} scrobbles'),
            ),
          if (dates.length > 100)
            Text(
              t(
                'Showing 100 groups. Export CSV for all data.',
                'Exibindo 100 grupos. Exporte CSV para todos os dados.',
              ),
            ),
        ],
      ),
    );
  }

  Widget overview(ListeningReport report) {
    final top = report.artists.firstOrNull;
    final index = libraryIndex;
    final artistTracks = <Track>[
      if (index != null && top != null && matches != null)
        for (final id
            in (index.artists[searchKey(top.title)] ?? <String>[]).toSet())
          if (index.byId[id] != null) index.byId[id]!,
    ];
    final artist = card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title(t('Your top artist', 'Seu artista mais ouvido')),
          const SizedBox(height: 16),
          SizedBox.square(
            key: const ValueKey('insights.top-artist-image'),
            dimension: 64,
            child: ArtistPortrait(
              artist: top?.title ?? '',
              fallbackTrack: artistTracks.firstOrNull,
              enabled: widget.settings.visualBool('artist_photos'),
              cachedOnly: offline,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            top?.title ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text('${top?.count ?? 0} scrobbles'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: artistTracks.isEmpty || top == null
                ? null
                : () => widget.onOpen(
                    'artists',
                    CatalogGroup(
                      'insights:artist:${top.title}',
                      top.title,
                      artistTracks,
                    ),
                  ),
            child: Text(t('View artist', 'Ver artista')),
          ),
        ],
      ),
    );
    final trackRanks = card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              title(t('Top tracks', 'Faixas mais ouvidas')),
              TextButton(
                onPressed: matches == null ? null : playlist,
                child: Text(t('Create playlist', 'Criar playlist')),
              ),
            ],
          ),
          ranking('tracks', report.tracks, take: 5),
        ],
      ),
    );
    final artistRanks = card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title(t('Top artists', 'Artistas mais ouvidos')),
          ranking('artists', report.artists, take: 5),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, size) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (size.maxWidth >= 1000)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: card(activity(report))),
                const SizedBox(width: 16),
                Expanded(child: artist),
              ],
            )
          else ...[
            card(activity(report)),
            const SizedBox(height: 16),
            artist,
          ],
          const SizedBox(height: 16),
          if (report.complete &&
              report.invalid == 0 &&
              report.previousFrom != report.from)
            Text(
              '${t('Previous period of equal duration', 'Período anterior de mesma duração')}: ${report.previousScrobbles} scrobbles${report.previousScrobbles == 0 ? '' : ' · ${((report.scrobbles - report.previousScrobbles) * 100 / report.previousScrobbles).toStringAsFixed(1)}%'}',
            ),
          const SizedBox(height: 16),
          if (size.maxWidth >= 900)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: trackRanks),
                const SizedBox(width: 16),
                Expanded(child: artistRanks),
              ],
            )
          else ...[
            trackRanks,
            const SizedBox(height: 16),
            artistRanks,
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = data;
    final complete = report != null && report.complete && report.invalid == 0;
    return SingleChildScrollView(
      key: const PageStorageKey('listening.insights.scroll'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('Listening Insights', 'Estatísticas de escuta'),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    t(
                      'Your listening story, powered by Last.fm',
                      'Sua história de escuta, com dados do Last.fm',
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: report == null || exporting ? null : export,
                    icon: const MtIcon(Icons.file_download),
                    label: Text(t('Export CSV', 'Exportar CSV')),
                  ),
                  FilledButton.icon(
                    onPressed:
                        report == null || openingPlaylist || matches == null
                        ? null
                        : playlist,
                    icon: const MtIcon(Icons.add),
                    label: Text(t('Create playlist', 'Criar playlist')),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                label: Text(
                  profile.isEmpty
                      ? t('Configure Last.fm', 'Configurar Last.fm')
                      : 'Last.fm · $profile',
                ),
                onPressed: widget.onConfigure,
              ),
              if (report != null)
                Text(
                  '${t('Updated', 'Atualizado')}: ${report.updatedAt.toLocal().toString().substring(0, 16)}',
                ),
              if (offline)
                Text(t('Offline · saved data', 'Offline · dados salvos')),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, size) => Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final entry in {
                  'overview': t('Overview', 'Visão geral'),
                  'artists': t('Artists', 'Artistas'),
                  'albums': t('Albums', 'Álbuns'),
                  'tracks': t('Tracks', 'Faixas'),
                  'reports': t('Reports', 'Relatórios'),
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: tab == entry.key,
                    onSelected: (_) => setState(() {
                      tab = entry.key;
                      offset = 0;
                    }),
                  ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey('insights.period.$period.$periodSelection'),
                    initialValue: period,
                    items: [
                      for (final entry in {
                        '7': t('Last 7 days', 'Últimos 7 dias'),
                        '30': t('Last 30 days', 'Últimos 30 dias'),
                        '90': t('Last 90 days', 'Últimos 90 dias'),
                        '180': t('Last 180 days', 'Últimos 180 dias'),
                        '365': t('Last 365 days', 'Últimos 365 dias'),
                        'all': t('All time', 'Todo o período'),
                        'custom': t('Custom dates', 'Datas personalizadas'),
                      }.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: profile.isEmpty
                        ? null
                        : (v) {
                            if (v != null) choosePeriod(v);
                          },
                  ),
                ),
                IconButton(
                  tooltip: t('Refresh', 'Atualizar'),
                  onPressed: offline || profile.isEmpty || loading
                      ? null
                      : () => load(refresh: true),
                  icon: const MtIcon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    totalPages == 0
                        ? t('Reading Last.fm…', 'Consultando Last.fm…')
                        : '${t('Page', 'Página')} $currentPage / $totalPages',
                  ),
                ),
                TextButton(
                  onPressed: () {
                    request?.cancelled = true;
                    generation++;
                    setState(() => loading = false);
                  },
                  child: Text(t('Cancel', 'Cancelar')),
                ),
              ],
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (profile.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                t(
                  'Set your Last.fm username and API key in Integrations. Reading public listening data does not require a scrobbling session.',
                  'Informe usuário e chave Last.fm em Integrações. A leitura pública não exige uma sessão de scrobbling.',
                ),
              ),
            ),
          if (report != null) ...[
            const SizedBox(height: 16),
            Text(
              '${report.from.millisecondsSinceEpoch == 0 ? t('All time', 'Todo o período') : report.from.toLocal().toString().substring(0, 16)} — ${report.until.toLocal().toString().substring(0, 16)} · ${t('Last.fm data, separate from local history', 'Dados Last.fm, separados do histórico local')}',
            ),
            if (!complete)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${t('Partial coverage · loaded data only', 'Cobertura parcial · somente dados carregados')} ${report.invalid > 0 ? '(${report.invalid} ${t('invalid records', 'registros inválidos')})' : ''}',
                    ),
                    if (!report.complete)
                      TextButton(
                        onPressed: loading || offline
                            ? null
                            : () => load(more: true),
                        child: Text(
                          t('Load more history', 'Carregar mais histórico'),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, size) {
                final cols = size.maxWidth >= 800
                    ? 4
                    : size.maxWidth >= 430
                    ? 2
                    : 1;
                final values = [
                  (
                    t(
                      complete ? 'Scrobbles' : 'Loaded scrobbles',
                      complete ? 'Scrobbles' : 'Scrobbles carregados',
                    ),
                    report.scrobbles,
                  ),
                  (
                    t('Identified artists', 'Artistas identificados'),
                    report.artists.length,
                  ),
                  (
                    t('Identified albums', 'Álbuns identificados'),
                    report.albums.length,
                  ),
                  (
                    t('Identified tracks', 'Faixas identificadas'),
                    report.tracks.length,
                  ),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final value in values)
                      SizedBox(
                        width: (size.maxWidth - (cols - 1) * 12) / cols,
                        child: card(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(value.$1),
                              const SizedBox(height: 8),
                              Text(
                                '${value.$2}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            if (tab == 'overview')
              overview(report)
            else if (tab == 'reports')
              reports(report)
            else
              card(
                ranking(tab, switch (tab) {
                  'artists' => report.artists,
                  'albums' => report.albums,
                  _ => report.tracks,
                }),
              ),
          ],
        ],
      ),
    );
  }
}
