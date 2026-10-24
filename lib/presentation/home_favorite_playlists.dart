import 'design_icon.dart';
import 'media_details_table.dart';

import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../persistence/library_store.dart';
import '../settings/app_settings.dart';
import 'compact_media_card.dart';
import 'home_page.dart'
    show
        HomeCardLayout,
        HomeCarouselState,
        homeCarouselButtons,
        homeCompactItem,
        homeListMode;
import 'playlists_dialog.dart' show PlaylistArtwork;
import 'ui_language.dart';

class HomeFavoritePlaylists extends StatefulWidget {
  const HomeFavoritePlaylists({
    super.key,
    required this.settings,
    required this.store,
    required this.playlists,
    required this.tracks,
    required this.mode,
    required this.onOpen,
    required this.onPlay,
    this.onPlayNamed,
    required this.onAction,
  });
  final Future<void> Function(List<Track>, int, String)? onPlayNamed;
  final AppSettings settings;
  final LibraryStore? store;
  final List<Map<String, Object?>> playlists;
  final List<Track> tracks;
  final String mode;
  final void Function(int)? onOpen;
  final Future<void> Function(List<Track>, int) onPlay;
  final Future<void> Function(String, List<Track>) onAction;
  @override
  State<HomeFavoritePlaylists> createState() => _HomeFavoritePlaylistsState();
}

class _HomeFavoritePlaylistsState extends State<HomeFavoritePlaylists> {
  final carouselKey = GlobalKey<HomeCarouselState>();
  late Future<List<({Map<String, Object?> row, List<Track> tracks})>> pending;
  String signature = '';
  void load() {
    final favorites = widget.settings.collectionFavorites.toList()..sort();
    final next =
        '${identityHashCode(widget.tracks)}:${identityHashCode(widget.playlists)}:${favorites.join('|')}:${widget.settings.visualNumber('home_count_favorite_playlists', 12)}';
    if (next == signature) return;
    signature = next;
    final rows = widget.playlists
        .where((p) => favorites.contains('playlist:${p['id']}'))
        .take(
          widget.settings
              .visualNumber('home_count_favorite_playlists', 12)
              .round(),
        )
        .toList();
    final byId = {for (final t in widget.tracks) t.id: t};
    final store = widget.store;
    pending = Future.wait(
      rows.map((row) async {
        final ids =
            await store?.playlistTrackIds(row['id'] as int) ?? <String>[];
        return (
          row: row,
          tracks: [
            for (final id in ids)
              if (byId.containsKey(id)) byId[id]!,
          ],
        );
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant HomeFavoritePlaylists old) {
    super.didUpdateWidget(old);
    load();
  }

  Widget actions(int id, List<Track> tracks) => PopupMenuButton<String>(
    tooltip: ui(context, 'Ações da playlist'),
    onSelected: (value) async {
      if (value == 'favorite') {
        await widget.settings.favoriteCollection('playlist:$id');
      } else if (value == 'open') {
        widget.onOpen?.call(id);
      } else if (tracks.isNotEmpty) {
        if (value == 'play') {
          final title =
              widget.playlists.where((p) => p['id'] == id).firstOrNull?['name']
                  as String?;
          if (widget.onPlayNamed != null && title != null) {
            await widget.onPlayNamed!(tracks, 0, title);
          } else {
            await widget.onPlay(tracks, 0);
          }
        } else {
          await widget.onAction(value, tracks);
        }
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'open',
        enabled: widget.onOpen != null,
        child: const UiText('Open playlist'),
      ),
      PopupMenuItem(
        value: 'play',
        enabled: tracks.isNotEmpty,
        child: const UiText('Reproduzir'),
      ),
      PopupMenuItem(
        value: 'queue',
        enabled: tracks.isNotEmpty,
        child: const UiText('Adicionar à fila'),
      ),
      const PopupMenuItem(
        value: 'favorite',
        child: UiText('Remove playlist favorite'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('home.section.favorite_playlists'),
    padding: EdgeInsets.only(
      top: widget.settings
          .visualNumber('home_section_spacing', 24)
          .clamp(0, 96)
          .toDouble(),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: UiText(
                'Playlists favoritas',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (widget.mode.startsWith('carousel'))
              ...homeCarouselButtons(context, carouselKey),
          ],
        ),
        const SizedBox(height: 24),
        FutureBuilder(
          future: pending,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(() {
                  signature = '';
                  load();
                }),
                child: const UiText('Tentar novamente'),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final rows = snapshot.data!;
            if (rows.isEmpty) {
              return const UiText(
                'Favorite playlists in Playlists to show them here.',
              );
            }
            if (widget.mode == 'detailed') {
              return MediaDetailsTable(
                columnKey: 'home_favorite_playlists',
                headers: [ui(context, 'Título'), ui(context, 'Músicas'), ''],
                widths: const [340, 140, 80],
                itemCount: rows.length,
                rowBuilder: (i) {
                  final item = rows[i], id = rows[i].row['id'] as int;
                  return [
                    InkWell(
                      onTap: () => widget.onOpen?.call(id),
                      child: Text(item.row['name'] as String),
                    ),
                    Text('${item.tracks.length}'),
                    actions(id, item.tracks),
                  ];
                },
              );
            }
            final items = rows.map((item) {
              final id = item.row['id'] as int;
              final title = item.row['name'] as String;
              final subtitle =
                  '${item.tracks.length} ${ui(context, 'available tracks')}';
              final artwork = widget.store == null
                  ? const MtIcon(Icons.playlist_play)
                  : PlaylistArtwork(
                      store: widget.store!,
                      id: id,
                      favorite: true,
                      hasCover: item.row['has_cover'] == 1,
                      empty: item.row['track_count'] == 0,
                      revision: identityHashCode(widget.playlists),
                      fallback: item.tracks.firstOrNull,
                    );
              void open() => widget.onOpen?.call(id);
              if (homeCompactItem(widget.mode) || widget.mode == 'detailed') {
                return CompactMediaCard(
                  artwork: artwork,
                  title: title,
                  subtitle: subtitle,
                  actions: actions(id, item.tracks),
                  onTap: open,
                );
              }
              if (homeListMode(widget.mode)) {
                return ListTile(
                  dense: true,
                  leading: SizedBox.square(dimension: 44, child: artwork),
                  title: Text(title),
                  subtitle: Text(subtitle),
                  trailing: actions(id, item.tracks),
                  onTap: open,
                );
              }
              return InkWell(
                onTap: open,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        children: [
                          Positioned.fill(child: artwork),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: actions(id, item.tracks),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }).toList();
            return HomeCardLayout(
              carouselKey: carouselKey,
              mode: widget.mode,
              covers: true,
              children: items,
            );
          },
        ),
      ],
    ),
  );
}
