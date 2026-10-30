import 'dart:convert';

import '../domain/track.dart';
import 'catalog.dart';
import 'local_metadata.dart';

/// Only personal hexadecimal OneDrive identities may differ in letter case.
String cloudAccountMatch(String a, String b) =>
    "($a=$b OR (length($a)=16 AND $a NOT GLOB '*[^0-9a-fA-F]*' AND upper($a)=upper($b)))";

String catalogVisibility(String t) =>
    "COALESCE(json_extract($t.metadata,'\$.catalogExcluded'),0)=0 AND ($t.id NOT IN (SELECT track_id FROM local_source_tracks) OR $t.id IN (SELECT m.track_id FROM local_source_tracks m JOIN local_sources s ON s.id=m.source_id WHERE s.active=1 AND s.visible=1 AND m.present=1)) AND (CASE WHEN EXISTS(SELECT 1 FROM cloud_sources s WHERE ${cloudAccountMatch('s.account', "json_extract($t.metadata,'\$.driveId')")}) THEN EXISTS(SELECT 1 FROM cloud_sources s WHERE ${cloudAccountMatch('s.account', "json_extract($t.metadata,'\$.driveId')")} AND s.active=1 AND (json_extract($t.metadata,'\$.sourcePath')=s.folder OR substr(json_extract($t.metadata,'\$.sourcePath'),1,length(s.folder)+1)=s.folder||'/')) ELSE COALESCE(json_extract($t.metadata,'\$.catalogExcluded'),0)=0 END)";

class CatalogPage {
  const CatalogPage(this.tracks, this.total, this.offset);
  final List<Track> tracks;
  final int total, offset;
}

Map<String, Object?> catalogProjection(Track track) => {
  'track_id': track.id,
  'title_key': searchKey(track.title),
  'artist_key': searchKey(track.artist),
  'album_key': searchKey(track.album),
  'album_identity': albumKey(track),
  'album_previous': albumKey(track, combineDiscs: false),
  'album_legacy': legacyAlbumKey(track),
  'disc_number': effectiveDiscNumber(track),
  'track_number': metadataPosition(track.trackNumber),
  'searchable': searchKey(
    [
      track.title,
      track.artist,
      ...track.artistNames,
      ...track.albumArtistNames,
      track.album,
      ...track.genreNames,
      trackFolder(track),
    ].join(' '),
  ),
  'provider': track.provider,
  'account': track.account,
  'folder': trackFolder(track).replaceAll(r'\', '/'),
  'artists': jsonEncode(track.artistNames.map(artistNameKey).toList()),
  'genres': jsonEncode(track.genreNames),
  'year': track.year,
  'format': trackFormat(track),
  'duration_ms': track.duration.inMilliseconds,
  'added_us': track.addedAt?.microsecondsSinceEpoch ?? 0,
};

class CatalogSqlQuery {
  CatalogSqlQuery({
    required CatalogFilters filters,
    String text = '',
    String sort = 'title',
    bool descending = false,
    Set<String> offline = const {},
    Set<String> collectionFavorites = const {},
  }) {
    clauses.add(catalogVisibility('t'));
    if (filters.visibility != 'all') {
      add("COALESCE(json_extract(t.metadata,'\$.libraryHidden'),0)=?", [
        filters.visibility == 'hidden' ? 1 : 0,
      ]);
    }
    final query = searchKey(text);
    if (query.isNotEmpty) add('instr(c.searchable,?)>0', [query]);
    if (filters.source.isNotEmpty) {
      add(
        "(c.provider!='local' AND c.provider=?) OR EXISTS(SELECT 1 FROM cloud_sources s WHERE s.id=? AND s.active=1 AND ${cloudAccountMatch('s.account', 'c.account')} AND (c.folder=s.folder OR substr(c.folder,1,length(s.folder)+1)=s.folder||'/')) OR (c.provider='local' AND EXISTS(SELECT 1 FROM local_source_tracks m JOIN local_sources s ON s.id=m.source_id WHERE m.track_id=t.id AND m.source_id=? AND m.present=1 AND s.active=1)) OR (c.provider='local' AND ?='local' AND NOT EXISTS(SELECT 1 FROM local_source_tracks m WHERE m.track_id=t.id))",
        [filters.source, filters.source, filters.source, filters.source],
      );
    }
    if (filters.account.isNotEmpty) {
      add(cloudAccountMatch('c.account', '?'), [
        filters.account,
        filters.account,
      ]);
    }
    if (filters.folder.isNotEmpty) {
      final folder = filters.folder.replaceAll(r'\', '/');
      add('c.folder=? OR substr(c.folder,1,length(?))=?', [
        folder,
        '$folder/',
        '$folder/',
      ]);
    }
    if (filters.artist.isNotEmpty) {
      add('EXISTS(SELECT 1 FROM json_each(c.artists) a WHERE a.value=?)', [
        artistNameKey(filters.artist),
      ]);
    }
    if (filters.genre.isNotEmpty) {
      add('EXISTS(SELECT 1 FROM json_each(c.genres) g WHERE g.value=?)', [
        filters.genre,
      ]);
    }
    if (filters.album.isNotEmpty) {
      add(
        'c.album_identity=? OR c.album_identity IN (SELECT album_identity FROM catalog_search WHERE album_previous=?)',
        [filters.album, filters.album],
      );
    }
    if (filters.year.isNotEmpty) add('CAST(c.year AS TEXT)=?', [filters.year]);
    if (filters.format.isNotEmpty) add('c.format=?', [filters.format]);
    if (filters.offline) {
      add('t.id IN (SELECT value FROM json_each(?))', [
        jsonEncode(offline.toList()),
      ]);
    }
    if (filters.favorites) {
      add('EXISTS(SELECT 1 FROM favorites f WHERE f.track_id=t.id)', []);
    }
    if (filters.heard != 'all') {
      add(
        filters.heard == 'heard'
            ? 'COALESCE(h.play_count,0)>0'
            : 'COALESCE(h.play_count,0)=0',
        [],
      );
    }
    final field = switch (sort) {
      'artist' => 'c.artist_key',
      'album' => 'c.album_key',
      'duration' => 'c.duration_ms',
      'added' => 'c.added_us',
      'last' => "COALESCE(julianday(h.last_played),2440587.5)",
      'plays' => 'COALESCE(h.play_count,0)',
      _ => 'c.title_key',
    };
    final direction = descending ? 'DESC' : 'ASC';
    order = sort == 'track'
        ? 'COALESCE(c.disc_number,2147483647) $direction,COALESCE(c.track_number,2147483647) $direction,c.title_key $direction,t.id $direction'
        : '$field $direction,t.id $direction';
  }
  final clauses = <String>[], arguments = <Object?>[];
  late final String order;
  void add(String clause, List<Object?> args) {
    clauses.add('($clause)');
    arguments.addAll(args);
  }

  String get where => clauses.join(' AND ');
  static const from =
      'FROM tracks t JOIN catalog_search c ON c.track_id=t.id LEFT JOIN (SELECT track_id,COUNT(*) AS play_count,MAX(started_at) AS last_played FROM history GROUP BY track_id) h ON h.track_id=t.id';
}
