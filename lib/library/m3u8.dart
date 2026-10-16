import 'package:path/path.dart' as path;

import '../domain/track.dart';
import 'playlist_reference.dart';
import 'playlist_parser.dart';

/// Cloud paths are relative to the drive root, never download URLs.
String? oneDrivePlaylistPath(Track track) {
  if (track.provider != 'onedrive' ||
      track.driveId == null ||
      track.fileName.isEmpty ||
      !track.sourcePath.startsWith('/drive/root:')) {
    return null;
  }
  final folder = track.sourcePath.substring('/drive/root:'.length);
  return path.posix.normalize(
    '/${folder.replaceFirst(RegExp(r'^/+'), '')}/${track.fileName}',
  );
}

String _cloudKey(String value) => path.posix.normalize(value).toLowerCase();

String exportM3u8(String name, List<Track> tracks) {
  String clean(String value) => value.replaceAll(RegExp(r'[\r\n]'), ' ');
  return [
    '#EXTM3U',
    '#PLAYLIST:${clean(name)}',
    for (final track in tracks) ...[
      '#EXTINF:${track.duration == Duration.zero ? -1 : track.duration.inSeconds},${clean(track.artist)} - ${clean(track.title)}',
      if (oneDrivePlaylistPath(track) != null)
        '#MUSICTIME-DRIVE:${Uri.encodeComponent(track.driveId!)}',
      oneDrivePlaylistPath(track) ?? PlaylistReference.track(track),
    ],
    '',
  ].join('\n');
}

class PlaylistImportEntry {
  PlaylistImportEntry(
    this.line,
    this.reference,
    this.candidates,
    this.suggestions, {
    this.title = '',
    this.artist = '',
    this.durationSeconds,
    this.driveId,
    this.sourcePath = '',
    this.reason,
  });
  final int line;
  final String reference;
  final List<String> candidates, suggestions;
  final String title, artist, sourcePath;
  final int? durationSeconds;
  final String? driveId, reason;
  String? selected;
  bool removed = false;
  String? get trackId =>
      selected ?? (candidates.length == 1 ? candidates.single : null);
  bool get unresolved => !removed && trackId == null;
}

class PlaylistImportReport {
  PlaylistImportReport(this.entries, {this.name});
  final String? name;
  final List<PlaylistImportEntry> entries;
  List<String> get ids => [
    for (final e in entries)
      if (!e.removed && e.trackId != null) e.trackId!,
  ];
  int get unresolved => entries.where((e) => e.unresolved).length;
}

/// Exports every occurrence, including unresolved references. Relative paths
/// are rebased against the new file; OneDrive paths remain drive-root relative.
String exportPlaylistOccurrences(
  String name,
  List<Map<String, Object?>> rows,
  Map<String, Track> tracks,
  String targetPath,
) {
  String clean(String s) => s.replaceAll(RegExp(r'[\r\n]'), ' ');
  final lines = <String>['#EXTM3U', '#PLAYLIST:${clean(name)}'];
  for (final row in rows) {
    final t = tracks[row['track_id']];
    if (t != null) {
      lines.addAll(
        exportM3u8('', [t]).split('\n').skip(2).where((l) => l.isNotEmpty),
      );
      continue;
    }
    final reference = row['original_reference'] as String?;
    if (reference == null || reference.isEmpty) {
      throw const FormatException(
        'An unresolved item has no exportable reference.',
      );
    }
    final drive = row['reference_drive'] as String?;
    if (reference.startsWith(
      'musictime://unresolved/unsupported-remote-reference',
    )) {
      throw const FormatException(
        'Link unsupported remote references to library tracks before exporting.',
      );
    }
    final oldCloudPath = _syncedCloudPath(
      row['reference_base'] as String? ?? '',
    );
    final exportReference =
        drive != null &&
            oldCloudPath != null &&
            !path.posix.isAbsolute(reference) &&
            !path.windows.isAbsolute(reference) &&
            Uri.tryParse(reference)?.hasScheme != true
        ? path.posix.normalize(
            path.posix.join(
              path.posix.dirname(oldCloudPath),
              reference.replaceAll(r'\', '/'),
            ),
          )
        : reference;
    final rebased = PlaylistReference.rebase(
      exportReference,
      row['reference_base'] as String? ?? targetPath,
      targetPath,
      driveRoot: drive != null,
    );
    lines.add(
      '#EXTINF:${row['import_duration'] ?? -1},${clean('${row['import_artist'] ?? ''} - ${row['import_title'] ?? ''}')}',
    );
    if (drive != null) {
      lines.add('#MUSICTIME-DRIVE:${Uri.encodeComponent(drive)}');
    }
    lines.add(rebased);
  }
  return '${lines.join('\n')}\n';
}

String _localKey(String value) => path.windows.isAbsolute(value)
    ? path.windows.normalize(value).toLowerCase()
    : path.posix.normalize(value);
String? _syncedCloudPath(String value) {
  final parts = value.replaceAll(r'\', '/').split('/');
  final index = parts.indexWhere(
    (v) => RegExp(r'^OneDrive(?: - .+)?$', caseSensitive: false).hasMatch(v),
  );
  return index < 0 ? null : '/${parts.skip(index + 1).join('/')}';
}

PlaylistImportReport reviewM3u8(
  String content,
  String playlistPath,
  List<Track> tracks, {
  String? oneDriveId,
}) {
  final cloud = <String, List<Track>>{},
      local = <String, List<Track>>{},
      filenames = <String, List<Track>>{};
  final byId = <String, Track>{};
  for (final t in tracks) {
    byId[t.id] = t;
    final cp = oneDrivePlaylistPath(t);
    if (cp != null) (cloud[_cloudKey(cp)] ??= []).add(t);
    if (t.localPath != null) (local[_localKey(t.localPath!)] ??= []).add(t);
    final name = t.fileName.isNotEmpty
        ? t.fileName
        : t.localPath == null
        ? ''
        : path.windows.basename(t.localPath!);
    if (name.isNotEmpty) (filenames[name.toLowerCase()] ??= []).add(t);
  }
  final syncedPlaylist = _syncedCloudPath(playlistPath);
  final cloudBase = syncedPlaylist == null
      ? '/'
      : path.posix.dirname(syncedPlaylist);
  final entries = <PlaylistImportEntry>[];
  for (final parsed in parseM3uEntries(content)) {
    final line = parsed.reference;
    final explicitDrive = parsed.drive;
    final drive = explicitDrive ?? oneDriveId;
    final uri = Uri.tryParse(line);
    var matches = <Track>[];
    String? filePath;
    if (uri?.scheme == 'musictime' && uri?.host == 'track') {
      final t = byId[uri!.pathSegments.join('/')];
      if (t != null) matches = [t];
    } else {
      filePath = PlaylistReference.local(line, playlistPath);
      if (filePath != null) matches = local[_localKey(filePath)] ?? [];
      if (matches.isEmpty &&
          (explicitDrive != null ||
              syncedPlaylist != null ||
              line.startsWith('/') ||
              filePath != null && _syncedCloudPath(filePath) != null) &&
          (uri?.hasScheme != true ||
              uri?.scheme == 'file' ||
              path.windows.isAbsolute(line))) {
        final normalized = line.replaceAll(r'\', '/');
        final cp =
            (filePath == null ? null : _syncedCloudPath(filePath)) ??
            (normalized.startsWith('/')
                ? normalized
                : path.posix.join(cloudBase, normalized));
        List<Track> lookup(String value) => (cloud[_cloudKey(value)] ?? [])
            .where((t) => drive == null || t.driveId == drive)
            .toList();
        matches = lookup(cp);
        if (matches.isEmpty && cp.contains('%')) {
          try {
            matches = lookup(Uri.decodeFull(cp));
          } catch (_) {
            /* Literal percent in filename. */
          }
        }
      }
    }
    final basename = path.posix
        .basename(line.replaceAll(r'\', '/'))
        .toLowerCase();
    final suggestions = (filenames[basename] ?? [])
        .where((t) => drive == null || t.driveId == drive)
        .map((t) => t.id)
        .toList();
    entries.add(
      PlaylistImportEntry(
        parsed.line,
        PlaylistReference.safe(line),
        matches.map((t) => t.id).toSet().toList(),
        suggestions,
        title: parsed.title,
        artist: parsed.artist,
        durationSeconds: parsed.duration,
        sourcePath: playlistPath,
        driveId:
            explicitDrive ??
            (matches.any((t) => t.provider == 'onedrive') ||
                    line.startsWith('/') ||
                    syncedPlaylist != null
                ? drive
                : null),
        reason: PlaylistReference.isTransient(line)
            ? 'unsupported'
            : matches.length > 1
            ? 'ambiguous'
            : matches.isEmpty
            ? 'missing'
            : null,
      ),
    );
  }
  if (entries.isEmpty) {
    throw const FormatException('A playlist não contém faixas.');
  }
  final label = content
      .split(RegExp(r'\r\n|\n|\r'))
      .where((line) => line.startsWith('#PLAYLIST:'))
      .firstOrNull;
  return PlaylistImportReport(entries, name: label?.substring(10).trim());
}

List<String> importM3u8(
  String content,
  String playlistPath,
  List<Track> tracks, {
  String? oneDriveId,
}) {
  final report = reviewM3u8(
    content,
    playlistPath,
    tracks,
    oneDriveId: oneDriveId,
  );
  if (report.unresolved != 0) {
    final first = report.entries.firstWhere((e) => e.unresolved);
    throw FormatException(
      'Linha ${first.line}: ${first.candidates.length > 1 ? 'referência ambígua entre contas/fontes' : 'faixa não encontrada no catálogo sincronizado'}. ${report.unresolved} referência(s) precisam de revisão. Localize a faixa ou remova-a da importação.',
    );
  }
  return report.ids;
}

PlaylistImportReport parsePlaylistInBackground(
  ({String content, String filePath, List<Track> tracks, String? drive}) input,
) => reviewM3u8(
  input.content,
  input.filePath,
  input.tracks,
  oneDriveId: input.drive,
);
