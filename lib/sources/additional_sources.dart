import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../domain/ports.dart';
import '../domain/track.dart';
import '../library/cloud_metadata.dart';
import '../library/local_metadata.dart';
import '../persistence/library_store.dart';
import 'microsoft_auth.dart';

const additionalSourceTypes = {
  'google': 'Google Drive',
  'webdav': 'WebDAV',
  'jellyfin': 'Jellyfin',
  'emby': 'Emby',
  'smb': 'SMB',
};

List<Track> _originalSourceRows(List<Map<String, Object?>> rows) =>
    rows.map((row) => decodeTrackRow(row, applyUser: false)).toList();

List<Map<String, Object>> _parseDavListing(List<int> bytes) {
  final xml = XmlDocument.parse(utf8.decode(bytes));
  if (xml.rootElement.name.local != 'multistatus' ||
      xml.rootElement.namespaceUri != 'DAV:') {
    throw const FormatException('The server did not return a WebDAV listing.');
  }
  final items = <Map<String, Object>>[];
  for (final response in xml.findAllElements(
    'response',
    namespaceUri: 'DAV:',
  )) {
    final href = response.getElement('href', namespaceUri: 'DAV:')?.innerText;
    if (href == null) continue;
    for (final propstat in response.findElements(
      'propstat',
      namespaceUri: 'DAV:',
    )) {
      if (!(propstat
              .getElement('status', namespaceUri: 'DAV:')
              ?.innerText
              .contains(' 200 ') ??
          false)) {
        continue;
      }
      final prop = propstat.getElement('prop', namespaceUri: 'DAV:');
      if (prop == null) continue;
      items.add({
        'href': href,
        'folder': prop
            .findAllElements('collection', namespaceUri: 'DAV:')
            .isNotEmpty,
        'revision':
            prop.getElement('getetag', namespaceUri: 'DAV:')?.innerText ??
            prop
                .getElement('getlastmodified', namespaceUri: 'DAV:')
                ?.innerText ??
            '',
      });
    }
  }
  return items;
}

class SourceConnection {
  SourceConnection({
    required this.id,
    required this.type,
    required this.label,
    this.address = '',
    this.folder = '',
    this.username = '',
    this.clientId = '',
    this.visible = true,
    this.connected = true,
    this.allowHttp = false,
  });
  final String id, type, label, address, username, clientId;
  String folder;
  String folderName = '';
  bool visible;
  bool connected;
  final bool allowHttp;
  Map<String, Object> toJson() => {
    'id': id,
    'type': type,
    'label': label,
    'address': address,
    'folder': folder,
    'folderName': folderName,
    'username': username,
    'clientId': clientId,
    'visible': visible,
    'connected': connected,
    'allowHttp': allowHttp,
  };
  factory SourceConnection.fromJson(Map<String, dynamic> value) =>
      (SourceConnection(
        id: value['id'] as String,
        type: value['type'] as String,
        label: value['label'] as String,
        address: value['address'] as String? ?? '',
        folder: value['folder'] as String? ?? '',
        username: value['username'] as String? ?? '',
        clientId: value['clientId'] as String? ?? '',
        visible: value['visible'] != false,
        connected: value['connected'] != false,
        allowHttp: value['allowHttp'] == true,
      )..folderName = value['folderName'] as String? ?? '');
  Uri get base {
    final uri = Uri.parse(address.endsWith('/') ? address : '$address/');
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(uri.scheme == 'https' || (uri.scheme == 'http' && allowHttp))) {
      throw const MediaSourceFailure(
        'Use an HTTPS server URL without credentials or query parameters. HTTP requires explicit permission.',
      );
    }
    return uri;
  }

  bool contains(Uri uri) =>
      uri.origin == base.origin &&
      uri.path.startsWith(base.path) &&
      uri.userInfo.isEmpty;
}

class AdditionalSources extends ChangeNotifier
    implements MediaSourceResolver, AuthenticatedMediaResolver {
  AdditionalSources(
    this.preferences,
    this.store,
    this.vault,
    this.client, {
    this.browser = openSystemBrowser,
  }) {
    try {
      for (final row in jsonDecode(
        preferences.getString('additional_sources') ?? '[]',
      ) as List) {
        final source = SourceConnection.fromJson(
          Map<String, dynamic>.from(row as Map),
        );
        if (additionalSourceTypes.containsKey(source.type)) {
          connections.add(source);
        }
      }
    } catch (_) {
      /* Invalid configuration never changes the catalog. */
    }
  }
  final SharedPreferences preferences;
  final LibraryStore store;
  final SecretVault vault;
  final http.Client client;
  final OpenBrowser browser;
  final connections = <SourceConnection>[];
  final busy = <String>{}, cancelled = <String>{};
  final messages = <String, String>{};
  final refreshes = <String, Future<String>>{};
  final _previous = <String, Map<String, Track>>{};
  bool disposed = false;
  void changed() {
    if (!disposed) notifyListeners();
  }

  String secretKey(String id) => 'source.$id.session';
  Future<Map<String, dynamic>> session(SourceConnection source) async {
    final text = await vault.read(secretKey(source.id));
    return text == null
        ? {}
        : Map<String, dynamic>.from(jsonDecode(text) as Map);
  }

  Future<void> persist() async {
    if (!await preferences.setString(
      'additional_sources',
      jsonEncode(connections.map((s) => s.toJson()).toList()),
    )) {
      throw const MediaSourceFailure('Could not save source configuration.');
    }
    for (final s in connections) {
      await store.saveCloudSource(
        s.id,
        s.id,
        '/source',
        s.label,
        s.visible && s.connected,
      );
    }
    changed();
  }

  Future<void> add(
    SourceConnection source, {
    String password = '',
    String clientSecret = '',
    bool reconnect = false,
  }) async {
    if (!additionalSourceTypes.containsKey(source.type) ||
        (connections.any((s) => s.id == source.id) &&
            (!reconnect || !connections.contains(source)))) {
      throw ArgumentError('Invalid source');
    }
    if (source.type == 'smb') {
      if (!Platform.isWindows ||
          !source.address.startsWith(r'\\') ||
          source.address.startsWith(r'\\?\')) {
        throw const MediaSourceFailure(
          r'Use a Windows UNC path such as \\server\share\Music. Authenticate through Windows Credential Manager.',
        );
      }
    } else if (source.type != 'google') {
      source.base;
    }
    if (source.type == 'google') {
      await authorizeGoogle(source, clientSecret);
    } else if ({'jellyfin', 'emby'}.contains(source.type)) {
      final result = await requestJson(
        source,
        source.base.resolve('Users/AuthenticateByName'),
        method: 'POST',
        headers: {
          source.type == 'emby' ? 'X-Emby-Authorization' : 'Authorization':
              authorization(source),
        },
        body: jsonEncode({'Username': source.username, 'Pw': password}),
      );
      if (result['AccessToken'] is! String ||
          result['User'] is! Map ||
          result['User']['Id'] is! String) {
        throw const MediaSourceFailure(
          'The server did not return a valid user session.',
        );
      }
      await vault.write(
        secretKey(source.id),
        jsonEncode({
          'token': result['AccessToken'],
          'userId': result['User']['Id'],
        }),
      );
    } else if (source.type == 'webdav') {
      await vault.write(
        secretKey(source.id),
        jsonEncode({'password': password}),
      );
    }
    if (reconnect && !source.connected) source.visible = true;
    source.connected = true;
    if (!reconnect) connections.add(source);
    try {
      await persist();
    } catch (_) {
      if (!reconnect) {
        connections.remove(source);
        await vault.delete(secretKey(source.id));
      }
      rethrow;
    }
  }

  String authorization(SourceConnection s, [String? token]) =>
      'MediaBrowser Client="Music Time", Device="Windows", DeviceId="${s.id}", Version="0.7.0"${token == null ? '' : ', Token="$token"'}';

  Future<List<int>> requestBytes(
    SourceConnection s,
    Uri uri, {
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    int limit = 8 * 1024 * 1024,
  }) async {
    if (s.type == 'google') {
      if (uri.scheme != 'https' ||
          uri.host != 'www.googleapis.com' ||
          uri.port != 443 ||
          uri.userInfo.isNotEmpty) {
        throw const MediaSourceFailure('Invalid Google API endpoint.');
      }
    } else if (!s.contains(uri)) {
      throw const MediaSourceFailure(
        'The server returned a URL outside this source.',
      );
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      if (cancelled.contains(s.id) || disposed) {
        throw const MediaSourceFailure('Cancelled');
      }
      final request = http.Request(method, uri)..followRedirects = false;
      request.headers.addAll(headers ?? await this.headers(s));
      if (body != null) {
        request.body = body;
        request.headers['Content-Type'] = method == 'PROPFIND'
            ? 'application/xml; charset=utf-8'
            : 'application/json';
      }
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 429 || response.statusCode >= 500) {
        await response.stream.listen(null).cancel();
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
          continue;
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.listen(null).cancel();
        throw MediaSourceFailure(
          response.statusCode == 401 || response.statusCode == 403
              ? 'Access denied. Reconnect this source or check its permissions.'
              : 'The source request failed (HTTP ${response.statusCode}).',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > limit) {
          throw const MediaSourceFailure(
            'The source response exceeds its size limit.',
          );
        }
        if (cancelled.contains(s.id) || disposed) {
          throw const MediaSourceFailure('Cancelled');
        }
      }
      return bytes;
    }
    throw const MediaSourceFailure(
      'The source is temporarily unavailable. Retry later.',
    );
  }

  Future<Map<String, dynamic>> requestJson(
    SourceConnection s,
    Uri uri, {
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
  }) async => Map<String, dynamic>.from(
    jsonDecode(
      utf8.decode(
        await requestBytes(
          s,
          uri,
          method: method,
          headers: headers,
          body: body,
        ),
      ),
    ) as Map,
  );
  Future<Map<String, String>> headers(SourceConnection s) async {
    final data = await session(s);
    if (s.type == 'google') {
      return {'Authorization': 'Bearer ${await googleToken(s)}'};
    }
    if (s.type == 'webdav') {
      return {
        'Authorization':
            'Basic ${base64.encode(utf8.encode('${s.username}:${data['password'] ?? ''}'))}',
      };
    }
    if ({'jellyfin', 'emby'}.contains(s.type)) {
      final token = data['token'];
      if (token is! String || token.isEmpty) {
        throw const MediaSourceFailure('Reconnect this media server.');
      }
      return s.type == 'jellyfin'
          ? {'Authorization': authorization(s, token)}
          : {'X-Emby-Token': token};
    }
    return {};
  }

  Future<void> authorizeGoogle(SourceConnection s, String secret) async {
    if (!s.clientId.endsWith('.apps.googleusercontent.com')) {
      throw const MediaSourceFailure('Enter a Google OAuth desktop client ID.');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final state = secureRandomString(), verifier = secureRandomString();
    final redirect = 'http://127.0.0.1:${server.port}/oauth';
    final result = Completer<String>();
    final subscription = server.listen((request) async {
      if (request.uri.path != '/oauth' ||
          request.uri.queryParameters['state'] != state) {
        request.response.statusCode = 400;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.text;
      request.response.write('You can return to Music Time.');
      await request.response.close();
      if (!result.isCompleted) {
        final code = request.uri.queryParameters['code'];
        if (code == null || code.isEmpty) {
          result.completeError(
            const MediaSourceFailure('Google authorization was declined.'),
          );
        } else {
          result.complete(code);
        }
      }
    });
    try {
      final opened = await browser(
        Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
          'client_id': s.clientId,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': 'https://www.googleapis.com/auth/drive.readonly',
          'access_type': 'offline',
          'prompt': 'consent select_account',
          'state': state,
          'code_challenge': pkceChallenge(verifier),
          'code_challenge_method': 'S256',
        }),
      );
      if (!opened) {
        throw const MediaSourceFailure('Could not open the system browser.');
      }
      final code = await result.future.timeout(const Duration(minutes: 3));
      final data = await googleExchange({
        'client_id': s.clientId,
        if (secret.isNotEmpty) 'client_secret': secret,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
      });
      if (data['refresh_token'] is! String) {
        throw const MediaSourceFailure(
          'Google did not return offline access. Authorize again.',
        );
      }
      data['expires_at'] = DateTime.now()
          .add(Duration(seconds: (data['expires_in'] as num? ?? 3600).toInt()))
          .toIso8601String();
      data['client_secret'] = secret;
      data['session_id'] = secureRandomString();
      await vault.write(secretKey(s.id), jsonEncode(data));
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<Map<String, dynamic>> googleExchange(
    Map<String, String> fields,
  ) async {
    final response = await client
        .post(Uri.https('oauth2.googleapis.com', '/token'), body: fields)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw const MediaSourceFailure(
        'Google login expired or was rejected. Check the desktop OAuth registration and reconnect.',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<String> googleToken(SourceConnection s) async {
    final data = await session(s);
    final expiry = DateTime.tryParse('${data['expires_at']}');
    if (expiry != null &&
        expiry.isAfter(DateTime.now().add(const Duration(minutes: 1))) &&
        data['access_token'] is String) {
      return data['access_token'] as String;
    }
    return refreshes.putIfAbsent(s.id, () async {
      try {
        if (data['refresh_token'] is! String) {
          throw const MediaSourceFailure('Reconnect Google Drive.');
        }
        final next = await googleExchange({
          'client_id': s.clientId,
          'refresh_token': data['refresh_token'] as String,
          if ((data['client_secret'] as String? ?? '').isNotEmpty)
            'client_secret': data['client_secret'] as String,
          'grant_type': 'refresh_token',
        });
        data.addAll(next);
        data['expires_at'] = DateTime.now()
            .add(
              Duration(seconds: (next['expires_in'] as num? ?? 3600).toInt()),
            )
            .toIso8601String();
        if (!connections.contains(s) || !s.connected) {
          throw const MediaSourceFailure('Source disconnected.');
        }
        if ((await session(s))['session_id'] != data['session_id']) {
          throw const MediaSourceFailure('The source session changed. Retry.');
        }
        await vault.write(secretKey(s.id), jsonEncode(data));
        return data['access_token'] as String;
      } finally {
        refreshes.remove(s.id);
      }
    });
  }

  SourceConnection sourceFor(Track track) =>
      connections
          .where(
            (s) =>
                s.id == track.account &&
                s.type == track.provider &&
                s.connected,
          )
          .firstOrNull ??
      (throw const MediaSourceFailure(
        'Reconnect the original source for this track.',
      ));
  @override
  Future<Uri> resolve(Track track) async {
    if (preferences.getBool('visual.offline_only') ?? false) {
      throw const MediaSourceFailure(
        'This source is unavailable in offline mode.',
      );
    }
    final s = sourceFor(track), item = track.itemId;
    if (item == null || item.isEmpty) {
      throw const MediaSourceFailure('Synchronize this source again.');
    }
    if (s.type == 'google') {
      return Uri.https(
        'www.googleapis.com',
        '/drive/v3/files/${Uri.encodeComponent(item)}',
        {'alt': 'media'},
      );
    }
    if (s.type == 'smb') {
      final root = path.windows.normalize(s.address);
      final target = path.windows.normalize(path.windows.join(root, item));
      if (!path.windows.isWithin(root, target)) {
        throw const MediaSourceFailure('Invalid share path.');
      }
      return Uri.file(target, windows: true);
    }
    if (s.type == 'webdav') {
      final uri = s.base.resolve(item);
      if (!s.contains(uri)) {
        throw const MediaSourceFailure('Invalid WebDAV file path.');
      }
      return uri;
    }
    return s.base
        .resolve('Audio/${Uri.encodeComponent(item)}/stream')
        .replace(queryParameters: {'Static': 'true'});
  }

  @override
  Future<Map<String, String>> mediaHeaders(Track track, Uri uri) async {
    final s = sourceFor(track);
    if (uri != await resolve(track)) {
      throw const MediaSourceFailure('Media origin mismatch.');
    }
    return headers(s);
  }

  @override
  bool allowsInsecureMedia(Uri uri) => connections.any(
    (s) =>
        s.type != 'google' && s.type != 'smb' && s.allowHttp && s.contains(uri),
  );
  void cancel(String id) {
    cancelled.add(id);
    changed();
  }

  Future<void> disconnect(SourceConnection s) async {
    if (busy.contains(s.id)) {
      throw const MediaSourceFailure(
        'Cancel synchronization and wait before removing this source.',
      );
    }
    s.connected = false;
    s.visible = false;
    await vault.delete(secretKey(s.id));
    await store.saveCloudSource(s.id, s.id, '/source', s.label, false);
    await persist();
  }

  Future<void> remove(SourceConnection s) async {
    if (busy.contains(s.id)) {
      throw const MediaSourceFailure(
        'Cancel synchronization and wait before removing this source.',
      );
    }
    busy.add(s.id);
    changed();
    try {
      await store.removeCloudSource(s.id);
      await vault.delete(secretKey(s.id));
      connections.remove(s);
      try {
        await persist();
      } catch (_) {
        connections.add(s);
        rethrow;
      }
      messages.remove(s.id);
    } finally {
      busy.remove(s.id);
      changed();
    }
  }

  Future<List<Map<String, dynamic>>> googleFolders(
    SourceConnection s,
    String parent,
  ) async {
    if (s.type != 'google' || !s.connected) {
      throw const MediaSourceFailure(
        'Reconnect this source before synchronizing.',
      );
    }
    final result = <Map<String, dynamic>>[];
    String? token;
    do {
      final data = await requestJson(
        s,
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q':
              "'${parent.replaceAll("'", "\\'")}' in parents and trashed=false and mimeType='application/vnd.google-apps.folder'",
          'fields': 'nextPageToken,files(id,name)',
          'pageSize': '1000',
          'orderBy': 'name',
          if (token != null) 'pageToken': token,
        }),
      );
      result.addAll(
        (data['files'] as List? ?? []).map(
          (r) => Map<String, dynamic>.from(r as Map),
        ),
      );
      token = data['nextPageToken'] as String?;
    } while (token != null && token.isNotEmpty);
    return result;
  }

  Future<void> selectGoogleFolder(
    SourceConnection s,
    String id,
    String name,
  ) async {
    if (s.type != 'google' || busy.contains(s.id)) {
      throw const MediaSourceFailure('Wait for synchronization to finish.');
    }
    // Validate access and type before changing the scan scope.
    final data = await requestJson(
      s,
      Uri.https(
        'www.googleapis.com',
        '/drive/v3/files/${Uri.encodeComponent(id)}',
        {'fields': 'id,name,mimeType'},
      ),
    );
    if (data['mimeType'] != 'application/vnd.google-apps.folder') {
      throw const MediaSourceFailure('Select a music folder.');
    }
    final previous = s.folder, previousName = s.folderName;
    s.folder = data['id'] as String;
    s.folderName = data['name'] as String? ?? name;
    try {
      await persist();
    } catch (_) {
      s.folder = previous;
      s.folderName = previousName;
      rethrow;
    }
  }

  Future<void> setVisible(SourceConnection s, bool value) async {
    s.visible = value;
    await persist();
  }

  Future<void> sync(SourceConnection s) async {
    if (busy.contains(s.id)) return;
    if (!s.connected) {
      throw const MediaSourceFailure(
        'Reconnect this source before synchronizing.',
      );
    }
    if (preferences.getBool('visual.offline_only') ?? false) {
      throw const MediaSourceFailure(
        'Turn off offline mode to synchronize sources.',
      );
    }
    busy.add(s.id);
    cancelled.remove(s.id);
    messages[s.id] = 'Connecting…';
    changed();
    final seen = <String>{};
    final batch = <Track>[];
    try {
      final oldRows = await store.database.query(
        'tracks',
        columns: LibraryStore.metadataColumns,
        where: "json_extract(metadata,'\$.sourceAccount')=? AND json_extract(metadata,'\$.sourceProvider')=?",
        whereArgs: [s.id, s.type],
      );
      final old = await compute(_originalSourceRows, oldRows);
      _previous[s.id] = {for (final t in old) t.id: t};
      final stream = s.type == 'smb'
          ? smbTracks(s)
          : s.type == 'webdav'
          ? webdavTracks(s)
          : s.type == 'google'
          ? googleTracks(s)
          : serverTracks(s);
      await for (final track in stream) {
        if (cancelled.contains(s.id) || disposed) {
          throw const MediaSourceFailure(
            'Cancelled. Existing catalog preserved.',
          );
        }
        if (!seen.add(track.id)) continue;
        batch.add(track);
        if (batch.length == 50) {
          await store.addTracks(batch, preserveCovers: true);
          batch.clear();
          messages[s.id] = '${seen.length} tracks indexed';
          changed();
        }
      }
      if (cancelled.contains(s.id) || disposed) {
        throw const MediaSourceFailure(
          'Cancelled. Existing catalog preserved.',
        );
      }
      if (batch.isNotEmpty) await store.addTracks(batch, preserveCovers: true);
      final rows = await store.database.rawQuery(
        "SELECT id FROM tracks WHERE json_extract(metadata,'\$.sourceAccount')=? AND json_extract(metadata,'\$.sourceProvider')=?",
        [s.id, s.type],
      );
      await store.finishSync(
        s.id,
        Uri(scheme: 'catalog', path: s.id),
        rows
            .map((r) => r['id'] as String)
            .where((id) => !seen.contains(id))
            .toList(),
      );
      messages[s.id] =
          '${seen.length} tracks · Updated ${DateTime.now().toLocal()}';
    } catch (error) {
      messages[s.id] = error is MediaSourceFailure ? error.message : 'Source unavailable. Check the address, account permissions and connection, then retry.';
      rethrow;
    } finally {
      _previous.remove(s.id);
      busy.remove(s.id);
      cancelled.remove(s.id);
      changed();
    }
  }

  String trackId(SourceConnection s, String item) =>
      '${s.type}:${s.id}:${sha256.convert(utf8.encode(item))}';
  bool audio(String name) => {
    '.mp3',
    '.flac',
    '.m4a',
    '.ogg',
    '.opus',
    '.wav',
    '.aac',
    '.wma',
  }.contains(path.extension(name).toLowerCase());
  Track track(
    SourceConnection s,
    String item,
    String name, {
    String revision = '',
    CloudTags? tags,
    int tagsVersion = 0,
    String folder = '/source',
  }) => Track(
    id: trackId(s, item),
    title: tags?.title.isNotEmpty == true
        ? tags!.title
        : path.basenameWithoutExtension(name),
    artist: tags?.artists.isNotEmpty == true
        ? tags!.artists.join('; ')
        : 'Unknown artist',
    artists: tags?.artists ?? [],
    album: tags?.album ?? '',
    albumId: tags?.albumId ?? '',
    edition: tags?.edition ?? '',
    albumArtists: tags?.albumArtists ?? [],
    genres: tags?.genres ?? [],
    year: tags?.year,
    trackNumber: tags?.trackNumber,
    discNumber: tags?.discNumber,
    cloudTagsVersion: tagsVersion,
    duration: tags?.duration ?? Duration.zero,
    cover: tags?.cover,
    driveId: s.id,
    itemId: item,
    sourceProvider: s.type,
    sourceAccount: s.id,
    sourcePath: folder,
    fileName: name,
    revision: revision,
    format: path.extension(name).replaceFirst('.', '').toUpperCase(),
  );
  Future<CloudTags?> remoteTags(
    SourceConnection s,
    String item,
    String name,
  ) async {
    final t = track(s, item, name);
    final uri = await resolve(t);
    try {
      return await CloudMetadataReader(
        _SourceClient(
          client,
          s.type == 'google' ? (u) => u == uri : s.contains,
          await headers(s),
        ),
        allowedUri: (u) => u == uri,
        cancelled: () => cancelled.contains(s.id) || disposed,
      ).read(uri, name);
    } catch (_) {
      return null;
    }
  }

  Future<Track> indexFile(
    SourceConnection s,
    String item,
    String name, {
    required String folder,
    required String revision,
  }) async {
    final old = _previous[s.id]?[trackId(s, item)];
    CloudTags? tags;
    var tagsVersion = old?.cloudTagsVersion ?? 0;
    if (old == null ||
        revision.isEmpty ||
        revision != old.revision ||
        old.discNumber == null &&
            old.cloudTagsVersion < cloudMetadataVersion &&
            RegExp(r'\.(mp3|flac)$', caseSensitive: false).hasMatch(name)) {
      tags = await remoteTags(s, item, name);
      if (tags != null) tagsVersion = cloudMetadataVersion;
    }
    tags ??= old == null
        ? null
        : CloudTags(
            title: old.title,
            artists: old.artistNames,
            album: old.album,
            albumArtists: old.albumArtistNames,
            genres: old.genreNames,
            year: old.year,
            trackNumber: old.trackNumber,
            discNumber: old.discNumber,
            duration: old.duration,
            albumId: old.albumId,
            edition: old.edition,
          );
    return track(
      s,
      item,
      name,
      folder: folder,
      revision: revision,
      tags: tags,
      tagsVersion: tagsVersion,
    );
  }

  Stream<Track> googleTracks(SourceConnection s) async* {
    final folders = <(String, String)>[
      (s.folder.isEmpty ? 'root' : s.folder, '/source'),
    ];
    final visited = <String>{};
    while (folders.isNotEmpty) {
      final (parent, folder) = folders.removeLast();
      if (!visited.add(parent)) continue;
      String? token;
      do {
        final q =
            "'${parent.replaceAll("'", "\\'")}' in parents and trashed=false";
        final data = await requestJson(
          s,
          Uri.https('www.googleapis.com', '/drive/v3/files', {
            'q': q,
            'pageSize': '100',
            'fields':
                'nextPageToken,files(id,name,mimeType,modifiedTime,version)',
            if (token != null) 'pageToken': token,
          }),
        );
        for (final raw in data['files'] as List? ?? []) {
          final row = Map<String, dynamic>.from(raw as Map),
              id = row['id'] as String,
              name = row['name'] as String;
          if (row['mimeType'] == 'application/vnd.google-apps.folder') {
            folders.add((id, '$folder/$name'));
          } else if (audio(name)) {
            yield await indexFile(
              s,
              id,
              name,
              folder: folder,
              revision: '${row['version'] ?? row['modifiedTime'] ?? ''}',
            );
          }
        }
        token = data['nextPageToken'] as String?;
      } while (token != null);
    }
  }

  Stream<Track> webdavTracks(SourceConnection s) async* {
    final folders = <Uri>[s.base], visited = <String>{};
    while (folders.isNotEmpty) {
      final folder = folders.removeLast();
      if (!visited.add(folder.path)) continue;
      final bytes = await requestBytes(
        s,
        folder,
        method: 'PROPFIND',
        headers: {...await headers(s), 'Depth': '1'},
        body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getetag/><d:getlastmodified/><d:getcontentlength/></d:prop></d:propfind>',
      );
      final rows = await compute(_parseDavListing, bytes);
      for (final row in rows) {
        final uri = folder.resolve(row['href'] as String);
        if (!s.contains(uri) ||
            uri.path == folder.path ||
            uri.hasQuery ||
            uri.hasFragment ||
            uri.pathSegments.contains('..')) {
          continue;
        }
        if (row['folder'] == true) {
          folders.add(
            uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/'),
          );
          continue;
        }
        final name = uri.pathSegments.last;
        if (!audio(name)) continue;
        final item = uri.toString().substring(s.base.toString().length);
        yield await indexFile(
          s,
          item,
          name,
          folder:
              '/source/${uri.pathSegments.skip(s.base.pathSegments.length - 1).take(uri.pathSegments.length - s.base.pathSegments.length).join('/')}',
          revision: row['revision'] as String,
        );
      }
    }
  }

  Stream<Track> serverTracks(SourceConnection s) async* {
    final data = await session(s), user = data['userId'] as String?;
    if (user == null) throw const MediaSourceFailure('Reconnect this server.');
    var start = 0;
    while (true) {
      final endpoint = s.type == 'emby'
          ? 'Users/${Uri.encodeComponent(user)}/Items'
          : 'Items';
      final result = await requestJson(
        s,
        s.base
            .resolve(endpoint)
            .replace(
              queryParameters: {
                'UserId': user,
                'IncludeItemTypes': 'Audio',
                'Recursive': 'true',
                'StartIndex': '$start',
                'Limit': '100',
                'Fields': 'Genres,DateCreated,MediaSources,ProviderIds',
                if (s.folder.isNotEmpty) 'ParentId': s.folder,
              },
            ),
      );
      final rows = result['Items'] as List? ?? [];
      if (rows.isEmpty) break;
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final item = row['Id'] as String;
        List<String> names(String key) {
          final values = (row[key] as List? ?? []).whereType<String>().toList();
          if (values.isEmpty &&
              key == 'AlbumArtists' &&
              row['AlbumArtist'] is String &&
              (row['AlbumArtist'] as String).isNotEmpty) {
            return [row['AlbumArtist'] as String];
          }
          return values;
        }

        final media = row['MediaSources'] as List? ?? [];
        final container = media.isEmpty
            ? 'mp3'
            : (media.first as Map)['Container'] as String? ?? 'mp3';
        final base = track(
          s,
          item,
          '${row['Name']}.$container',
          revision: '${row['Etag'] ?? row['DateCreated'] ?? ''}',
          tags: CloudTags(
            title: row['Name'] as String? ?? '',
            artists: names('Artists'),
            album: row['Album'] as String? ?? '',
            albumId: row['AlbumId'] is String
                ? '${s.type}:${s.id}:${row['AlbumId']}'
                : '',
            albumArtists: names('AlbumArtists'),
            genres: names('Genres'),
            year: row['ProductionYear'] as int?,
            trackNumber: row['IndexNumber'] as int?,
            discNumber: row['ParentIndexNumber'] as int?,
            duration: Duration(
              microseconds: ((row['RunTimeTicks'] as num? ?? 0) / 10).round(),
            ),
          ),
        );
        yield base;
      }
      start += rows.length;
      final total = result['TotalRecordCount'] as int?;
      if (total != null ? start >= total : rows.length < 100) break;
    }
  }

  Stream<Track> smbTracks(SourceConnection s) async* {
    final root = Directory(s.address);
    if (!await root.exists()) {
      throw const MediaSourceFailure(
        'Share unavailable. Open this UNC path in Windows and configure Windows Credential Manager, then retry.',
      );
    }
    final files = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (cancelled.contains(s.id) || disposed) {
        throw const MediaSourceFailure('Cancelled');
      }
      if (entity is! File || !audio(entity.path)) continue;
      files.add(entity.path);
      if (files.length == 25) {
        yield* smbBatch(s, files);
        files.clear();
      }
    }
    yield* smbBatch(s, files);
  }

  Stream<Track> smbBatch(SourceConnection s, List<String> files) async* {
    final tags = await compute(readLocalTracks, List<String>.of(files));
    for (final t in tags) {
      final relative = path.windows.relative(t.localPath!, from: s.address);
      final stat = await File(t.localPath!).stat();
      yield track(
        s,
        relative,
        path.windows.basename(relative),
        folder:
            '/source/${path.windows.dirname(relative).replaceAll(r'\', '/')}',
        revision: '${stat.size}:${stat.modified.millisecondsSinceEpoch}',
        tags: CloudTags(
          title: t.title,
          artists: t.artistNames,
          album: t.album,
          albumArtists: t.albumArtistNames,
          genres: t.genreNames,
          year: t.year,
          trackNumber: t.trackNumber,
          discNumber: t.discNumber,
          duration: t.duration,
          cover: t.cover,
        ),
      );
    }
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _SourceClient extends http.BaseClient {
  _SourceClient(this.inner, this.allowed, this.auth);
  final http.Client inner;
  final bool Function(Uri) allowed;
  final Map<String, String> auth;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!allowed(request.url)) {
      throw const MediaSourceFailure(
        'Source redirected outside its authorized origin.',
      );
    }
    request.followRedirects = false;
    request.headers.addAll(auth);
    return inner.send(request);
  }
}
