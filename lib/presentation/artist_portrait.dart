import 'media_indicators.dart';
import 'artwork_placeholder.dart';
import 'ui_language.dart';
import 'bounded_artwork.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';

import '../domain/track.dart';
import 'now_playing_artwork.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// TheAudioDB v1: exact name matching; disk cache works without a connection.
class ArtistPhotos {
  ArtistPhotos({http.Client? client, Future<Directory> Function()? directory})
    : client = client ?? http.Client(),
      directory = directory ?? getApplicationSupportDirectory;
  final http.Client client;
  final Future<Directory> Function() directory;
  static final instance = ArtistPhotos();
  final Map<String, Future<Uint8List?>> pending = {};
  final _sizes = <String, int>{};
  int memoryBytes = 0;
  void clearMemory() {
    cacheEpoch++;
    pending.clear();
    _sizes.clear();
    memoryBytes = 0;
  }

  void invalidate(String artist) {
    for (final key in [
      artist.toLowerCase().trim(),
      'offline:${artist.toLowerCase().trim()}',
    ]) {
      pending.remove(key);
      memoryBytes -= _sizes.remove(key) ?? 0;
    }
  }

  Future<void> tail = Future.value();
  DateTime lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  int cacheEpoch = 0;
  Future<void> clearDiskCache(Future<void> Function() removeFiles) async {
    clearMemory();
    await tail;
    await removeFiles();
    clearMemory();
  }

  Future<Uint8List?> photo(String artist, {bool cachedOnly = false}) {
    final key = '${cachedOnly ? 'offline:' : ''}${artist.toLowerCase().trim()}';
    final saved = pending.remove(key);
    if (saved != null) {
      pending[key] = saved;
      return saved;
    }
    final epoch = cacheEpoch;
    late final Future<Uint8List?> request;
    request = load(artist, cachedOnly: cachedOnly).then((bytes) {
      if (epoch != cacheEpoch || !identical(pending[key], request)) {
        return bytes;
      }
      _sizes[key] = bytes?.length ?? 0;
      memoryBytes += _sizes[key]!;
      while (pending.length > 64 || memoryBytes > 8 * 1024 * 1024) {
        final completed = pending.keys.where(_sizes.containsKey).firstOrNull;
        if (completed == null) break;
        pending.remove(completed);
        memoryBytes -= _sizes.remove(completed)!;
      }
      return bytes;
    });
    pending[key] = request;
    return request;
  }

  Future<Uint8List?> load(String artist, {bool cachedOnly = false}) async {
    final requestEpoch = cacheEpoch;
    if (artist.trim().isEmpty) return null;
    try {
      final root = await directory();
      final custom = File(
        '${root.path}/artist-custom/${sha256.convert(utf8.encode(artist.toLowerCase().trim()))}.jpg',
      );
      if (await custom.exists()) return await custom.readAsBytes();
      final file = File(
        '${root.path}/artist-photos/${sha256.convert(utf8.encode(artist.toLowerCase().trim()))}.jpg',
      );
      if (await file.exists()) return await file.readAsBytes();
      if (cachedOnly || artist == 'Artista desconhecido') return null;
      Uint8List? bytes;
      final job = tail.then((_) async {
        if (requestEpoch != cacheEpoch) return;
        final elapsed = DateTime.now().difference(lastRequest);
        if (elapsed.inMilliseconds < 2100) {
          await Future<void>.delayed(
            Duration(milliseconds: 2100 - elapsed.inMilliseconds),
          );
        }
        lastRequest = DateTime.now();
        final response = await client
            .get(
              Uri.https('www.theaudiodb.com', '/api/v1/json/123/search.php', {
                's': artist,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return;
        final rows =
            (jsonDecode(response.body) as Map<String, dynamic>)['artists'];
        if (rows is! List) return;
        final matches = rows
            .where(
              (r) =>
                  (r['strArtist'] as String? ?? '').toLowerCase().trim() ==
                  artist.toLowerCase().trim(),
            )
            .toList();
        if (matches.length != 1) return;
        final uri = Uri.tryParse(
          matches.single['strArtistThumb'] as String? ?? '',
        );
        if (uri == null ||
            uri.scheme != 'https' ||
            !(uri.host == 'theaudiodb.com' ||
                uri.host.endsWith('.theaudiodb.com'))) {
          return;
        }
        final image = await client.get(uri).timeout(const Duration(seconds: 8));
        if (image.statusCode != 200 ||
            image.bodyBytes.isEmpty ||
            image.bodyBytes.length > 5 * 1024 * 1024 ||
            !(image.headers['content-type'] ?? '').startsWith('image/')) {
          return;
        }
        bytes = image.bodyBytes;
        if (requestEpoch != cacheEpoch) return;
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsBytes(bytes!, flush: true);
        await temp.rename(file.path);
      });
      tail = job.catchError((Object _) {});
      await job;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

class ArtistPortrait extends StatelessWidget {
  const ArtistPortrait({
    super.key,
    required this.artist,
    this.enabled = true,
    this.fallbackTrack,
    this.cachedOnly = false,
  });
  final Track? fallbackTrack;
  final String artist;
  final bool enabled;
  final bool cachedOnly;
  Widget fallback(BuildContext context) => fallbackTrack?.hasArtwork == true
      ? TrackCover(track: fallbackTrack, circular: true, indicators: false)
      : const ClipOval(child: ArtworkPlaceholder(artist: true));
  @override
  Widget build(BuildContext context) => Center(
    child: AspectRatio(
      aspectRatio: 1,
      child: MediaBadges(
        favorite:
            MediaIndicatorScope.of(context)?.artistFavorite(artist) ?? false,
        child: FutureBuilder<Uint8List?>(
          future: ArtistPhotos.instance.photo(
            artist,
            cachedOnly: cachedOnly || !enabled,
          ),
          builder: (context, snapshot) => snapshot.data == null
              ? fallback(context)
              : ClipOval(
                  child: BoundedArtwork(
                    snapshot.data!,
                    errorBuilder: (_, _, _) => fallback(context),
                  ),
                ),
        ),
      ),
    ),
  );
}

Future<bool> customizeArtistImage(BuildContext context, String artist) async {
  final source = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      insetPadding: const EdgeInsets.all(24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      title: const UiText('Imagem do artista'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'file'),
          child: const UiText('Escolher arquivo'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'url'),
          child: const UiText('Usar link HTTPS'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'reset'),
          child: const UiText('Remover imagem personalizada'),
        ),
      ],
    ),
  );
  if (source == null || !context.mounted) return false;
  try {
    final root = await ArtistPhotos.instance.directory();
    final key = sha256
        .convert(utf8.encode(artist.toLowerCase().trim()))
        .toString();
    final output = File('${root.path}/artist-custom/$key.jpg');
    if (source == 'reset') {
      if (await output.exists()) await output.delete();
      ArtistPhotos.instance.invalidate(artist);
      return true;
    }
    Uint8List? bytes;
    if (source == 'file') {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Imagens',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
          ),
        ],
      );
      if (file == null) return false;
      if (await file.length() > 5 * 1024 * 1024) {
        throw StateError('Image too large');
      }
      bytes = await file.readAsBytes();
    } else {
      if (!context.mounted) return false;
      final input = TextEditingController();
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          title: const UiText('Link da imagem'),
          content: TextField(
            controller: input,
            decoration: const InputDecoration(labelText: 'https://…'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const UiText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, input.text.trim()),
              child: const UiText('Usar imagem'),
            ),
          ],
        ),
      );
      Future<void>.delayed(const Duration(seconds: 1), input.dispose);
      if (value == null) return false;
      var uri = Uri.parse(value);
      final client = http.Client();
      try {
        for (var redirects = 0; redirects < 5; redirects++) {
          if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
            throw StateError('HTTPS required');
          }
          final request = http.Request('GET', uri)..followRedirects = false;
          final response = await client
              .send(request)
              .timeout(const Duration(seconds: 15));
          if (response.isRedirect) {
            final location = response.headers['location'];
            await response.stream.listen(null).cancel();
            if (location == null) throw StateError('Invalid redirect');
            uri = uri.resolve(location);
            continue;
          }
          if (response.statusCode != 200 ||
              (response.contentLength ?? 0) > 5 * 1024 * 1024) {
            await response.stream.listen(null).cancel();
            throw StateError('Invalid image');
          }
          final buffer = BytesBuilder();
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 15),
          )) {
            buffer.add(chunk);
            if (buffer.length > 5 * 1024 * 1024) {
              throw StateError('Image too large');
            }
          }
          bytes = buffer.takeBytes();
          break;
        }
      } finally {
        client.close();
      }
    }
    if (bytes == null || bytes.isEmpty) return false;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 1024,
      targetHeight: 1024,
      allowUpscaling: false,
    );
    final frame = await codec.getNextFrame();
    final normalized = (await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    frame.image.dispose();
    codec.dispose();
    await output.parent.create(recursive: true);
    if (await FileSystemEntity.type(output.parent.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await FileSystemEntity.type(output.path, followLinks: false) ==
            FileSystemEntityType.link) {
      throw StateError('Unsafe image path');
    }
    await output.writeAsBytes(normalized, flush: true);
    ArtistPhotos.instance.invalidate(artist);
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: UiText(
            'Não foi possível usar esta imagem. Use PNG, JPEG ou WebP de até 5 MB e link HTTPS acessível.',
          ),
        ),
      );
    }
    return false;
  }
}
