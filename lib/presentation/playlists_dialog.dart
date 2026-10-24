import 'design_icon.dart';
import 'media_details_table.dart';
import 'compact_media_card.dart';
import 'media_card_size.dart';
import 'media_indicators.dart';
import 'item_action_region.dart';
import 'view_style_selector.dart';
import 'ui_language.dart';
import '../library/m3u8.dart';
import '../library/catalog.dart';
import 'playlist_batch_summary.dart';
import 'playlist_pending_items.dart';
import '../library/playlist_batch_import.dart';
import 'now_playing_artwork.dart';

import 'package:flutter/foundation.dart';

import 'dart:convert';
import 'dart:ui' as image_ui;

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../persistence/library_store.dart';
import '../settings/app_settings.dart';
import '../library/artwork.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({
    super.key,
    required this.store,
    required this.tracks,
    required this.onPlay,
    this.onPlayNamed,
    this.onOffline,
    this.onShuffle,
    this.onQueue,
    this.trackActions,
    this.initialPlaylist,
    this.query = '',
    this.settings,
    this.onChanged,
  });
  final Future<void> Function(List<Track>, int, String)? onPlayNamed;
  final Widget Function(Track)? trackActions;
  final int? initialPlaylist;
  final String query;
  final AppSettings? settings;
  final VoidCallback? onChanged;
  final LibraryStore store;
  final List<Track> tracks;
  final void Function(List<Track>, int) onPlay;
  final void Function(String, List<Track>)? onOffline;
  final void Function(List<Track>)? onShuffle, onQueue;
  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  List<Map<String, Object?>> playlists = [], entries = [];
  int? selected;
  bool busy = false;
  List<Track> playlistQueue = [];
  String? error;
  String view = 'compact', sort = 'name';
  bool descending = false, controlsExpanded = false;
  int coverRevision = 0;
  int loadGeneration = 0;
  bool loading = true;
  String? importProgress, importingName;
  String importingPhase = 'Reading file';
  int importingFound = 0, importingPending = 0;
  List<Map<String, Object?>> occurrences = [];
  @override
  void initState() {
    super.initState();
    selected = widget.initialPlaylist;
    view =
        widget.settings?.visualChoice('playlists_view', 'compact') ?? 'compact';
    sort = widget.settings?.visualChoice('playlists_sort', 'name') ?? 'name';
    descending =
        widget.settings?.visualBool('playlists_descending', fallback: false) ??
        false;
    refresh();
  }

  @override
  void didUpdateWidget(covariant PlaylistsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPlaylist != widget.initialPlaylist) {
      selected = widget.initialPlaylist;
      refresh();
    }
  }

  Future<void> refresh() async {
    if (!mounted) return;
    final generation = ++loadGeneration;
    final playlistId = selected;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final lists = await widget.store.playlists();
      final exists = lists.any((p) => p['id'] == playlistId);
      final rows = playlistId == null || !exists
          ? <Map<String, Object?>>[]
          : await widget.store.playlistEntries(playlistId);
      final allEntries = playlistId == null || !exists
          ? <Map<String, Object?>>[]
          : await widget.store.playlistOccurrences(playlistId);
      final decoded = rows.length > 1000
          ? await compute(decodeCatalogRows, rows)
          : decodeCatalogRows(rows);
      if (mounted && generation == loadGeneration) {
        setState(() {
          if (playlistId != null && !exists) selected = null;
          playlists = lists;
          entries = rows;
          occurrences = allEntries;
          playlistQueue = decoded;
        });
      }
    } catch (_) {
      if (mounted && generation == loadGeneration) {
        setState(() => error = 'Não foi possível carregar playlists.');
      }
    } finally {
      if (mounted && generation == loadGeneration) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      widget.onChanged?.call();
      await refresh();
    } on FormatException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível salvar a alteração.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> name(String title, [String initial = '']) =>
      showDialog<String>(
        context: context,
        builder: (_) => _PlaylistNameDialog(title: title, initial: initial),
      );

  Future<void> create() async {
    final value = await name('Criar playlist');
    if (value != null && mounted) {
      await run(() async {
        selected = await widget.store.createPlaylist(value);
      });
    }
  }

  Future<void> append() async {
    final id = selected;
    if (id == null) return;
    final track = await showDialog<Track>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: const UiText('Adicionar música'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: widget.tracks.isEmpty
              ? const Center(
                  child: UiText('Adicione músicas em Configurações primeiro.'),
                )
              : ListView.builder(
                  itemCount: widget.tracks.length,
                  itemBuilder: (context, index) => ItemActionRegion(
                    child: ListTile(
                      title: Text(widget.tracks[index].title),
                      subtitle: Text(widget.tracks[index].artist),
                      onTap: () => Navigator.pop(context, widget.tracks[index]),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UiText('Cancelar'),
          ),
        ],
      ),
    );
    if (track != null && mounted) {
      await run(() => widget.store.appendToPlaylist(id, track.id));
    }
  }

  Future<void> importPlaylist() => run(_importPlaylist);
  Future<void> _importPlaylist() async {
    final files = await openFiles(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'M3U8', extensions: ['m3u8']),
      ],
    );
    if (files.isEmpty || !mounted) return;
    final catalog = await widget.store.loadTracks(
      includeCovers: false,
      includeHidden: true,
    );
    final results = await importPlaylistBatch(
      widget.store,
      files
          .map(
            (f) => PlaylistImportFile(
              f.path,
              () => compute(readPlaylistText, f.path),
            ),
          )
          .toList(),
      catalog,
      onProgress: (done, total, current) {
        if (mounted) {
          setState(() {
            importProgress = '$done / $total';
            importingName = current.name;
            importingPhase = current.phase;
            importingFound = current.found;
            importingPending = current.pending;
          });
        }
      },
    );
    if (!mounted) return;
    selected = results.where((r) => r.id != null).lastOrNull?.id ?? selected;
    setState(() {
      importProgress = null;
      importingName = null;
    });
    await showPlaylistBatchSummary(context, results);
  }

  Future<void> exportPlaylist() async {
    final id = selected;
    if (id == null) return;
    final title =
        playlists.firstWhere((row) => row['id'] == id)['name'] as String;
    final location = await getSaveLocation(
      suggestedName:
          '${path.basename(title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_'))}.m3u8',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Playlist M3U8', extensions: ['m3u8']),
      ],
    );
    if (location == null || !mounted) return;
    await run(() async {
      final catalog = await widget.store.loadTracks(
        includeCovers: false,
        includeHidden: true,
      );
      final data = exportPlaylistOccurrences(
        title,
        await widget.store.playlistOccurrences(id),
        {for (final t in catalog) t.id: t},
        location.path,
      );
      await XFile.fromData(
        utf8.encode(data),
        mimeType: 'audio/x-mpegurl',
      ).saveTo(location.path);
    });
  }

  Future<void> rename() async {
    final id = selected;
    if (id == null) return;
    final current =
        playlists.firstWhere((row) => row['id'] == id)['name'] as String;
    final value = await name('Renomear playlist', current);
    if (value != null && mounted) {
      await run(() => widget.store.renamePlaylist(id, value));
    }
  }

  Future<void> delete() async {
    final id = selected;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: const UiText('Excluir playlist?'),
        content: const UiText(
          'As músicas e os arquivos originais serão preservados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const UiText('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await run(() async {
        await widget.store.deletePlaylist(id);
        if (widget.settings?.collectionFavorites.contains('playlist:$id') ==
            true) {
          await widget.settings!.favoriteCollection('playlist:$id');
        }
        selected = null;
      });
    }
  }

  List<Track> get queue => playlistQueue;

  Future<void> chooseCover() => run(() async {
    final id = selected;
    if (id == null) return;
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'PNG / JPEG',
          extensions: ['png', 'jpg', 'jpeg'],
        ),
      ],
    );
    if (file == null) return;
    if (await file.length() > maxArtworkBytes) {
      throw const FormatException('Use uma imagem PNG ou JPEG de até 4 MB.');
    }
    final bytes = await file.readAsBytes();
    if (validatedArtwork(bytes) == null) {
      throw const FormatException('Use uma imagem PNG ou JPEG de até 4 MB.');
    }
    final codec = await image_ui.instantiateImageCodec(
      bytes,
      targetWidth: 600,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: image_ui.ImageByteFormat.png,
        );
        if (data == null) {
          throw const FormatException('Não foi possível ler a imagem.');
        }
        await widget.store.setPlaylistCover(id, data.buffer.asUint8List());
        coverRevision++;
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  });

  Widget favoriteButton(int id) => IconButton(
    key: ValueKey('playlist.favorite.$id'),
    tooltip: ui(
      context,
      widget.settings?.collectionFavorites.contains('playlist:$id') == true
          ? 'Remove playlist favorite'
          : 'Favorite playlist',
    ),
    isSelected:
        widget.settings?.collectionFavorites.contains('playlist:$id') == true,
    icon: const MtIcon(Icons.favorite_border),
    selectedIcon: const MtIcon(Icons.favorite),
    onPressed: widget.settings == null || busy
        ? null
        : () async {
            await widget.settings!.favoriteCollection('playlist:$id');
            if (mounted) setState(() {});
          },
  );
  Widget artwork(Map<String, Object?> playlist, {Track? fallback}) =>
      PlaylistArtwork(
        key: ValueKey('playlist.artwork.${playlist['id']}'),
        store: widget.store,
        id: playlist['id'] as int,
        favorite:
            widget.settings?.collectionFavorites.contains(
              'playlist:${playlist['id']}',
            ) ??
            false,
        hasCover: playlist['has_cover'] == 1,
        revision: Object.hash(coverRevision, identityHashCode(playlists)),
        empty: playlist['track_count'] == 0,
        fallback: fallback,
      );

  List<Map<String, Object?>> get sortedPlaylists {
    final values = playlists
        .where(
          (p) =>
              searchKey(p['name'] as String).contains(searchKey(widget.query)),
        )
        .toList();
    values.sort((a, b) {
      final comparison = switch (sort) {
        'count' => (a['track_count'] as int).compareTo(b['track_count'] as int),
        'added' => (a['id'] as int).compareTo(b['id'] as int),
        _ => searchKey(
          a['name'] as String,
        ).compareTo(searchKey(b['name'] as String)),
      };
      final stable = comparison == 0
          ? (a['id'] as int).compareTo(b['id'] as int)
          : comparison;
      return descending ? -stable : stable;
    });
    return values;
  }

  void openPlaylist(int id) {
    setState(() {
      selected = id;
      entries = [];
      playlistQueue = [];
    });
    refresh();
  }

  Widget playlistControls() => SingleChildScrollView(
    reverse: true,
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 170,
          child: DropdownButton<String>(
            key: const ValueKey('playlists.sort'),
            isExpanded: true,
            value: {'name', 'count', 'added'}.contains(sort) ? sort : 'name',
            items: const [
              DropdownMenuItem(value: 'name', child: UiText('Nome')),
              DropdownMenuItem(
                value: 'count',
                child: UiText('Quantidade de faixas'),
              ),
              DropdownMenuItem(value: 'added', child: UiText('Inclusão')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => sort = value);
              widget.settings?.updateVisual('playlists_sort', value);
            },
          ),
        ),
        IconButton(
          tooltip: ui(
            context,
            descending ? 'Ordem decrescente' : 'Ordem crescente',
          ),
          icon: MtIcon(descending ? Icons.arrow_downward : Icons.arrow_upward),
          onPressed: () {
            setState(() => descending = !descending);
            widget.settings?.updateVisual('playlists_descending', descending);
          },
        ),
        ViewStyleButton(
          key: const ValueKey('playlists.view'),
          value: view,
          families: {
            'list': const {
              'compact': 'Lista compacta',
              'detailed': 'Lista detalhada',
            },
            if (selected == null) ...{
              'grid': const {'grid': 'Grade'},
              'cards': const {'compact_card': 'Compact cards'},
            },
          },
          onChanged: (value) {
            setState(() => view = value);
            widget.settings?.updateVisual('playlists_view', value);
          },
        ),
      ],
    ),
  );

  Widget playlistActions(Map<String, Object?> item) => PopupMenuButton<String>(
    tooltip: ui(context, 'Ações da playlist'),
    onSelected: (value) async {
      final id = item['id'] as int;
      if (value == 'open') {
        openPlaylist(id);
        return;
      }
      if (value == 'favorite') {
        await widget.settings?.favoriteCollection('playlist:$id');
        if (mounted) setState(() {});
        return;
      }
      final rows = await widget.store.playlistEntries(id);
      final tracks = rows.map(widget.store.trackFromRow).toList();
      if (tracks.isEmpty) return;
      if (value == 'shuffle') tracks.shuffle();
      if (widget.onPlayNamed != null) {
        widget.onPlayNamed!(tracks, 0, item['name'] as String);
      } else {
        widget.onPlay(tracks, 0);
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'open', child: UiText('Open playlist')),
      const PopupMenuItem(value: 'play', child: UiText('Reproduzir')),
      const PopupMenuItem(value: 'shuffle', child: UiText('Aleatório')),
      PopupMenuItem(
        value: 'favorite',
        child: UiText(
          widget.settings?.collectionFavorites.contains(
                    'playlist:${item['id']}',
                  ) ==
                  true
              ? 'Remover favorito'
              : 'Favoritar',
        ),
      ),
    ],
  );

  Widget content() {
    if (loading && (selected != null ? entries.isEmpty : playlists.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (selected == null) {
      if (playlists.isEmpty) {
        return const Center(child: UiText('Crie sua primeira playlist.'));
      }
      final values = sortedPlaylists;
      if (values.isEmpty) {
        return const Center(
          child: UiText('Nenhuma playlist corresponde à busca.'),
        );
      }
      if (view == 'grid' || view == 'compact_card') {
        return LayoutBuilder(
          builder: (context, space) {
            final compact = view == 'compact_card';
            final preferredWidth = compact
                ? MediaCardSizeScope.horizontalWidth(context)
                : MediaCardSizeScope.cardWidth(context);
            final columns = ((space.maxWidth + 24) / (preferredWidth + 24))
                .floor()
                .clamp(1, 12);
            final width = (space.maxWidth - (columns - 1) * 24) / columns;
            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: compact
                    ? MediaCardSizeScope.horizontalHeight(context)
                    : width + 56 * MediaQuery.textScalerOf(context).scale(1),
                crossAxisSpacing: 24,
                mainAxisSpacing: compact ? 12 : 24,
              ),
              itemCount: values.length,
              itemBuilder: (context, index) {
                final item = values[index];
                final id = item['id'] as int;
                if (compact) {
                  return CompactMediaCard(
                    artwork: artwork(item),
                    title: item['name'] as String,
                    subtitle:
                        '${item['track_count']} ${ui(context, 'músicas')}',
                    actions: playlistActions(item),
                    onTap: () {
                      if (!busy) openPlaylist(id);
                    },
                  );
                }
                return ItemActionRegion(
                  child: InkWell(
                    onTap: busy ? null : () => openPlaylist(id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: Stack(
                            children: [
                              Positioned.fill(child: artwork(item)),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: playlistActions(item),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item['name'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${item['track_count']} ${ui(context, 'músicas')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if ((item['pending_count'] as int? ?? 0) > 0)
                          playlistPendingBadge(
                            context,
                            item['pending_count'] as int,
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      }
      if (view == 'detailed') {
        return MediaDetailsTable(
          columnKey: 'playlists',
          headers: [
            ui(context, 'Título'),
            ui(context, 'Músicas'),
            ui(context, 'Pendências'),
            '',
          ],
          widths: const [340, 140, 140, 128],
          itemCount: values.length,
          rowBuilder: (i) {
            final item = values[i];
            return [
              InkWell(
                onTap: busy ? null : () => openPlaylist(item['id'] as int),
                child: Row(
                  children: [
                    SizedBox.square(dimension: 36, child: artwork(item)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item['name'] as String)),
                  ],
                ),
              ),
              Text('${item['track_count']}'),
              Text('${item['pending_count'] ?? 0}'),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  favoriteButton(item['id'] as int),
                  playlistActions(item),
                ],
              ),
            ];
          },
        );
      }
      return ListView.builder(
        itemCount: values.length,
        itemBuilder: (context, index) => ItemActionRegion(
          child: ListTile(
            dense: view == 'compact',
            leading: SizedBox.square(
              dimension: view == 'detailed' ? 64 : 40,
              child: artwork(values[index]),
            ),
            minTileHeight: view == 'detailed' ? 88 : null,
            title: Text(values[index]['name'] as String),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((values[index]['pending_count'] as int? ?? 0) > 0)
                  playlistPendingBadge(
                    context,
                    values[index]['pending_count'] as int,
                  ),
                favoriteButton(values[index]['id'] as int),
                playlistActions(values[index]),
              ],
            ),
            subtitle: Text(
              '${values[index]['track_count']} ${ui(context, 'músicas')}',
            ),
            onTap: busy
                ? null
                : () {
                    openPlaylist(values[index]['id'] as int);
                  },
          ),
        ),
      );
    }
    return PlaylistPendingItems(
      store: widget.store,
      id: selected!,
      rows: occurrences,
      queue: queue,
      busy: busy,
      onChanged: run,
      onPlay: playPlaylist,
      trackActions: widget.trackActions,
    );
  }

  void playPlaylist(List<Track> values, int index) {
    if (values.isEmpty) return;
    final name =
        playlists.where((p) => p['id'] == selected).firstOrNull?['name']
            as String?;
    if (name != null && widget.onPlayNamed != null) {
      widget.onPlayNamed!(values, index, name);
    } else {
      widget.onPlay(values, index);
    }
  }

  Widget playlistHeader() => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: ui(context, 'Todas as playlists'),
            onPressed: busy
                ? null
                : () {
                    setState(() => selected = null);
                  },
            icon: const MtIcon(Icons.arrow_back),
          ),
          SizedBox.square(
            dimension: constraints.maxWidth < 650 ? 112 : 180,
            child: Tooltip(
              message: ui(context, 'Escolher capa da playlist'),
              child: InkWell(
                onTap: busy ? null : chooseCover,
                child: artwork(
                  playlists.where((p) => p['id'] == selected).firstOrNull ??
                      {'id': selected, 'has_cover': 0},
                  fallback: queue.firstOrNull,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlists
                              .where((p) => p['id'] == selected)
                              .firstOrNull?['name']
                          as String? ??
                      'Playlist',
                  style: Theme.of(context).textTheme.headlineMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${occurrences.length} ${ui(context, 'total')} - ${queue.length} ${ui(context, 'resolved')}',
                ),
                if (occurrences.length > queue.length)
                  playlistPendingBadge(
                    context,
                    occurrences.length - queue.length,
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: busy || queue.isEmpty
                          ? null
                          : () => playPlaylist(queue, 0),
                      icon: const MtIcon(Icons.play_arrow),
                      label: const UiText('Reproduzir'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy || queue.isEmpty
                          ? null
                          : () {
                              if (widget.onPlayNamed != null) {
                                playPlaylist(
                                  List<Track>.of(queue)..shuffle(),
                                  0,
                                );
                              } else if (widget.onShuffle != null) {
                                widget.onShuffle!(queue);
                              } else {
                                widget.onPlay(
                                  List<Track>.of(queue)..shuffle(),
                                  0,
                                );
                              }
                            },
                      icon: const MtIcon(Icons.shuffle),
                      label: const UiText('Aleatório'),
                    ),
                    if (widget.onQueue != null)
                      IconButton(
                        tooltip: ui(context, 'Adicionar à fila'),
                        onPressed: busy || queue.isEmpty
                            ? null
                            : () => widget.onQueue!(queue),
                        icon: const MtIcon(Icons.queue_music),
                      ),
                    if (selected != null) favoriteButton(selected!),
                    PopupMenuButton<String>(
                      key: const ValueKey('playlist.actions'),
                      tooltip: ui(context, 'Ações da playlist'),
                      enabled: !busy,
                      onSelected: (value) {
                        switch (value) {
                          case 'append':
                            append();
                          case 'offline':
                            widget.onOffline?.call('playlist:$selected', queue);
                          case 'rename':
                            rename();
                          case 'export':
                            exportPlaylist();
                          case 'delete':
                            delete();
                          case 'cover':
                            chooseCover();
                          case 'remove_cover':
                            run(() async {
                              await widget.store.setPlaylistCover(
                                selected!,
                                null,
                              );
                              coverRevision++;
                            });
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'cover',
                          child: UiText('Escolher capa da playlist'),
                        ),
                        if (playlists
                                .where((p) => p['id'] == selected)
                                .firstOrNull?['has_cover'] ==
                            1)
                          const PopupMenuItem(
                            value: 'remove_cover',
                            child: UiText('Remover capa personalizada'),
                          ),
                        const PopupMenuItem(
                          value: 'append',
                          child: UiText('Adicionar música'),
                        ),
                        if (widget.onOffline != null)
                          PopupMenuItem(
                            value: 'offline',
                            enabled: queue.isNotEmpty,
                            child: const UiText('Disponibilizar offline'),
                          ),
                        const PopupMenuItem(
                          value: 'rename',
                          child: UiText('Renomear'),
                        ),
                        const PopupMenuItem(
                          value: 'export',
                          child: UiText('Exportar playlist'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: UiText('Excluir playlist'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected != null) playlistHeader(),
        if (error != null)
          UiText(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (busy || loading) const LinearProgressIndicator(),
        if (importProgress != null)
          Text(
            '$importProgress - $importingName - ${ui(context, importingPhase)} - $importingFound ${ui(context, 'found')} / $importingPending ${ui(context, 'items not found')}',
          ),
        if (error != null)
          TextButton(
            onPressed: refresh,
            child: const UiText('Tentar novamente'),
          ),
        if (selected == null)
          LayoutBuilder(
            builder: (context, space) {
              final compact =
                  space.maxWidth <
                  760 * MediaQuery.textScalerOf(context).scale(1);
              return Row(
                key: const ValueKey('playlists.heading'),
                children: [
                  Expanded(
                    child: UiText(
                      'Playlists',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (compact) ...[
                    IconButton.filledTonal(
                      tooltip: ui(context, 'Criar playlist'),
                      onPressed: busy ? null : create,
                      icon: const MtIcon(Icons.add),
                    ),
                    IconButton(
                      tooltip: ui(context, 'Importar playlist'),
                      onPressed: busy ? null : importPlaylist,
                      icon: const MtIcon(Icons.file_open),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed: busy ? null : create,
                      icon: const MtIcon(Icons.add),
                      label: const UiText('Criar playlist'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: busy ? null : importPlaylist,
                      icon: const MtIcon(Icons.file_open),
                      label: const UiText('Importar playlist'),
                    ),
                  ],
                  if (controlsExpanded)
                    Flexible(
                      flex: 3,
                      fit: FlexFit.tight,
                      child: playlistControls(),
                    ),
                  IconButton.filledTonal(
                    key: const ValueKey('playlists.controls.toggle'),
                    tooltip: ui(context, 'Visualização e ordenação'),
                    onPressed: () =>
                        setState(() => controlsExpanded = !controlsExpanded),
                    icon: MtIcon(
                      controlsExpanded ? Icons.chevron_right : Icons.tune,
                    ),
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: 12),
        Expanded(child: content()),
      ],
    ),
  );
}

class PlaylistArtwork extends StatefulWidget {
  const PlaylistArtwork({
    super.key,
    required this.store,
    required this.id,
    required this.hasCover,
    required this.revision,
    this.empty = false,
    this.favorite = false,
    this.fallback,
  });
  final LibraryStore store;
  final int id, revision;
  final bool hasCover;
  final bool empty;
  final bool favorite;
  final Track? fallback;
  @override
  State<PlaylistArtwork> createState() => PlaylistArtworkState();
}

class PlaylistArtworkState extends State<PlaylistArtwork> {
  late Future<Uint8List?> cover;
  late Future<List<Track>> collage;
  void load() {
    cover = widget.hasCover
        ? widget.store.playlistCover(widget.id)
        : Future.value();
    collage = widget.hasCover || widget.empty
        ? Future.value(<Track>[])
        : widget.store.playlistArtworkTracks(widget.id);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant PlaylistArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.hasCover != widget.hasCover ||
        oldWidget.empty != widget.empty ||
        oldWidget.revision != widget.revision ||
        oldWidget.store != widget.store) {
      load();
    }
  }

  Widget fallback() => FutureBuilder<List<Track>>(
    future: collage,
    builder: (context, snapshot) {
      final tracks = snapshot.data ?? <Track>[];
      return Column(
        key: const ValueKey('playlist.collage'),
        children: [
          for (var row = 0; row < 2; row++)
            Expanded(
              child: Row(
                children: [
                  for (var col = 0; col < 2; col++)
                    Expanded(
                      child: TrackCover(
                        key: ValueKey('playlist.tile.${row * 2 + col}'),
                        indicators: false,
                        track: row * 2 + col < tracks.length
                            ? tracks[row * 2 + col]
                            : null,
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) => MediaBadges(
    favorite: widget.favorite,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FutureBuilder<Uint8List?>(
        future: cover,
        builder: (context, snapshot) => snapshot.data == null
            ? fallback()
            : Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => fallback(),
              ),
      ),
    ),
  );
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController input;
  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    title: Text(widget.title),
    content: TextField(
      controller: input,
      autofocus: true,
      maxLength: 120,
      decoration: InputDecoration(labelText: ui(context, 'Nome da playlist')),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const UiText('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (input.text.trim().isNotEmpty) {
            Navigator.pop(context, input.text.trim());
          }
        },
        child: const UiText('Salvar'),
      ),
    ],
  );
}
