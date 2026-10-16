import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/additional_sources.dart';

import 'provider_auth_test.dart' show MemoryVault;

class _LoopbackHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Native audio and permanent download receive source authorization headers',
    () async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      SharedPreferences.setMockInitialValues({});
      final bytes = Uint8List(44 + 44100 * 2 * 5), data = ByteData(44);
      void text(int at, String value) =>
          bytes.setRange(at, at + value.length, value.codeUnits);
      text(0, 'RIFF');
      text(8, 'WAVE');
      text(12, 'fmt ');
      text(36, 'data');
      data.setUint32(4, bytes.length - 8, Endian.little);
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little);
      data.setUint16(22, 1, Endian.little);
      data.setUint32(24, 44100, Endian.little);
      data.setUint32(28, 88200, Endian.little);
      data.setUint16(32, 2, Endian.little);
      data.setUint16(34, 16, Endian.little);
      data.setUint32(40, bytes.length - 44, Endian.little);
      for (final offset in [4, 16, 20, 22, 24, 28, 32, 34, 40]) {
        final length = {20, 22, 32, 34}.contains(offset) ? 2 : 4;
        bytes.setRange(
          offset,
          offset + length,
          data.buffer.asUint8List(offset, length),
        );
      }
      var authenticated = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final expected =
          'Basic ${base64.encode(utf8.encode('listener:fixture-password'))}';
      final subscription = server.listen((request) async {
        if (request.headers.value('authorization') != expected) {
          request.response.statusCode = 401;
          await request.response.close();
          return;
        }
        authenticated++;
        final range = RegExp(r'^bytes=(\d+)-(\d*)$')
            .firstMatch(request.headers.value('range') ?? '');
        var start = range == null ? 0 : int.parse(range[1]!);
        var end = range == null || range[2]!.isEmpty
            ? bytes.length - 1
            : int.parse(range[2]!);
        if (start >= bytes.length) {
          request.response.statusCode = 416;
          await request.response.close();
          return;
        }
        end = end.clamp(start, bytes.length - 1);
        request.response.headers.set('Accept-Ranges', 'bytes');
        request.response.headers.contentType = ContentType('audio', 'wav');
        if (range != null) {
          request.response.statusCode = 206;
          request.response.headers.set(
            'Content-Range',
            'bytes $start-$end/${bytes.length}',
          );
        }
        request.response.contentLength = end - start + 1;
        if (request.method != 'HEAD') {
          request.response.add(bytes.sublist(start, end + 1));
        }
        await request.response.close();
      });
      final directory = await Directory.systemTemp.createTemp(
        'music_time_source_transport_',
      );
      final store = await LibraryStore.open(':memory:'),
          client = HttpOverrides.runWithHttpOverrides(
            http.Client.new,
            _LoopbackHttp(),
          );
      final sources = AdditionalSources(
        await SharedPreferences.getInstance(),
        store,
        MemoryVault(),
        client,
      );
      final source = SourceConnection(
        id: 'dav-native',
        type: 'webdav',
        label: 'Fixture',
        address: 'http://127.0.0.1:${server.port}/music/',
        username: 'listener',
        allowHttp: true,
      );
      final manager = DownloadManager(
            store,
            sources,
            client: client,
            directory: () async => directory,
          ),
          controller = PlayerController(resolver: sources);
      try {
        await sources.add(source, password: 'fixture-password');
        const t = Track(
          id: 'dav-native:wave',
          title: 'Silence',
          artist: 'Fixture',
          sourceProvider: 'webdav',
          sourceAccount: 'dav-native',
          driveId: 'dav-native',
          itemId: 'silence.wav',
          sourcePath: '/source',
          fileName: 'silence.wav',
        );
        await store.addTracks([t]);
        await (controller.player.platform as NativePlayer).setProperty(
          'ao',
          'null',
        );
        await controller.restore([t], 0, Duration.zero);
        for (
          var i = 0;
          i < 50 &&
              controller.duration == Duration.zero &&
              controller.error == null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(controller.error, isNull);
        expect(controller.duration.inSeconds, 5);
        await controller.toggle();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(controller.playing, true);
        await controller.seek(const Duration(seconds: 2));
        expect(controller.error, isNull);
        await manager.select('fixture', [t]);
        final row = await store.offlineFile(t.id);
        expect(row, isNotNull);
        expect(await File(row!['path'] as String).readAsBytes(), bytes);
        manager.offlineOnly = true;
        expect((await manager.resolve(t)).scheme, 'file');
        expect(authenticated, greaterThanOrEqualTo(2));
      } finally {
        controller.dispose();
        manager.dispose();
        sources.dispose();
        client.close();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await subscription.cancel();
        await server.close(force: true);
        await store.close();
        // Only this test-created temporary directory is removed.
        expect(directory.path.contains('music_time_source_transport_'), true);
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.environment['MUSIC_TIME_LIBMPV'] == null
        ? 'Requires the distributed native audio engine.'
        : false,
  );
}
