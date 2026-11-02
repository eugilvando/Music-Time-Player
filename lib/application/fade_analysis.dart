import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// Analyze bounded PCM windows, without decoding an entire library track.
Future<List<double>?> _peaks(String path, int seconds, bool tail) async {
  if (!path.toLowerCase().endsWith('.wav')) return null;
  final file = await File(path).open();
  try {
    final header = await file.read(12);
    if (header.length != 12 ||
        String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(header.sublist(8)) != 'WAVE') {
      return null;
    }
    int rate = 0, channels = 0;
    for (var n = 0; n < 64; n++) {
      final chunk = await file.read(8);
      if (chunk.length != 8) return null;
      final id = String.fromCharCodes(chunk.sublist(0, 4));
      final size = ByteData.sublistView(chunk).getUint32(4, Endian.little);
      final offset = await file.position();
      if (id == 'fmt ' && size >= 16) {
        final fmt = await file.read(16);
        if (fmt.length != 16) return null;
        final d = ByteData.sublistView(fmt);
        if (d.getUint16(0, Endian.little) != 1 ||
            d.getUint16(14, Endian.little) != 16) {
          return null;
        }
        channels = d.getUint16(2, Endian.little);
        rate = d.getUint32(4, Endian.little);
        if (rate < 8000 || rate > 192000 || channels < 1 || channels > 8) {
          return null;
        }
      }
      if (id == 'data' && rate > 0) {
        final frame = rate ~/ 10 * channels * 2;
        final length = min(size ~/ frame, seconds * 10) * frame;
        if (length < frame * 3) return null;
        if (tail) await file.setPosition(offset + size - size % frame - length);
        final bytes = await file.read(length);
        if (bytes.length != length) return null;
        final d = ByteData.sublistView(bytes);
        return [for (var i = 0; i < length; i += frame) _peak(d, i, frame)];
      }
      await file.setPosition(offset + size + (size.isOdd ? 1 : 0));
    }
    return null;
  } finally {
    await file.close();
  }
}

double _peak(ByteData bytes, int offset, int size) {
  var peak = 0;
  for (var i = offset; i < offset + size; i += 2) {
    peak = max(peak, bytes.getInt16(i, Endian.little).abs());
  }
  return peak / 32768;
}

Future<int?> smartOverlapMs(
  String from,
  String to,
  int seconds, {
  required bool mixOnly,
}) async {
  final peaks = await Future.wait([
    _peaks(from, seconds, true),
    _peaks(to, seconds, false),
  ]);
  final a = peaks.first, b = peaks.last;
  if (a == null || b == null) return null;
  final limit = min(a.length, b.length);
  // Longest overlap whose peak envelopes leave room for both tracks.
  for (var n = limit; n >= 3; n--) {
    var safe = true;
    for (var i = 0; i < n; i++) {
      if (a[a.length - n + i] + b[i] > (mixOnly ? 0.9 : 1.15)) {
        safe = false;
        break;
      }
    }
    if (safe) return n * 100;
  }
  return mixOnly ? 0 : min(500, limit * 100);
}
