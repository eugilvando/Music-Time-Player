import 'dart:convert';
import 'dart:typed_data';

const maxLyricsBytes = 2 * 1024 * 1024;
const maxLyricsTagBytes = 8 * 1024 * 1024;

String decodeLyricsBytes(List<int> bytes, {int? encoding}) {
  if (bytes.length > maxLyricsTagBytes) {
    throw const FormatException('Lyrics exceed the size limit');
  }
  var start = 0;
  var little = encoding != 2;
  if (bytes.length >= 2 &&
      ((bytes[0] == 255 && bytes[1] == 254) ||
          (bytes[0] == 254 && bytes[1] == 255))) {
    little = bytes[0] == 255;
    start = 2;
    encoding = 1;
  }
  if (encoding == 1 || encoding == 2) {
    return String.fromCharCodes([
      for (var i = start; i + 1 < bytes.length; i += 2)
        little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
    ]).replaceAll('\u0000', '').replaceFirst('\uFEFF', '');
  }
  if (encoding == 0) return latin1.decode(bytes).replaceAll('\u0000', '');
  try {
    return utf8
        .decode(bytes)
        .replaceFirst('\uFEFF', '')
        .replaceAll('\u0000', '');
  } on FormatException {
    return latin1.decode(bytes).replaceAll('\u0000', '');
  }
}

int syncSafe(List<int> bytes, int at) =>
    bytes[at] << 21 | bytes[at + 1] << 14 | bytes[at + 2] << 7 | bytes[at + 3];
int _end(List<int> bytes, int at, int encoding) {
  final step = encoding == 1 || encoding == 2 ? 2 : 1;
  for (var i = at; i + step <= bytes.length; i += step) {
    if (bytes[i] == 0 && (step == 1 || bytes[i + 1] == 0)) return i + step;
  }
  return bytes.length;
}

/// ID3v2.2/2.3/2.4 USLT (and common TXXX lyrics). Never reads audio payloads.
String? embeddedId3Lyrics(Uint8List tag) {
  if (tag.length < 10 ||
      tag.length > maxLyricsTagBytes ||
      tag.sublist(6, 10).any((b) => b > 127) ||
      ascii.decode(tag.sublist(0, 3), allowInvalid: true) != 'ID3' ||
      !{2, 3, 4}.contains(tag[3])) {
    return null;
  }
  final version = tag[3];
  var body = tag.sublist(10, (10 + syncSafe(tag, 6)).clamp(10, tag.length));
  if (tag[5] & 0x80 != 0) {
    body = Uint8List.fromList([
      for (var i = 0; i < body.length; i++)
        if (!(i > 0 && body[i - 1] == 255 && body[i] == 0)) body[i],
    ]);
  }
  var at = 0;
  if (tag[5] & 0x40 != 0 && version != 2) {
    if (body.length < 4) return null;
    at = version == 4
        ? syncSafe(body, 0)
        : ByteData.sublistView(body).getUint32(0) + 4;
  }
  final header = version == 2 ? 6 : 10;
  for (var frames = 0; at + header <= body.length && frames < 4096; frames++) {
    final id = ascii.decode(
      body.sublist(at, at + (version == 2 ? 3 : 4)),
      allowInvalid: true,
    );
    if (!RegExp(r'^[A-Z0-9]{3,4}$').hasMatch(id)) break;
    final size = version == 2
        ? body[at + 3] << 16 | body[at + 4] << 8 | body[at + 5]
        : version == 4
        ? syncSafe(body, at + 4)
        : ByteData.sublistView(body).getUint32(at + 4);
    if (size < 1 || at + header + size > body.length) break;
    final flags = version == 2 ? 0 : body[at + 9];
    var payload = body.sublist(at + header, at + header + size);
    at += header + size;
    if (version == 3 && flags & 0xe0 != 0 ||
        version == 4 && flags & 0x4d != 0) {
      continue;
    }
    if (version == 4 && flags & 2 != 0) {
      payload = Uint8List.fromList([
        for (var i = 0; i < payload.length; i++)
          if (!(i > 0 && payload[i - 1] == 255 && payload[i] == 0)) payload[i],
      ]);
    }
    var encoding = payload.first;
    if (!{0, 1, 2, 3}.contains(encoding)) continue;
    // Some writers place the UTF-16 BOM only on the description.
    final description = (id == 'USLT' || id == 'ULT') ? 4 : 1;
    if (encoding == 1 &&
        payload.length > description + 1 &&
        payload[description] == 254 &&
        payload[description + 1] == 255) {
      encoding = 2;
    }
    if ((id == 'USLT' || id == 'ULT') && payload.length > 4) {
      final text = decodeLyricsBytes(
        payload.sublist(_end(payload, 4, encoding)),
        encoding: encoding,
      ).trim();
      if (text.isNotEmpty) return text;
    }
    if (id == 'TXXX' || id == 'TXX') {
      final end = _end(payload, 1, encoding);
      final name = decodeLyricsBytes(
        payload.sublist(1, end),
        encoding: encoding,
      ).toUpperCase();
      if ({'LYRICS', 'UNSYNCEDLYRICS', 'UNSYNCED LYRICS'}.contains(name)) {
        final text = decodeLyricsBytes(
          payload.sublist(end),
          encoding: encoding,
        ).trim();
        if (text.isNotEmpty) return text;
      }
    }
  }
  return null;
}
