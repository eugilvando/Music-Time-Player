class LyricWord {
  const LyricWord(this.at, this.text);
  final Duration at;
  final String text;
}

class LyricLine {
  const LyricLine(this.text, {this.at, this.words = const []});
  final String text;
  final Duration? at;
  final List<LyricWord> words;
}

class LyricsDocument {
  const LyricsDocument(this.lines, {this.offset = Duration.zero, this.source});
  final String? source;
  final List<LyricLine> lines;
  final Duration offset;
  bool get synchronized => lines.any((line) => line.at != null);
  int activeIndex(Duration position, {Duration adjustment = Duration.zero}) {
    final effective = position - offset - adjustment;
    var result = -1;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].at != null && lines[index].at! <= effective) {
        result = index;
      } else if (lines[index].at != null) {
        break;
      }
    }
    return result;
  }
}

Duration _timestamp(String minutes, String seconds, String? fraction) {
  final second = int.parse(seconds);
  if (second >= 60) throw const FormatException('Segundos inválidos');
  final milliseconds = int.parse((fraction ?? '').padRight(3, '0'));
  return Duration(
    minutes: int.parse(minutes),
    seconds: second,
    milliseconds: milliseconds,
  );
}

LyricsDocument parseLyrics(String source) {
  final timing = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final wordTiming = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');
  final lines = <LyricLine>[];
  var offset = Duration.zero;
  for (final raw in source.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'))) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    final offsetMatch = RegExp(
      r'^\[offset:([+-]?\d+)\]$',
      caseSensitive: false,
    ).firstMatch(value);
    if (offsetMatch != null) {
      offset = Duration(milliseconds: int.parse(offsetMatch[1]!));
      continue;
    }
    if (RegExp(
      r'^\[(ar|al|ti|by|re|ve|length):.*\]$',
      caseSensitive: false,
    ).hasMatch(value)) {
      continue;
    }
    final matches = timing.allMatches(value).toList();
    if (matches.isEmpty) {
      if (value.startsWith('[') || wordTiming.hasMatch(value)) {
        throw const FormatException('Timestamp inválido');
      }
      lines.add(LyricLine(value));
      continue;
    }
    if (matches.first.start != 0) {
      throw const FormatException('Timestamp fora do início');
    }
    var lastEnd = 0;
    for (final match in matches) {
      if (match.start != lastEnd) {
        throw const FormatException('Timestamp intercalado');
      }
      lastEnd = match.end;
    }
    final text = value.substring(lastEnd).trim();
    final wordMatches = wordTiming.allMatches(text).toList();
    final words = <LyricWord>[];
    for (var i = 0; i < wordMatches.length; i++) {
      final match = wordMatches[i];
      final at = _timestamp(match[1]!, match[2]!, match[3]);
      if (words.isNotEmpty && at < words.last.at) {
        throw const FormatException('Palavras fora de ordem');
      }
      final end = i + 1 < wordMatches.length
          ? wordMatches[i + 1].start
          : text.length;
      words.add(LyricWord(at, text.substring(match.end, end)));
    }
    final cleanText = text.replaceAll(wordTiming, '');
    for (final match in matches) {
      lines.add(
        LyricLine(
          cleanText,
          at: _timestamp(match[1]!, match[2]!, match[3]),
          words: matches.length == 1 ? words : const [],
        ),
      );
    }
  }
  if (lines.isEmpty) throw const FormatException('Letra vazia');
  if (lines.any((line) => line.at != null)) {
    if (lines.any((line) => line.at == null)) {
      throw const FormatException(
        'Letra mistura linhas temporizadas e texto solto',
      );
    }
    lines.sort((a, b) => a.at!.compareTo(b.at!));
  }
  return LyricsDocument(
    lines,
    offset: offset,
    source: source.startsWith('[by:LRCLIB]') ? 'LRCLIB' : null,
  );
}
