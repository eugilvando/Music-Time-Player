import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/library/mp3_duration.dart';

void main() {
  test(
    'Xing and Info frame counts return VBR duration without bitrate estimates',
    () {
      for (final marker in ['Xing', 'Info']) {
        final bytes = Uint8List(128)
          ..setAll(0, [255, 251, 144, 0])
          ..setAll(36, marker.codeUnits);
        final data = ByteData.sublistView(bytes);
        data.setUint32(40, 1);
        data.setUint32(44, 7656);
        expect(mp3FrameDuration(bytes)!.inSeconds, 199);
      }
    },
  );
  test('VBRI counts work and absent or malformed counts stay unknown', () {
    final bytes = Uint8List(128)
      ..setAll(0, [255, 251, 144, 0])
      ..setAll(36, 'VBRI'.codeUnits);
    final data = ByteData.sublistView(bytes);
    data.setUint16(40, 1);
    data.setUint32(50, 7656);
    expect(mp3FrameDuration(bytes)!.inSeconds, 199);
    data.setUint32(50, 0);
    expect(mp3FrameDuration(bytes), isNull);
    expect(mp3FrameDuration(Uint8List(128)), isNull);
    expect(mp3FrameDuration(Uint8List(5)), isNull);
  });
}
