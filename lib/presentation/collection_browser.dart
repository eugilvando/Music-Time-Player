import 'media_card_size.dart';
import '../library/catalog.dart';
import 'ui_language.dart';
import 'artist_portrait.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../library/local_metadata.dart';
import '../library/file_availability.dart';
import '../settings/app_settings.dart';
import '../offline/download_manager.dart';
import 'now_playing_artwork.dart';

Set<String> validOfflineFiles(List<Map<String, Object?>> candidates) {
  final result = <String>{};
  for (final row in candidates) {
    try {
      final file = File(row['path'] as String);
      final expected = row['bytes'] as int?;
      if (fileHasLocalData(file) &&
          FileSystemEntity.typeSync(file.path, followLinks: false) ==
              FileSystemEntityType.file &&
          file.existsSync() &&
          file.lengthSync() > 0 &&
          (expected == null || expected == file.lengthSync())) {
        result.add(row['id'] as String);
      }
    } catch (_) {}
  }
  return result;
}

class CollectionBrowser extends StatefulWidget {
  const CollectionBrowser({
    super.key,
    required this.albums,
    required this.tracks,
    required this.query,
    required this.settings,
    required this.downloads,
    required this.onPlay,
    required this.onQueue,
    required this.onOffline,
    required this.onTrackDetails,
    this.trackActions,
    this.onShuffle,
  });
  final Widget Function(Track)? trackActions;
  final Future<void> Function(List<Track>)? onShuffle;
  final bool albums;
  final List<Track> tracks;
  final String query;
  final AppSettings settings;
  final DownloadManager downloads;
  final void Function(List<Track>, int) onPlay;
  final void Function(List<Track>) onQueue;
  final void Function(String, List<Track>) onOffline;
  final void Function(Track) onTrackDetails;
  @override
  State<CollectionBrowser> createState() => _CollectionBrowserState();
}

class _CollectionBrowserState extends State<CollectionBrowser> {
  Set<String> offline = {};
  Map<List<Track>, String> groupKeys = {}, groupTitles = {};
  String filter = 'all';
  String? selected;
  Timer? offlineTimer;
  int request = 0;
  @override
  void initState() {
    super.initState();
    widget.downloads.addListener(scheduleOffline);
    widget.downloads.cache?.addListener(scheduleOffline);
    refreshOffline();
  }

  @override
  void didUpdateWidget(covariant CollectionBrowser old) {
    super.didUpdateWidget(old);
    if (old.albums != widget.albums) {
      selected = null;
      filter = 'all';
      refreshOffline();
    }
    if (old.tracks.length != widget.tracks.length) refreshOffline();
  }

  void scheduleOffline() {
    offlineTimer?.cancel();
    offlineTimer = Timer(const Duration(milliseconds: 300), refreshOffline);
  }

  Future<void> refreshOffline() async {
    final version = ++request;
    final candidates = <Map<String, Object?>>[];
    for (final track in widget.tracks) {
      if (track.localPath != null) {
        candidates.add({'id': track.id, 'path': track.localPath});
      }
    }
    final rows = await widget.downloads.store.downloadTasks(
      includeCovers: false,
    );
    for (final row in rows) {
      if (row['status'] == 'complete' &&
          row['download_path'] is String &&
          (row['received'] as int) > 0) {
        candidates.add({
          'id': row['id'],
          'path': row['download_path'],
          'bytes': row['received'],
        });
      }
    }
    for (final row
        in await widget.downloads.cache?.rows(validOnly: true) ??
            <Map<String, Object?>>[]) {
      candidates.add({
        'id': row['track_id'],
        'path': row['path'],
        'bytes': row['bytes'],
      });
    }
    final values = await compute(validOfflineFiles, candidates);
    if (mounted && version == request) setState(() => offline = values);
  }

  @override
  void dispose() {
    request++;
    offlineTimer?.cancel();
    widget.downloads.removeListener(scheduleOffline);
    widget.downloads.cache?.removeListener(scheduleOffline);
    super.dispose();
  }

  String key(List<Track> group) => groupKeys[group]!;
  String title(List<Track> group) => groupTitles[group]!;
  bool isOffline(List<Track> group) =>
      group.isNotEmpty && group.every((track) => offline.contains(track.id));
  bool isFavorite(List<Track> group) =>
      widget.settings.collectionFavorites.contains(key(group)) ||
      (widget.albums &&
          widget.settings.collectionFavorites.contains(
            'album:${legacyAlbumKey(group.first)}',
          ));
  List<Track> ordered(List<Track> group) => List.of(group)
    ..sort((a, b) {
      final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
      final order = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      return disc != 0
          ? disc
          : order != 0
          ? order
          : a.title.compareTo(b.title);
    });
  Widget image(List<Track> group) => widget.albums
      ? TrackCover(track: group.first)
      : ArtistPortrait(
          artist: title(group),
          enabled: widget.settings.visualBool('artist_photos'),
          cachedOnly: widget.settings.visualBool(
            'offline_only',
            fallback: false,
          ),
          fallbackTrack: group.where((t) => t.hasArtwork).firstOrNull,
        );
  Widget actions(List<Track> group) => PopupMenuButton<String>(
    tooltip: ui(context, 'Ações da coleção'),
    onSelected: (value) {
      final tracks = ordered(group);
      switch (value) {
        case 'play':
          widget.onPlay(tracks, 0);
        case 'queue':
          widget.onQueue(tracks);
        case 'favorite':
          widget.settings.favoriteCollection(
            key(group),
            aliases: widget.albums
                ? [
                    'album:${legacyAlbumKey(group.first)}',
                    if (group.first.albumId.isNotEmpty)
                      'album:id:${group.first.albumId}',
                  ]
                : const [],
          );
        case 'offline':
          widget.onOffline(key(group), tracks);
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'play', child: UiText('Reproduzir')),
      const PopupMenuItem(value: 'queue', child: UiText('Adicionar à fila')),
      PopupMenuItem(
        value: 'favorite',
        child: Text(
          isFavorite(group) ? 'Remover favorito' : 'Favoritar coleção',
        ),
      ),
      const PopupMenuItem(
        value: 'offline',
        child: UiText('Disponibilizar offline'),
      ),
    ],
  );
  Widget collectionHeader(List<Track> group) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: ui(context, 'Voltar às coleções'),
            onPressed: () => setState(() => selected = null),
            icon: const Icon(Icons.arrow_back),
          ),
          SizedBox.square(
            dimension: constraints.maxWidth < 650 ? 128 : 200,
            child: image(group),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title(group),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (widget.albums)
                  Text(group.first.albumArtistNames.join('; ')),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => widget.onPlay(ordered(group), 0),
                      icon: const Icon(Icons.play_arrow),
                      label: const UiText('Reproduzir'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        if (widget.onShuffle != null) {
                          widget.onShuffle!(group);
                        } else {
                          widget.onPlay(List<Track>.of(group)..shuffle(), 0);
                        }
                      },
                      icon: const Icon(Icons.shuffle),
                      label: const UiText('Aleatório'),
                    ),
                    IconButton(
                      tooltip: ui(
                        context,
                        isFavorite(group)
                            ? 'Remover favorito da coleção'
                            : 'Favoritar coleção',
                      ),
                      icon: Icon(
                        isFavorite(group)
                            ? Icons.favorite
                            : Icons.favorite_border,
                      ),
                      onPressed: () async {
                        await widget.settings.favoriteCollection(
                          key(group),
                          aliases: widget.albums
                              ? ['album:${legacyAlbumKey(group.first)}']
                              : const [],
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                    actions(group),
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
  Widget build(BuildContext context) {
    final index = CatalogIndex(
      tracks: widget.tracks,
      favorites: const {},
      offline: offline,
      stats: const {},
      sources: const {},
      collectionFavorites: widget.settings.collectionFavorites,
      mergeArtists: widget.settings.visualBool('merge_artists', fallback: true),
      mergeAlbums: widget.settings.visualBool('merge_albums', fallback: true),
    );
    final grouped = index.groups(
      widget.albums ? 'albums' : 'artists',
      widget.tracks,
    );
    final groups = <String, List<Track>>{
      for (final group in grouped)
        (widget.albums ? 'album:' : 'artist:') + group.id: group.tracks,
    };
    groupKeys = {for (final entry in groups.entries) entry.value: entry.key};
    groupTitles = {for (final group in grouped) group.tracks: group.name};
    final current = groups[selected];
    if (current != null) {
      if (!widget.albums) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            collectionHeader(current),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: UiText('Álbuns do artista'),
            ),
            Expanded(
              child: CollectionBrowser(
                key: ValueKey(selected),
                albums: true,
                tracks: current,
                query: widget.query,
                settings: widget.settings,
                downloads: widget.downloads,
                onPlay: widget.onPlay,
                onShuffle: widget.onShuffle,
                onQueue: widget.onQueue,
                onOffline: widget.onOffline,
                onTrackDetails: widget.onTrackDetails,
                trackActions: widget.trackActions,
              ),
            ),
          ],
        );
      }
      final tracks = ordered(current);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            collectionHeader(current),
            Expanded(
              child: ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (context, index) => ListTile(
                  leading: Text(tracks[index].trackNumber?.toString() ?? '—'),
                  title: Text(tracks[index].title),
                  subtitle: Text(tracks[index].artist),
                  trailing: widget.trackActions?.call(tracks[index]),
                  onTap: () => widget.onPlay(tracks, index),
                  onLongPress: () => widget.onTrackDetails(tracks[index]),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final values = groups.values.where((group) {
      final matches = ('${title(group)} ${group.first.artist}')
          .toLowerCase()
          .contains(widget.query.toLowerCase());
      return matches &&
          (filter != 'favorites' || isFavorite(group)) &&
          (filter != 'offline' || isOffline(group));
    }).toList();
    final preference = widget.albums ? 'albums' : 'artists';
    final sort = widget.settings.visualChoice('${preference}_sort', 'name');
    values.sort((a, b) {
      if (sort == 'count') {
        final count = b.length.compareTo(a.length);
        if (count != 0) return count;
      } else if (sort == 'year') {
        final year = (b.first.year ?? 0).compareTo(a.first.year ?? 0);
        if (year != 0) return year;
      }
      final name = title(a).toLowerCase().compareTo(title(b).toLowerCase());
      return sort == 'descending' ? -name : name;
    });
    final grid = widget.settings.visualBool('${preference}_grid');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final entry in {
                  'all': 'Tudo',
                  'favorites': 'Favoritos',
                  'offline': 'Offline',
                }.entries)
                  ChoiceChip(
                    label: UiText(entry.value),
                    selected: filter == entry.key,
                    onSelected: (_) => setState(() => filter = entry.key),
                  ),
                DropdownButton<String>(
                  value: {'name', 'descending', 'count', 'year'}.contains(sort)
                      ? sort
                      : 'name',
                  items: [
                    const DropdownMenuItem(
                      value: 'name',
                      child: UiText('Nome A–Z'),
                    ),
                    const DropdownMenuItem(
                      value: 'descending',
                      child: UiText('Nome Z–A'),
                    ),
                    DropdownMenuItem(
                      value: widget.albums ? 'year' : 'count',
                      child: Text(
                        widget.albums ? 'Ano mais recente' : 'Mais músicas',
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.settings.updateVisual('${preference}_sort', value);
                    }
                  },
                ),
                IconButton(
                  tooltip: grid ? 'Exibir lista' : 'Exibir grade',
                  onPressed: () =>
                      widget.settings.updateVisual('${preference}_grid', !grid),
                  icon: Icon(grid ? Icons.view_list : Icons.grid_view),
                ),
                IconButton(
                  tooltip: ui(context, 'Verificar arquivos offline'),
                  onPressed: refreshOffline,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: values.isEmpty
                ? const Center(
                    child: UiText(
                      'Nenhuma coleção encontrada. Adicione músicas em Configurações ou ajuste os filtros.',
                    ),
                  )
                : grid
                ? GridView.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent:
                          (widget.albums ? 210 : 200) *
                          MediaCardSizeScope.scale(context),
                      mainAxisExtent:
                          (widget.albums ? 252 : 242) *
                          MediaCardSizeScope.scale(context).clamp(1, 1.7),
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                    ),
                    itemCount: values.length,
                    itemBuilder: (context, index) {
                      final group = values[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => selected = key(group)),
                        child: Column(
                          crossAxisAlignment: widget.albums
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(child: image(group)),
                                  if (isOffline(group))
                                    const Positioned(
                                      bottom: 8,
                                      right: 8,
                                      child: Icon(
                                        Icons.offline_pin,
                                        color: Color(0xff54cf9b),
                                        size: 22,
                                      ),
                                    ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: actions(group),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              title(group),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              widget.albums
                                  ? (group.first.albumArtist.isEmpty
                                        ? group.first.artist
                                        : group.first.albumArtist)
                                  : '${group.length} ${ui(context, 'músicas')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : ListView.builder(
                    itemCount: values.length,
                    itemBuilder: (context, index) {
                      final group = values[index];
                      return ListTile(
                        leading: SizedBox.square(
                          dimension: 52,
                          child: image(group),
                        ),
                        title: Text(title(group)),
                        subtitle: Text(
                          '${group.length} ${ui(context, 'músicas')}',
                        ),
                        trailing: actions(group),
                        onTap: () => setState(() => selected = key(group)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
