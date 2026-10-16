import 'dart:math';

import '../domain/track.dart';
import 'catalog.dart';
import 'artist_selection.dart';

const homeSectionLabels = {
  'mixes': 'Made for you',
  'continue': 'Now listening',
  'favorite_playlists': 'Favorite Playlists',
  'favorite_tracks': 'Favorite Tracks',
  'favorite_albums': 'Favorite Albums',
  'favorite_artists': 'Favorite Artists',
  'discover_albums': 'Discover Albums',
  'discover_artists': 'Discover Artists',
  'recent_artists': 'Recently Added Artists',
  'recent_albums': 'Recently Added Albums',
  'most_played_artists': 'Most played artists',
  'history': 'Last Played',
};

typedef HomeWork = ({
  CatalogIndex index,
  List<Track> tracks,
  String quick,
  int limit,
  bool lastfm,
});
typedef HomeData = ({
  Map<String, List<Track>> lists,
  Map<String, List<Track>> mixes,
  List<(String, CatalogGroup)> explore,
  List<CatalogGroup> albums,
  Map<String, List<CatalogGroup>> collections,
});

HomeData prepareHome(HomeWork work) {
  final index = work.index;
  final values = work.tracks
      .where(
        (t) => switch (work.quick) {
          'favorites' => index.isFavorite(t),
          'offline' => index.offline.contains(t.id),
          'recent' => t.addedAt != null,
          'unheard' => index.plays(t) == 0,
          _ => true,
        },
      )
      .toList();
  final recent = values.where((t) => t.addedAt != null).toList()
    ..sort((a, b) => b.addedAt!.compareTo(a.addedAt!));
  final history = values.where((t) => index.lastPlayed(t) != null).toList()
    ..sort((a, b) => index.lastPlayed(b)!.compareTo(index.lastPlayed(a)!));
  final popular = values.where((t) => index.plays(t) > 0).toList()
    ..sort((a, b) => index.plays(b).compareTo(index.plays(a)));
  final groups = {
    for (final type in ['genres', 'decades', 'artists'])
      type: index.groups(type, values).where((g) => g.id != 'unknown').toList(),
  };
  final explore = <(String, CatalogGroup)>[];
  for (var i = 0; i < 100 && explore.length < 100; i++) {
    for (final type in groups.keys) {
      if (i < groups[type]!.length && explore.length < 100) {
        explore.add((type, groups[type]![i]));
      }
    }
  }
  final random = Random();
  final albums = index
      .groups('albums', values)
      .where((g) => g.tracks.any((t) => t.album.isNotEmpty))
      .toList();
  final artists = groups['artists']!;
  final albumArtists = index
      .groups('albumArtists', values)
      .where((g) => g.id != 'unknown')
      .toList();
  bool artistFavorite(CatalogGroup g) => index.collectionFavorites.any(
    (key) =>
        key.startsWith('artist:') &&
        artistNameKey(key.substring(7)) == artistNameKey(g.name),
  );
  bool unheard(CatalogGroup g) => g.tracks.every((t) => index.plays(t) == 0);
  List<CatalogGroup> recentGroups(List<CatalogGroup> groups) =>
      index.sortGroups(
        groups.where((g) => g.tracks.any((t) => t.addedAt != null)).toList(),
        'added',
        true,
      );
  final collections = <String, List<CatalogGroup>>{
    'favorite_albums': albums
        .where((g) => g.tracks.any(index.isAlbumFavorite))
        .toList(),
    'favorite_artists': artists.where(artistFavorite).toList(),
    'favorite_album_artists': albumArtists.where(artistFavorite).toList(),
    'discover_albums': albums.where(unheard).toList()..shuffle(random),
    'discover_artists': artists.where(unheard).toList()..shuffle(random),
    'recent_artists': recentGroups(artists),
    'recent_albums': recentGroups(albums),
    'most_played_artists': index.sortGroups(
      artists.where((g) => g.tracks.any((t) => index.plays(t) > 0)).toList(),
      'plays',
      true,
    ),
  };
  List<Track> mix(List<Track> tracks) => index.mix(tracks, work.limit, random);
  final mixes = <String, List<Track>>{
    if (work.lastfm) 'Last.fm · Mais ouvidas': [],
    if (work.lastfm) 'Last.fm · Último mês': [],
    'Mix de favoritos': mix(values.where(index.isFavorite).toList()),
    'Descobertas da biblioteca': mix(
      values.where((t) => index.plays(t) == 0).toList(),
    ),
    'Redescobertas': mix(history.reversed.take(work.limit * 2).toList()),
    'Mix offline': mix(
      values.where((t) => index.offline.contains(t.id)).toList(),
    ),
    'Mix pessoal': mix(values),
    for (final g in groups['genres']!.take(4)) 'Mix · ${g.name}': mix(g.tracks),
    if (groups['decades']!.isNotEmpty) 'Mixes por década': mix(values),
    if (groups['artists']!.isNotEmpty)
      'Artist mix · ${suggestedMixArtists(index, values).first}':
          artistSelection(
            values,
            suggestedMixArtists(index, values).first,
            count: 40,
          ),
    if (groups['artists']!.isNotEmpty)
      'Artist radio · ${suggestedMixArtists(index, values).first}': [],
  };
  return (
    lists: {
      'values': values,
      'recent': recent,
      'history': history,
      'popular': popular,
    },
    mixes: mixes,
    explore: explore,
    albums: collections['favorite_albums']!,
    collections: collections,
  );
}
