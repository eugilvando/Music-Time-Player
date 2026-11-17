import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_time/application/update_check.dart';

Map<String, dynamic> release(
  String tag,
  String asset, {
  bool preview = false,
}) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': preview,
  'html_url': '$publicRepository/releases/tag/$tag',
  'assets': [
    {'name': asset, 'state': 'uploaded'},
  ],
};
void main() {
  test('selects stable installer for the OS and compares numerically', () {
    final data = [
      release('v3.0.9', 'MusicTime-Setup-3.0.9.exe'),
      release('v3.0.10', 'MusicTime-Setup-3.0.10.exe'),
      release('v4.0.0-ubuntu', 'music-time_4.0.0_amd64.deb'),
      release('v5.0.0', 'MusicTime-Setup-5.0.0.exe', preview: true),
      release('v6.0.0', 'source.zip'),
    ];
    expect(selectRelease(data, 'windows')?.version, '3.0.10');
    expect(selectRelease(data, 'linux')?.version, '4.0.0');
    expect(compareVersions('3.0.6+71', '3.0.3'), greaterThan(0));
    expect(selectRelease(data, 'macos'), isNull);
    expect(versionParts('3.1.0-rc1'), isNull);
  });
  test('rejects drafts and off-repository destinations', () {
    expect(
      selectRelease([
        {...release('v4.0.0', 'MusicTime-Setup-4.0.0.exe'), 'draft': true},
        {
          ...release('v4.0.0', 'MusicTime-Setup-4.0.0.exe'),
          'html_url': 'https://example.com/update',
        },
      ], 'windows'),
      isNull,
    );
  });
  test('handles unavailable, malformed and empty service responses', () async {
    for (final response in [
      http.Response('', 403),
      http.Response('{}', 200),
      http.Response('bad', 200),
    ]) {
      final client = MockClient((_) async => response);
      await expectLater(
        checkForUpdate('windows', client: client),
        throwsA(anything),
      );
      client.close();
    }
    final client = MockClient((request) async {
      expect(request.url.host, 'api.github.com');
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response('[]', 200);
    });
    expect(await checkForUpdate('windows', client: client), isNull);
    client.close();
  });
}
