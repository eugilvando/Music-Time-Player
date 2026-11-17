import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const publicRepository = 'https://github.com/eugilvando/Music-Time-Player';

/// Stable, platform-specific packages only; never offer source-only releases.
class AppRelease {
  const AppRelease(this.version, this.page);
  final String version;
  final Uri page;
}

List<int>? versionParts(String value) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?(?:-ubuntu)?$')
      .firstMatch(value);
  return match == null
      ? null
      : [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

int compareVersions(String a, String b) {
  final left = versionParts(a), right = versionParts(b);
  if (left == null || right == null) throw const FormatException('Version');
  for (var i = 0; i < 3; i++) {
    final result = left[i].compareTo(right[i]);
    if (result != 0) return result;
  }
  return 0;
}

AppRelease? selectRelease(List<dynamic> releases, String platform) {
  AppRelease? best;
  for (final item in releases) {
    if (item is! Map || item['draft'] != false || item['prerelease'] != false) {
      continue;
    }
    final tag = item['tag_name'];
    if (tag is! String || versionParts(tag) == null) continue;
    final assets = item['assets'];
    if (assets is! List ||
        !assets.any((asset) {
          if (asset is! Map || asset['state'] != 'uploaded') return false;
          final name = asset['name'];
          if (name is! String) return false;
          return switch (platform) {
            'windows' => RegExp(
              r'^MusicTime-Setup-[\d.]+\.exe$',
            ).hasMatch(name),
            'linux' =>
              name.endsWith('_amd64.deb') || name.endsWith('.AppImage'),
            _ => false,
          };
        })) {
      continue;
    }
    final page = Uri.tryParse(
      item['html_url'] is String ? item['html_url'] : '',
    );
    if (page == null ||
        page.scheme != 'https' ||
        page.host != 'github.com' ||
        !page.path.startsWith('/eugilvando/Music-Time-Player/releases/tag/')) {
      continue;
    }
    if (best == null || compareVersions(tag, best.version) > 0) {
      best = AppRelease(
        tag.replaceFirst(RegExp(r'^v'), '').replaceFirst('-ubuntu', ''),
        page,
      );
    }
  }
  return best;
}

Future<AppRelease?> checkForUpdate(
  String platform, {
  http.Client? client,
}) async {
  final connection = client ?? http.Client();
  try {
    final response = await connection
        .get(
          Uri.https(
            'api.github.com',
            '/repos/eugilvando/Music-Time-Player/releases',
            {'per_page': '100'},
          ),
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'Music-Time',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 4 * 1024 * 1024) {
      throw StateError('Release service unavailable');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! List) throw const FormatException('Releases');
    return selectRelease(data, platform);
  } finally {
    if (client == null) connection.close();
  }
}
