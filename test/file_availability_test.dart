import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/library/file_availability.dart';
import 'package:music_time/presentation/collection_browser.dart';

void main() {
  test(
    'offline exclui arquivos somente na nuvem, parciais e atributos inválidos',
    () {
      expect(attributesHaveLocalData(0x80), isTrue);
      expect(attributesHaveLocalData(0x80020), isTrue);
      for (final attributes in [
        0xffffffff,
        0x1000,
        0x40000,
        0x400000,
        0x400020,
      ]) {
        expect(attributesHaveLocalData(attributes), isFalse);
      }
    },
  );
  test('validação nativa aceita arquivo Unicode completo e rejeita tamanho divergente', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music-time-offline-state-',
    );
    final file = await File('${directory.path}/áudio-🎵.bin')
        .writeAsBytes([1, 2, 3]);
    try {
      expect(fileHasLocalData(file), isTrue);
      expect(
        validOfflineFiles([
          {'id': 'valid', 'path': file.path, 'bytes': 3},
          {'id': 'partial', 'path': file.path, 'bytes': 4},
          {'id': 'missing', 'path': '${directory.path}/missing.bin'},
        ]),
        {'valid'},
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
