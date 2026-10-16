import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:music_time/library/local_metadata.dart';
import 'package:music_time/domain/track.dart';

void main() {
  test('FLAC lê tags reais, relações múltiplas e capa embutida', () async {
    final root = await Directory.systemTemp.createTemp('music-time-tags-');
    try {
      final image = await File('assets/branding/icon.png').readAsBytes();
      List<int> number(int value, [Endian endian = Endian.big]) =>
          (ByteData(4)..setUint32(0, value, endian)).buffer.asUint8List();
      final comments = [
        'TITLE=Faixa real',
        'ARTIST=Nome & Banda',
        'ARTIST=Participante',
        'ALBUM=Álbum real',
        'ALBUMARTIST=Artista do álbum',
        'DATE=2021',
        'TRACKNUMBER=3',
        'DISCNUMBER=2',
        'GENRE=Rock',
        'GENRE=Pop',
      ];
      final tags = BytesBuilder()
        ..add(number(0, Endian.little))
        ..add(number(comments.length, Endian.little));
      for (final text in comments) {
        final bytes = utf8.encode(text);
        tags
          ..add(number(bytes.length, Endian.little))
          ..add(bytes);
      }
      final picture = BytesBuilder()
        ..add(number(3))
        ..add(number(9))
        ..add(utf8.encode('image/png'))
        ..add(number(0))
        ..add(number(128))
        ..add(number(128))
        ..add(number(32))
        ..add(number(0))
        ..add(number(image.length))
        ..add(image);
      final stream = Uint8List(34);
      final audio = (44100 << 44) | (1 << 41) | (15 << 36) | 44100;
      ByteData.sublistView(stream).setUint64(10, audio);
      List<int> block(int type, List<int> bytes) => [
        type,
        (bytes.length >> 16) & 255,
        (bytes.length >> 8) & 255,
        bytes.length & 255,
        ...bytes,
      ];
      final file = await File(path.join(root.path, 'tags.flac')).writeAsBytes([
        ...utf8.encode('fLaC'),
        ...block(0, stream),
        ...block(4, tags.takeBytes()),
        ...block(0x86, picture.takeBytes()),
      ]);
      final track = readLocalTracks([file.path]).single;
      expect(track.title, 'Faixa real');
      expect(track.album, 'Álbum real');
      expect(track.artistNames, ['Nome', 'Banda', 'Participante']);
      expect(track.genreNames, ['Rock', 'Pop']);
      expect(track.year, 2021);
      expect(track.trackNumber, 3);
      expect(track.discNumber, 2);
      expect(track.cover, image);
      expect(
        embeddedArtwork([
          Picture(Uint8List.fromList([1]), 'image/jpeg', PictureType.coverBack),
          Picture(image, 'image/png', PictureType.coverFront),
        ]),
        image,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
    'capa de pasta e falha de tags preservam metadados anteriores',
    () async {
      final root = await Directory.systemTemp.createTemp('music-time-cover-');
      try {
        final file = await File(path.join(root.path, 'a.mp3'))
            .writeAsBytes([1]);
        final image = await File('assets/branding/icon.png').readAsBytes();
        await File(path.join(root.path, 'cover.png')).writeAsBytes(image);
        final current = readLocalTracks([file.path]).single;
        expect(current.cover, image);
        final old = Track(
          id: file.path,
          localPath: file.path,
          title: 'Título conhecido',
          artist: 'Artista real',
          album: 'Álbum conhecido',
        );
        final preserved = readLocalSyncTracks({
          'paths': [file.path],
          'previous': <String, Track>{file.path: old},
        }).single;
        expect(preserved.title, 'Título conhecido');
        expect(preserved.album, 'Álbum conhecido');
        expect(preserved.cover, image);
        expect(await file.readAsBytes(), [1]);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
