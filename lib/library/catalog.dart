import 'dart:math';
import 'dart:convert';

import 'package:path/path.dart' as path;

import '../domain/track.dart';
import 'local_metadata.dart';

final _accentCharacters = RegExp('[áàâãäåéèêëíìîïóòôõöúùûüçñ]');
String searchKey(String value) {
  const from = 'áàâãäåéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaaeeeeiiiiooooouuuucn';
  return value.toLowerCase().replaceAllMapped(
    _accentCharacters,
    (match) => to[from.indexOf(match[0]!)],
  );
}

typedef CatalogWork = ({
  CatalogIndex index,
  CatalogFilters filters,
  String text,
  String sort,
  bool descending,
  String category,
});
typedef CatalogResult = ({List<Track> tracks, List<CatalogGroup> groups});
CatalogResult prepareCatalog(CatalogWork work) {
  final tracks = work.index.query(
    work.filters,
    text: work.text,
    sort: work.sort,
    descending: work.descending,
  );
  return (
    tracks: tracks,
    groups:
        {
          'albums',
          'artists',
          'albumArtists',
          'genres',
          'years',
          'decades',
        }.contains(work.category)
        ? work.index.sortGroups(
            work.index.groups(work.category, tracks),
            work.sort,
            work.descending,
          )
        : <CatalogGroup>[],
  );
}

String artistNameKey(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

int? albumReleaseYear(CatalogGroup album) {
  final years = album.tracks
      .map((t) => t.year)
      .whereType<int>()
      .where((y) => y > 0);
  return years.isEmpty ? null : years.reduce(min);
}

List<CatalogGroup> chronologicalAlbums(List<CatalogGroup> albums) {
  final position = {for (var i = 0; i < albums.length; i++) albums[i].id: i};
  return List.of(albums)..sort((a, b) {
    final x = albumReleaseYear(a), y = albumReleaseYear(b);
    if (x == null && y != null) return 1;
    if (y == null && x != null) return -1;
    final year = (x ?? 0).compareTo(y ?? 0);
    return year != 0 ? year : position[a.id]!.compareTo(position[b.id]!);
  });
}

String trackFormat(Track t) => t.format.isNotEmpty
    ? t.format
    : path
          .extension(t.localPath ?? t.title)
          .replaceFirst('.', '')
          .toUpperCase();
String trackFolder(Track t) => t.localPath != null
    ? path.dirname(t.localPath!)
    : t.sourcePath.isEmpty
    ? 'Pasta não informada'
    : t.sourcePath;

class CatalogFilters {
  String source = '',
      account = '',
      folder = '',
      artist = '',
      album = '',
      genre = '',
      year = '',
      format = '',
      heard = 'all';
  bool favorites = false, offline = false;
  Map<String, Object> toJson() => {
    'source': source,
    'account': account,
    'folder': folder,
    'artist': artist,
    'album': album,
    'genre': genre,
    'year': year,
    'format': format,
    'heard': heard,
    'favorites': favorites,
    'offline': offline,
  };
  CatalogFilters();
  CatalogFilters.fromJson(Map<String, dynamic> values) {
    source = values['source'] as String? ?? '';
    account = values['account'] as String? ?? '';
    folder = values['folder'] as String? ?? '';
    artist = values['artist'] as String? ?? '';
    album = values['album'] as String? ?? '';
    genre = values['genre'] as String? ?? '';
    year = values['year'] as String? ?? '';
    format = values['format'] as String? ?? '';
    heard = values['heard'] as String? ?? 'all';
    favorites = values['favorites'] == true;
    offline = values['offline'] == true;
  }
  bool get active =>
      source.isNotEmpty ||
      account.isNotEmpty ||
      folder.isNotEmpty ||
      artist.isNotEmpty ||
      album.isNotEmpty ||
      genre.isNotEmpty ||
      year.isNotEmpty ||
      format.isNotEmpty ||
      heard != 'all' ||
      favorites ||
      offline;
}

class CatalogGroup {
  CatalogGroup(this.id, this.name, this.tracks);
  final String id, name;
  final List<Track> tracks;
  Duration get duration =>
      tracks.fold(Duration.zero, (value, track) => value + track.duration);
}

class CatalogIndex {
  CatalogIndex({
    required this.tracks,
    required this.favorites,
    required this.offline,
    required this.stats,
    required this.sources,
    this.collectionFavorites = const {},
    this.mergeArtists = false,
    this.mergeAlbums = false,
  });
  final List<Track> tracks;
  final Set<String> favorites, offline, collectionFavorites;
  final Map<String, Map<String, Object?>> stats;
  final Map<String, List<Map<String, Object?>>> sources;
  final bool mergeArtists, mergeAlbums;
  String artistIdentity(String value) => mergeArtists
      ? value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase()
      : value;
  int plays(Track track) => stats[track.id]?['play_count'] as int? ?? 0;
  DateTime? lastPlayed(Track track) =>
      DateTime.tryParse(stats[track.id]?['last_played'] as String? ?? '');
  List<String> sourceIds(Track t) => t.provider == 'local'
      ? (sources[t.id]?.map((s) => s['id'] as String).toList() ?? ['local'])
      : [t.provider, ...?sources[t.id]?.map((s) => s['id'] as String)];
  Map<String, String> get sourceOptions {
    final result = <String, String>{};
    for (final t in tracks) {
      for (final id in sourceIds(t)) {
        final source = sources[t.id]?.where((s) => s['id'] == id).firstOrNull;
        result[id] =
            source?['label'] as String? ??
            (t.provider == 'local'
                ? (source?['label'] as String? ?? 'Arquivos locais')
                : t.provider == 'onedrive'
                ? 'OneDrive'
                : t.provider);
      }
    }
    return result;
  }

  bool isFavorite(Track t) => favorites.contains(t.id);

  late final favoriteAlbumKeys = canonicalAlbumFavorites(
    tracks,
    collectionFavorites,
  );
  late final previousAlbumKeys = {
    for (final track in tracks)
      albumKey(track, combineDiscs: false): albumKey(track),
  };
  bool isAlbumFavorite(Track t) =>
      favoriteAlbumKeys.contains('album:${albumKey(t)}');
  late final sortKeys = {
    for (final t in tracks)
      t.id: (
        title: searchKey(t.title),
        artist: searchKey(t.artist),
        album: searchKey(t.album),
      ),
  };
  List<Track> query(
    CatalogFilters filters, {
    String text = '',
    String quick = '',
    String sort = 'title',
    bool descending = false,
  }) {
    final albumFilter = filters.album.isEmpty
        ? ''
        : previousAlbumKeys[filters.album] ?? filters.album;
    final queries = [
      text,
      quick,
    ].map(searchKey).where((q) => q.isNotEmpty).toList();
    final values = tracks.where((t) {
      final searchable = queries.isEmpty
          ? ''
          : searchKey(
              [
                t.title,
                t.artist,
                ...t.artistNames,
                ...t.albumArtistNames,
                t.album,
                ...t.genreNames,
                trackFolder(t),
              ].join(' '),
            );
      return queries.every(searchable.contains) &&
          (filters.source.isEmpty || sourceIds(t).contains(filters.source)) &&
          (filters.account.isEmpty || t.account == filters.account) &&
          (filters.folder.isEmpty ||
              trackFolder(t) == filters.folder ||
              trackFolder(t).startsWith(filters.folder + path.separator) ||
              trackFolder(t).startsWith('${filters.folder}/')) &&
          (!filters.favorites || favorites.contains(t.id)) &&
          (!filters.offline || offline.contains(t.id)) &&
          (filters.artist.isEmpty ||
              t.artistNames.any(
                (a) => artistNameKey(a) == artistNameKey(filters.artist),
              )) &&
          (albumFilter.isEmpty || albumKey(t) == albumFilter) &&
          (filters.genre.isEmpty || t.genreNames.contains(filters.genre)) &&
          (filters.year.isEmpty || t.year?.toString() == filters.year) &&
          (filters.format.isEmpty || trackFormat(t) == filters.format) &&
          (filters.heard == 'all' ||
              (filters.heard == 'heard' ? plays(t) > 0 : plays(t) == 0));
    }).toList();
    values.sort((a, b) {
      int result;
      switch (sort) {
        case 'track':
          result = compareAlbumTracks(a, b);
        case 'artist':
          result = sortKeys[a.id]!.artist.compareTo(sortKeys[b.id]!.artist);
        case 'album':
          result = sortKeys[a.id]!.album.compareTo(sortKeys[b.id]!.album);
        case 'duration':
          result = a.duration.compareTo(b.duration);
        case 'added':
          result = (a.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
        case 'last':
          result = (lastPlayed(a) ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                lastPlayed(b) ?? DateTime.fromMillisecondsSinceEpoch(0),
              );
        case 'plays':
          result = plays(a).compareTo(plays(b));
        default:
          result = sortKeys[a.id]!.title.compareTo(sortKeys[b.id]!.title);
      }
      if (result == 0) result = a.id.compareTo(b.id);
      return descending ? -result : result;
    });
    return values;
  }

  List<CatalogGroup> groups(String category, List<Track> values) {
    final result = <String, CatalogGroup>{};
    for (final t in values) {
      final names = switch (category) {
        'albums' => {albumKey(t): t.album.isEmpty ? 'Sem álbum' : t.album},
        'artists' => {
          for (final a in t.artistNames) artistIdentity(a): a.trim(),
        },
        'albumArtists' => {
          for (final a in t.albumArtistNames) artistIdentity(a): a.trim(),
        },
        'genres' => {for (final g in t.genreNames) g: g},
        'years' =>
          t.year == null
              ? <String, String>{'unknown': 'Ano não informado'}
              : {t.year.toString(): t.year.toString()},
        'decades' =>
          t.year == null
              ? <String, String>{'unknown': 'Década não informada'}
              : {
                  (t.year! ~/ 10 * 10).toString():
                      '${t.year! ~/ 10 * 10}–${t.year! ~/ 10 * 10 + 9}',
                },
        'folders' => {
          '${t.provider}|${t.account}|${trackFolder(t)}':
              '${t.provider == 'local' ? 'Local' : t.provider} → ${t.account} → ${trackFolder(t)}',
        },
        _ => <String, String>{},
      };
      for (final entry in names.entries) {
        result
            .putIfAbsent(
              entry.key,
              () => CatalogGroup(entry.key, entry.value, []),
            )
            .tracks
            .add(t);
      }
    }
    var groups = result.values.toList();
    if (category == 'albums' && mergeAlbums) {
      final unique = <String, CatalogGroup>{};
      for (final group in groups) {
        final first = group.tracks.first;
        final reliable =
            first.album.isNotEmpty &&
            first.artist.isNotEmpty &&
            group.tracks.every(
              (t) => t.trackNumber != null && t.duration > Duration.zero,
            );
        if (!reliable) {
          unique[group.id] = group;
          continue;
        }
        final songs = <String, Track>{};
        for (final track in group.tracks) {
          final signature = jsonEncode([
            effectiveDiscNumber(track),
            track.trackNumber,
            track.title.trim().toLowerCase(),
            track.artistNames.map(artistIdentity).toList(),
            track.duration.inMilliseconds,
            track.format,
          ]);
          final previous = songs[signature];
          if (previous == null ||
              offline.contains(track.id) && !offline.contains(previous.id)) {
            songs[signature] = track;
          }
        }
        final signatures = songs.keys.toList()..sort();
        final identity = jsonEncode([
          first.album.trim().toLowerCase(),
          first.albumArtistNames.map(artistIdentity).toList(),
          first.year,
          first.edition,
          first.albumId,
          signatures,
        ]);
        final previous = unique[identity];
        if (previous == null) {
          unique[identity] = CatalogGroup(
            group.id,
            group.name,
            songs.values.toList(),
          );
        } else if (group.tracks.any((t) => offline.contains(t.id)) &&
            !previous.tracks.any((t) => offline.contains(t.id))) {
          unique[identity] = CatalogGroup(
            previous.id,
            previous.name,
            songs.values.toList(),
          );
        }
      }
      groups = unique.values.toList();
    }
    if (category == 'albums') {
      for (final group in groups) {
        group.tracks.sort(compareAlbumTracks);
      }
    }
    return groups
      ..sort((a, b) => searchKey(a.name).compareTo(searchKey(b.name)));
  }

  List<CatalogGroup> sortGroups(
    List<CatalogGroup> groups,
    String sort,
    bool descending,
  ) {
    final keys = <String, Object>{};
    for (final g in groups) {
      keys[g.id] = switch (sort) {
        'artist' => searchKey(g.tracks.first.albumArtistNames.join('; ')),
        'album' => searchKey(g.tracks.first.album),
        'duration' => g.tracks.fold<int>(
          0,
          (sum, t) => sum + t.duration.inMilliseconds,
        ),
        'plays' => g.tracks.fold<int>(0, (sum, t) => sum + plays(t)),
        'added' => g.tracks.fold<int>(
          0,
          (latest, t) => max(latest, t.addedAt?.millisecondsSinceEpoch ?? 0),
        ),
        'last' => g.tracks.fold<int>(
          0,
          (latest, t) =>
              max(latest, lastPlayed(t)?.millisecondsSinceEpoch ?? 0),
        ),
        _ => searchKey(g.name),
      };
    }
    return List<CatalogGroup>.of(groups)..sort((a, b) {
      final x = keys[a.id]!, y = keys[b.id]!;
      var result = x is int && y is int ? x.compareTo(y) : '$x'.compareTo('$y');
      if (result == 0) result = searchKey(a.name).compareTo(searchKey(b.name));
      return descending ? -result : result;
    });
  }

  List<Track> mix(List<Track> values, int limit, Random random) {
    final buckets = <String, List<Track>>{};
    final unique = <String>{};
    for (final track in values) {
      if (unique.add(track.id)) {
        buckets.putIfAbsent(track.artistNames.first, () => []).add(track);
      }
    }
    for (final bucket in buckets.values) {
      bucket.shuffle(random);
    }
    final artists = buckets.keys.toList()..shuffle(random);
    final result = <Track>[];
    while (artists.isNotEmpty && result.length < limit) {
      for (final artist in List.of(artists)) {
        final bucket = buckets[artist]!;
        result.add(bucket.removeLast());
        if (bucket.isEmpty) artists.remove(artist);
        if (result.length >= limit) break;
      }
    }
    return result;
  }
}
