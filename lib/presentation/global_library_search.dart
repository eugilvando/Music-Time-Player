import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../library/catalog.dart';
import '../persistence/library_store.dart';
import 'now_playing_artwork.dart';
import 'artist_portrait.dart';
import 'ui_language.dart';

typedef SearchWork = ({List<Track> tracks, String query});

class GlobalSearchData {
  const GlobalSearchData(this.tracks, this.albums, this.artists);
  final List<Track> tracks;
  final List<CatalogGroup> albums, artists;
}

GlobalSearchData searchLibrary(SearchWork work) {
  final query = searchKey(work.query.trim());
  final index = CatalogIndex(
    tracks: work.tracks,
    favorites: {},
    offline: {},
    stats: {},
    sources: {},
  );
  bool matches(String value) => searchKey(value).contains(query);
  final artists = <String, CatalogGroup>{};
  for (final group in [
    ...index.groups('artists', work.tracks),
    ...index.groups('albumArtists', work.tracks),
  ]) {
    if (!matches(group.name)) continue;
    final key = artistNameKey(group.name);
    final previous = artists[key];
    artists[key] = CatalogGroup(
      group.id,
      group.name,
      {
        for (final track in [...?previous?.tracks, ...group.tracks])
          track.id: track,
      }.values.toList(),
    );
  }
  return GlobalSearchData(
    work.tracks
        .where(
          (t) => matches(
            '${t.title} ${t.artistNames.join(' ')} ${t.albumArtistNames.join(' ')} ${t.album} ${t.genreNames.join(' ')} ${t.year ?? ''}',
          ),
        )
        .take(30)
        .toList(),
    index
        .groups('albums', work.tracks)
        .where(
          (g) =>
              matches('${g.name} ${g.tracks.first.albumArtistNames.join(' ')}'),
        )
        .take(20)
        .toList(),
    artists.values.take(20).toList(),
  );
}

class GlobalLibrarySearch extends StatefulWidget {
  const GlobalLibrarySearch({
    super.key,
    required this.tracks,
    required this.query,
    required this.store,
    required this.onOpen,
    required this.onPlaylist,
    this.revision = 0,
  });
  final List<Track> tracks;
  final String query;
  final LibraryStore store;
  final int revision;
  final void Function(String, CatalogGroup) onOpen;
  final void Function(int) onPlaylist;
  @override
  State<GlobalLibrarySearch> createState() => _GlobalLibrarySearchState();
}

class _GlobalLibrarySearchState extends State<GlobalLibrarySearch> {
  Timer? timer;
  int generation = 0;
  GlobalSearchData? result;
  bool failed = false;
  List<Map<String, Object?>> playlists = [];
  @override
  void initState() {
    super.initState();
    search();
  }

  @override
  void didUpdateWidget(covariant GlobalLibrarySearch old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query ||
        old.revision != widget.revision ||
        !listEquals(old.tracks, widget.tracks)) {
      search();
    }
  }

  void search() {
    timer?.cancel();
    final request = ++generation;
    failed = false;
    timer = Timer(const Duration(milliseconds: 220), () async {
      try {
        final work = (
          tracks: List<Track>.of(widget.tracks),
          query: widget.query,
        );
        final data = widget.tracks.length >= 1000
            ? await compute(searchLibrary, work)
            : searchLibrary(work);
        if (!mounted || request != generation) return;
        final rows = await widget.store.playlists();
        if (mounted && request == generation) {
          setState(() {
            result = data;
            playlists = rows
                .where(
                  (r) =>
                      searchKey(r['name'] as String)
                          .contains(searchKey(widget.query)),
                )
                .take(20)
                .toList();
          });
        }
      } catch (_) {
        if (mounted && request == generation) setState(() => failed = true);
      }
    });
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
        child: TextButton(
          onPressed: search,
          child: const UiText('Não foi possível pesquisar. Tente novamente.'),
        ),
      );
    }
    final data = result;
    if (data == null) return const Center(child: CircularProgressIndicator());
    Widget heading(String title) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: UiText(
        title,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
    Widget link(
      String title,
      String subtitle,
      Widget cover,
      VoidCallback open,
    ) => ListTile(
      leading: SizedBox.square(dimension: 44, child: cover),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward),
      onTap: open,
    );
    return ListView(
      key: const ValueKey('search.global.results'),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        heading('Resultados na biblioteca'),
        if (data.tracks.isEmpty &&
            data.albums.isEmpty &&
            data.artists.isEmpty &&
            playlists.isEmpty)
          const UiText('Nenhum resultado.'),
        if (data.artists.isNotEmpty) heading('Artistas'),
        for (final artist in data.artists)
          link(
            artist.name,
            ui(context, 'Abrir na biblioteca'),
            ArtistPortrait(artist: artist.name, enabled: false),
            () => widget.onOpen('artists', artist),
          ),
        if (data.albums.isNotEmpty) heading('Álbuns'),
        for (final album in data.albums)
          link(
            album.name,
            album.tracks.first.albumArtistNames.join('; '),
            TrackCover(track: album.tracks.first, album: true),
            () => widget.onOpen('albums', album),
          ),
        if (data.tracks.isNotEmpty) heading('Músicas'),
        for (final track in data.tracks)
          link(
            track.title,
            track.artistNames.join('; '),
            TrackCover(track: track),
            () => widget.onOpen(
              'songs',
              CatalogGroup('track:${track.id}', track.title, [track]),
            ),
          ),
        if (playlists.isNotEmpty) heading('Playlists'),
        for (final playlist in playlists)
          link(
            playlist['name'] as String,
            ui(context, 'Abrir na biblioteca'),
            const Icon(Icons.queue_music),
            () => widget.onPlaylist(playlist['id'] as int),
          ),
      ],
    );
  }
}
