/// Parsing is independent of catalog resolution and persistence.
class ParsedPlaylistEntry {
  const ParsedPlaylistEntry(
    this.line,
    this.reference,
    this.title,
    this.artist,
    this.duration,
    this.drive,
  );
  final int line;
  final String reference, title, artist;
  final int? duration;
  final String? drive;
}

List<ParsedPlaylistEntry> parseM3uEntries(String content) {
  if (content.contains('\u0000') || content.trimLeft().startsWith('<')) {
    throw const FormatException('Invalid or unsupported playlist');
  }
  final entries = <ParsedPlaylistEntry>[];
  final lines = content.replaceFirst('\uFEFF', '').split(RegExp(r'\r\n|\n|\r'));
  String title = '', artist = '';
  String? drive;
  int? duration;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('#EXTINF:')) {
      final comma = line.indexOf(',');
      if (comma < 0) throw const FormatException('Invalid EXTINF');
      duration = int.tryParse(line.substring(8, comma));
      final label = line.substring(comma + 1),
          split = line.substring(comma + 1).indexOf(' - ');
      artist = split < 0 ? '' : label.substring(0, split);
      title = split < 0 ? label : label.substring(split + 3);
    } else if (line.startsWith('#MUSICTIME-DRIVE:')) {
      drive = Uri.decodeComponent(line.substring(17));
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      entries.add(
        ParsedPlaylistEntry(i + 1, line, title, artist, duration, drive),
      );
      title = '';
      artist = '';
      duration = null;
      drive = null;
    }
  }
  if (entries.isEmpty) {
    throw const FormatException('Invalid or unsupported playlist');
  }
  return entries;
}
