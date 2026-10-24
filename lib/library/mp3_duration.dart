import 'dart:convert';
import 'dart:typed_data';

/// Exact Layer III duration from an encoder frame-count header, never a
/// file-size/bitrate estimate (which is incorrect for variable bitrate audio).
Duration? mp3FrameDuration(Uint8List bytes) {
  for (var i = 0; i + 64 <= bytes.length; i++) {
    if (bytes[i] != 255 || bytes[i + 1] & 0xe0 != 0xe0) continue;
    final version = (bytes[i + 1] >> 3) & 3;
    if (version == 1 || (bytes[i + 1] >> 1) & 3 != 1) continue;
    final rateIndex = (bytes[i + 2] >> 2) & 3;
    final bitrateIndex = bytes[i + 2] >> 4;
    if (rateIndex == 3 || bitrateIndex == 0 || bitrateIndex == 15) continue;
    final rate =
        [44100, 48000, 32000][rateIndex] ~/
        (version == 3
            ? 1
            : version == 2
            ? 2
            : 4);
    final mono = bytes[i + 3] >> 6 == 3;
    final sideInfo = version == 3 ? (mono ? 17 : 32) : (mono ? 9 : 17);
    final xing = i + 4 + sideInfo;
    int? frames;
    String marker(int offset) =>
        ascii.decode(bytes.sublist(offset, offset + 4), allowInvalid: true);
    final data = ByteData.sublistView(bytes);
    if (xing + 12 <= bytes.length &&
        {'Xing', 'Info'}.contains(marker(xing)) &&
        data.getUint32(xing + 4) & 1 != 0) {
      frames = data.getUint32(xing + 8);
    } else if (i + 54 <= bytes.length &&
        marker(i + 36) == 'VBRI' &&
        data.getUint16(i + 40) == 1) {
      frames = data.getUint32(i + 50);
    }
    if (frames == null || frames == 0) continue;
    final micros = frames * (version == 3 ? 1152 : 576) * 1000000 ~/ rate;
    if (micros > 0 && micros <= const Duration(days: 7).inMicroseconds) {
      return Duration(microseconds: micros);
    }
  }
  return null;
}
