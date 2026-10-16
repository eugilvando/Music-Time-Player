import 'ui_language.dart';

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ArtistBiographies {
  ArtistBiographies({
    http.Client? client,
    Future<Directory> Function()? directory,
  }) : client = client ?? http.Client(),
       directory = directory ?? getApplicationSupportDirectory;
  final http.Client client;
  final Future<Directory> Function() directory;
  static final instance = ArtistBiographies();
  final pending = <String, Future<String?>>{};
  Future<void> tail = Future.value();
  Future<String?> load(String artist, {bool offline = false}) {
    if (pending.length >= 128) pending.remove(pending.keys.first);
    return pending.putIfAbsent(
      '${offline ? 'offline:' : ''}$artist',
      () => _load(artist, offline),
    );
  }

  Future<String?> _load(String artist, bool offline) async {
    try {
      final root = await directory();
      final file = File(
        '${root.path}/artist-biographies/${sha256.convert(utf8.encode(artist.trim().toLowerCase()))}.txt',
      );
      if (await file.exists() &&
          await file.length() < 64 * 1024 &&
          (offline ||
              DateTime.now().difference(await file.lastModified()).inDays <
                  30)) {
        return await file.readAsString();
      }
      if (offline) return null;
      String? result;
      final job = tail.then((_) async {
        final response = await client
            .get(
              Uri.https('www.theaudiodb.com', '/api/v1/json/123/search.php', {
                's': artist,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200 ||
            response.bodyBytes.length > 2 * 1024 * 1024) {
          return;
        }
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final rows = data['artists'];
        if (rows is! List) return;
        final matches = rows
            .where(
              (r) =>
                  r is Map &&
                  '${r['strArtist']}'.trim().toLowerCase() ==
                      artist.trim().toLowerCase(),
            )
            .toList();
        if (matches.length != 1) return;
        final raw =
            matches.single['strBiographyEN'] ?? matches.single['strBiography'];
        if (raw is! String || raw.trim().isEmpty) return;
        result = raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (result!.length > 600) {
          result =
              '${result!.substring(0, 600).replaceFirst(RegExp(r'\s+\S*$'), '')}…';
        }
        try {
          await file.parent.create(recursive: true);
          await file.writeAsString(result!);
        } on FileSystemException {
          // A successful lookup remains usable when optional caching fails.
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      tail = job.catchError((Object _) {});
      await job;
      return result;
    } catch (_) {
      return null;
    }
  }
}

class ArtistBiography extends StatelessWidget {
  const ArtistBiography({
    super.key,
    required this.artist,
    this.offline = false,
    this.enabled = true,
  });
  final String artist;
  final bool offline, enabled;
  @override
  Widget build(BuildContext context) => !enabled
      ? const SizedBox.shrink()
      : FutureBuilder<String?>(
          future: ArtistBiographies.instance.load(artist, offline: offline),
          builder: (context, snapshot) => snapshot.data == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        snapshot.data!,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.https('www.theaudiodb.com', '/search.php', {
                            's': artist,
                          }),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const UiText('Biography · TheAudioDB'),
                      ),
                    ],
                  ),
                ),
        );
}
