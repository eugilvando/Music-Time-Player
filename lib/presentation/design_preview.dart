import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../domain/track.dart';
import '../library/local_metadata.dart';
import '../persistence/library_store.dart';

/// Route every path-provider consumer (artwork, downloads and data tools) into
/// the same temporary sandbox, including components with their own defaults.
class DesignPreviewPaths extends PathProviderPlatform {
  DesignPreviewPaths(this.root);
  final String root;
  @override
  Future<String> getApplicationSupportPath() async => root;
  @override
  Future<String> getApplicationDocumentsPath() async => root;
  @override
  Future<String> getApplicationCachePath() async => '$root/cache';
  @override
  Future<String> getTemporaryPath() async => '$root/temp';
  @override
  Future<String> getDownloadsPath() async => root;
}

/// Fictional, offline collection used only by --design-preview. Never reads the
/// personal library, providers or credentials and never starts playback.
Future<void> prepareDesignPreview(
  Directory directory,
  LibraryStore store,
  SharedPreferences preferences,
) async {
  await preferences.setString('visual.language', 'en');
  await preferences.setBool('visual.artist_photos', false);
  await preferences.setBool('visual.lyrics_online', false);
  await preferences.setString('visual.style', 'classic');
  await preferences.setBool('windows.close_to_tray', false);
  await preferences.setBool('visual.albums_grid', true);
  await preferences.setBool('visual.albumArtists_grid', true);
  await preferences.setBool('visual.show_queue', false);
  await preferences.setString('visual.songs_view', 'detailed');
  await preferences.setStringList('visual.songs_columns', [
    'artist',
    'year',
    'genre',
    'format',
  ]);
  await preferences.setString('visual.playlists_view', 'grid');
  await preferences.setString(
    'visual.home_modes',
    '{"favorite_albums":"carousel","favorite_playlists":"carousel","favorite_artists":"carousel"}',
  );
  final existing = await store.loadTracks(includeCovers: false);
  if (existing.isNotEmpty) {
    await preferences.setStringList('collections.favorites', [
      for (final track in existing.where((t) => t.trackNumber == 1))
        'album:${albumKey(track)}',
      for (final name in existing.map((t) => t.artist).toSet()) 'artist:$name',
      for (final row in await store.playlists()) 'playlist:${row['id']}',
    ]);
    return;
  }
  final file = File('${directory.path}/Review track.wav');
  final bytes = Uint8List(44 + 8000 * 2 * 120);
  final data = ByteData.sublistView(bytes);
  void text(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, value.codeUnits);
  text(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, bytes.length - 44, Endian.little);
  await file.writeAsBytes(bytes);
  await File('${directory.path}/Review track.lrc').writeAsString(
    '[00:00.00]Music Time — design review\n[00:10.00]A quiet moment in your collection\n[00:20.00]Your music, everywhere\n[00:30.00]Explore the new player\n[00:40.00]This is an offline demonstration\n[00:50.00]Your personal library stays separate\n',
  );
  final tracks = <Track>[];
  const artists = ['Northbound', 'Lina Vale', 'Paper Satellites', 'Sol & Mar'];
  const albums = [
    'After the Rain',
    'Open Windows',
    'Night Garden',
    'Slow Motion',
    'Sunday Morning',
    'Blue Horizon',
    'Quiet Places',
    'Golden Hour',
  ];
  const titles = [
    'First Light',
    'Moving Lines',
    'Somewhere New',
    'A Little Closer',
    'Under the Sun',
    'Coming Home',
  ];
  for (var album = 0; album < albums.length; album++) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final color = HSVColor.fromAHSV(1, album * 43.0, .65, .85).toColor();
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 480, 480),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, const Color(0xff111516)],
        ).createShader(const Rect.fromLTWH(0, 0, 480, 480)),
    );
    for (var line = 0; line < 7; line++) {
      canvas.drawCircle(
        Offset(100 + line * 42, 280 - line * 20),
        100,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..color = Colors.white.withValues(alpha: .18),
      );
    }
    final painter = TextPainter(
      text: TextSpan(
        text: albums[album],
        style: const TextStyle(
          fontFamily: 'Bricolage Grotesque',
          fontWeight: FontWeight.bold,
          fontSize: 42,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 400);
    painter.paint(canvas, const Offset(32, 28));
    final picture = recorder.endRecording();
    final image = await picture.toImage(480, 480);
    final cover = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
    for (var song = 0; song < 6; song++) {
      tracks.add(
        Track(
          id: 'review:$album:$song',
          title: titles[song],
          artist: artists[album % 4],
          albumArtist: artists[album % 4],
          album: albums[album],
          year: 2018 + album,
          genre: album.isEven ? 'Alternative' : 'Electronic',
          trackNumber: song + 1,
          discNumber: 1,
          localPath: file.path,
          sourcePath: directory.path,
          format: 'WAV',
          cover: cover,
          duration: const Duration(minutes: 2),
          addedAt: DateTime(2026, 10, 24).subtract(Duration(days: album)),
        ),
      );
    }
  }
  await store.addTracks(tracks);
  for (final track in tracks.where((t) => t.trackNumber == 1)) {
    await store.setFavorite(track.id, true);
    await store.recordHistory(
      track.id,
      DateTime(2026, 10, 24).subtract(Duration(hours: track.year! - 2017)),
      const Duration(minutes: 1),
    );
  }
  final favorites = <String>[
    for (final track in tracks.where((t) => t.trackNumber == 1))
      'album:${albumKey(track)}',
    for (final artist in artists) 'artist:$artist',
  ];
  for (var p = 0; p < 4; p++) {
    final id = await store.createPlaylist(
      [
        'Morning selection',
        'Weekend favorites',
        'Late night',
        'New discoveries',
      ][p],
    );
    for (final track in tracks.where((t) => t.year! % 4 == p)) {
      await store.appendToPlaylist(id, track.id);
    }
    favorites.add('playlist:$id');
  }
  await preferences.setStringList('collections.favorites', favorites);
  await store.savePlayback(
    tracks.take(18).toList(),
    0,
    Duration.zero,
    title: 'Morning selection',
  );
}
