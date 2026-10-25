import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/presentation/bounded_artwork.dart';
import 'package:music_time/presentation/artist_portrait.dart';

class FixturePhotos extends ArtistPhotos {
  int reads = 0;
  final gates = <String, Completer<Uint8List?>>{};
  @override
  Future<Uint8List?> load(String artist, {bool cachedOnly = false}) async {
    reads++;
    if (gates.containsKey(artist)) return gates[artist]!.future;
    return Uint8List(256 * 1024);
  }
}

void main() {
  test('portrait cache is bounded, shares active requests, and safely invalidates late results', () async {
    final photos = FixturePhotos();
    addTearDown(photos.client.close);
    for (var i = 0; i < 100; i++) {
      await photos.photo('artist$i');
    }
    expect(photos.memoryBytes, lessThanOrEqualTo(8 * 1024 * 1024));
    expect(photos.pending.length, lessThanOrEqualTo(64));
    final reads = photos.reads;
    await photos.photo('artist99');
    expect(photos.reads, reads);
    photos.gates['late'] = Completer<Uint8List?>();
    final request = photos.photo('late');
    expect(identical(request, photos.photo('late')), isTrue);
    photos.clearMemory();
    photos.gates['late']!.complete(Uint8List(100));
    await request;
    expect(photos.memoryBytes, 0);
    expect(photos.pending, isEmpty);
  });

  testWidgets(
    'large artwork decodes to physical thumbnail pixels; full player remains larger',
    (tester) async {
      final bytes = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 2048, 2048),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final source = await picture.toImage(2048, 2048);
        final result = (await source.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        source.dispose();
        picture.dispose();
        return result;
      }))!;
      final provider = MemoryImage(bytes);
      Future<ui.Image> decode(ImageProvider image) {
        final done = Completer<ui.Image>();
        final stream = image.resolve(ImageConfiguration.empty);
        late ImageStreamListener listener;
        listener = ImageStreamListener((info, _) {
          done.complete(info.image.clone());
          stream.removeListener(listener);
        });
        stream.addListener(listener);
        return done.future;
      }

      late ui.Image original, small, large;
      await tester.runAsync(() async {
        original = await decode(provider);
        final smallEdge = BoundedArtwork.decodeEdge(
          const BoxConstraints.tightFor(width: 96, height: 96),
          1,
        );
        small = await decode(
          ResizeImage(
            provider,
            width: smallEdge,
            height: smallEdge,
            policy: ResizeImagePolicy.fit,
          ),
        );
        final bigEdge = BoundedArtwork.decodeEdge(
          const BoxConstraints.tightFor(width: 700, height: 700),
          2,
        );
        large = await decode(
          ResizeImage(
            provider,
            width: bigEdge,
            height: bigEdge,
            policy: ResizeImagePolicy.fit,
          ),
        );
      });
      final fullBytes = original.width * original.height * 4;
      final thumbBytes = small.width * small.height * 4;
      expect(original.width, 2048);
      expect(small.width, 128);
      expect(large.width, 2048);
      expect(thumbBytes, lessThan(fullBytes ~/ 100));
      await tester.runAsync(() async {
        final out = Directory('build')..createSync(recursive: true);
        await File(
          '${out.path}/validation-2.3.0-image-memory.txt',
        ).writeAsString(
          'fixture=2048x2048 PNG; thumbnail=96 logical px DPR1\noriginalDecodedBytes=$fullBytes\nthumbnailDecodedBytes=$thumbBytes\nlargePlayerDecodedBytes=${large.width * large.height * 4}\nThis measures decoded image pixels, not whole-app or personal-library RAM.\n',
        );
      });
      original.dispose();
      small.dispose();
      large.dispose();
      PaintingBinding.instance.imageCache.clear();
    },
  );
}
