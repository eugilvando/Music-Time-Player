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

HomeData prepareSelectedHome((HomeWork, Set<String>) request) =>
    prepareHome(request.$1, sections: request.$2);

HomeData prepareHome(
  HomeWork work, {
  Set<String>? sections,
  bool lightweight = false,
}) {
  bool wanted(String key) => sections == null || sections.contains(key);
  final needsMixes = !lightweight && wanted('mixes');
  final needsExplore = !lightweight && wanted('explore');
  final needsArtists =
      !lightweight &&
      (needsMixes ||
          needsExplore ||
          [
            'favorite_artists',
            'discover_artists',
            'recent_artists',
            'most_played_artists',
          ].any(wanted));
  final needsAlbums =
      !lightweight &&
      ['favorite_albums', 'discover_albums', 'recent_albums'].any(wanted);
  final index = work.index;
  final values = work.tracks
      .where(
        (t) =>
            !t.libraryHidden &&
            switch (work.quick) {
              'favorites' => index.isFavorite(t),
              'offline' => index.offline.contains(t.id),
              'recent' => t.addedAt != null,
              'unheard' => index.plays(t) == 0,
              _ => true,
            },
      )
      .toList();
  final recent =
      (wanted('recent') ? values : <Track>[])
          .where((t) => t.addedAt != null)
          .toList()
        ..sort((a, b) => b.addedAt!.compareTo(a.addedAt!));
  final history =
      (wanted('history') || wanted('again') || needsMixes ? values : <Track>[])
          .where((t) => index.lastPlayed(t) != null)
          .toList()
        ..sort((a, b) => index.lastPlayed(b)!.compareTo(index.lastPlayed(a)!));
  final popular =
      (wanted('popular') ? values : <Track>[])
          .where((t) => index.plays(t) > 0)
          .toList()
        ..sort((a, b) => index.plays(b).compareTo(index.plays(a)));
  final groups = {
    for (final type in ['genres', 'decades', 'artists'])
      type:
          ((type == 'artists' ? needsArtists : needsMixes || needsExplore)
                  ? index.groups(type, values)
                  : <CatalogGroup>[])
              .where((g) => g.id != 'unknown')
              .toList(),
  };
  final explore = <(String, CatalogGroup)>[];
  for (var i = 0; needsExplore && i < 100 && explore.length < 100; i++) {
    for (final type in groups.keys) {
      if (i < groups[type]!.length && explore.length < 100) {
        explore.add((type, groups[type]![i]));
      }
    }
  }
  final random = Random();
  final albums =
      (needsAlbums ? index.groups('albums', values) : <CatalogGroup>[])
          .where((g) => g.tracks.any((t) => t.album.isNotEmpty))
          .toList();
  final artists = groups['artists']!;
  final albumArtists =
      (!lightweight &&
                  (wanted('favorite_album_artists') ||
                      wanted('favorite_artists'))
              ? index.groups('albumArtists', values)
              : <CatalogGroup>[])
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
    'favorite_artists': wanted('favorite_artists')
        ? artists.where(artistFavorite).toList()
        : <CatalogGroup>[],
    'favorite_album_artists':
        (wanted('favorite_album_artists') || wanted('favorite_artists'))
        ? albumArtists.where(artistFavorite).toList()
        : <CatalogGroup>[],
    'discover_albums': albums.where(unheard).toList()..shuffle(random),
    'discover_artists': artists.where(unheard).toList()..shuffle(random),
    'recent_artists': wanted('recent_artists')
        ? recentGroups(artists)
        : <CatalogGroup>[],
    'recent_albums': wanted('recent_albums')
        ? recentGroups(albums)
        : <CatalogGroup>[],
    'most_played_artists': index.sortGroups(
      artists.where((g) => g.tracks.any((t) => index.plays(t) > 0)).toList(),
      'plays',
      true,
    ),
  };
  List<Track> mix(List<Track> tracks) => index.mix(tracks, work.limit, random);
  final suggested = needsMixes && artists.isNotEmpty
      ? suggestedMixArtists(index, values).first
      : null;
  final mixes = !needsMixes
      ? <String, List<Track>>{}
      : <String, List<Track>>{
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
          for (final g in groups['genres']!.take(4))
            'Mix · ${g.name}': mix(g.tracks),
          if (groups['decades']!.isNotEmpty) 'Mixes por década': mix(values),
          if (groups['artists']!.isNotEmpty)
            'Artist mix · $suggested': artistSelection(
              values,
              suggested!,
              count: 40,
            ),
          if (groups['artists']!.isNotEmpty) 'Artist radio · $suggested': [],
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
