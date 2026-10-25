import 'package:path/path.dart' as path;

import '../domain/track.dart';
import 'catalog.dart';
import 'm3u8.dart';

String expectedPlaylistTitle(PlaylistImportEntry entry) {
  if (entry.title.trim().isNotEmpty) return entry.title.trim();
  final uri = Uri.tryParse(entry.reference);
  if (uri != null && {'http', 'https'}.contains(uri.scheme)) return '';
  return path.withoutExtension(
    path.posix.basename(entry.reference.replaceAll('\\', '/')),
  );
}

/// Suggestions never confirm a replacement. Original references stay intact.
Map<int, List<String>> recommendPlaylistReplacements(
  (List<PlaylistImportEntry>, List<Track>) work,
) {
  final indexed = [
    for (final t in work.$2)
      (t, searchKey(t.title), t.artistNames.map(searchKey).toSet()),
  ];
  final result = <int, List<String>>{};
  for (final entry in work.$1) {
    final title = searchKey(expectedPlaylistTitle(entry));
    final artist = searchKey(entry.artist);
    final words = title
        .split(RegExp(r'\W+'))
        .where((s) => s.length > 1)
        .toSet();
    final ranked = <(String, double)>[];
    for (final row in indexed) {
      final tokens = row.$2.split(RegExp(r'\W+')).toSet();
      final overlap = words.isEmpty
          ? 0.0
          : words.intersection(tokens).length / words.union(tokens).length;
      var score = row.$2 == title && title.isNotEmpty ? 80.0 : overlap * 60;
      if (artist.isNotEmpty && row.$3.contains(artist)) {
        score += 30;
      }
      if (entry.durationSeconds != null &&
          row.$1.duration.inSeconds > 0 &&
          (row.$1.duration.inSeconds - entry.durationSeconds!).abs() <= 3) {
        score += 5;
      }
      if (score >= 40) ranked.add((row.$1.id, score));
    }
    ranked.sort((a, b) {
      final n = b.$2.compareTo(a.$2);
      return n != 0 ? n : a.$1.compareTo(b.$1);
    });
    result[entry.line] = {
      ...entry.candidates,
      ...entry.suggestions,
      ...ranked.take(8).map((r) => r.$1),
    }.take(12).toList();
  }
  return result;
}
