import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/track.dart';
import '../sources/microsoft_auth.dart';
import '../sources/microsoft_sources.dart';
import 'app_data.dart';
import 'library_store.dart';

const backupSections = <String, String>{
  'library': 'Biblioteca',
  'playlists': 'Playlists',
  'favorites': 'Favoritos',
  'history': 'Histórico',
  'queue': 'Fila de reprodução',
  'preferences': 'Preferências',
  'artwork': 'Capas',
  'providers': 'Fontes e IDs de aplicativo',
  'credentials': 'Credenciais e sessões',
};

/// Archive credentials are only ever written inside authenticated encryption.
/// Decrypted data is kept in memory and is never staged for a later restart.
class BackupArchive {
  static const magic = 'MTBACKUP2\n';
  static const iterations = 600000;
  static bool encrypted(List<int> bytes) =>
      bytes.length >= magic.length &&
      ascii.decode(bytes.sublist(0, magic.length), allowInvalid: true) == magic;

  static bool providerKey(String key) =>
      key == 'microsoft.sources' ||
      key == 'additional_sources' ||
      const {
        'lastfm.profile_user',
        'lastfm.now_playing',
        'lastfm.scrobbling',
        'lastfm.index_auto',
        'lastfm.index_delay_seconds',
      }.contains(key) ||
      RegExp(
        r'^microsoft\.(?:source\.[A-Za-z0-9_-]{16,80}\.)?(?:client_id|label|folder_id|folder_name|folder_path|folder_drive_id|folder_selected|visible)$',
      ).hasMatch(key);

  static Set<String> secretKeys(Map<String, Object> config) {
    final keys = <String>{
      'microsoft.session',
      'lastfm.api_key',
      'lastfm.api_secret',
      'lastfm.session',
    };
    for (final id in (config['microsoft.sources'] as List?) ?? const []) {
      if (id is String && validMicrosoftSourceId(id)) {
        keys.add(microsoftSourceSessionKey(id));
      }
    }
    final additional = jsonDecode(
      config['additional_sources'] as String? ?? '[]',
    );
    if (additional is! List) {
      throw const FormatException("Configuração de fonte inválida.");
    }
    for (final row in additional) {
      if (row is! Map ||
          row['id'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(row['id'])) {
        throw const FormatException("Configuração de fonte inválida.");
      }
      keys.add('source.${row['id']}.session');
    }
    return keys;
  }

  static Future<Uint8List> create(
    LibraryStore store,
    SharedPreferences prefs,
    SecretVault vault,
    Set<String> sections, {
    String? password,
  }) async {
    if (sections.isEmpty ||
        sections.contains('artwork') &&
            !sections.contains('library') &&
            !sections.contains('playlists')) {
      throw const FormatException(
        'Selecione biblioteca ou playlists para incluir capas.',
      );
    }
    if (sections.contains('credentials') &&
        (password == null ||
            password.length < 12 ||
            !sections.contains('providers'))) {
      throw const FormatException(
        "Credenciais exigem fontes e senha de pelo menos 12 caracteres.",
      );
    }
    final artwork = sections.contains('artwork');
    if (artwork) {
      final size =
          (await store.database.rawQuery(
                'SELECT ${sections.contains('library') ? '(SELECT COALESCE(SUM(byte_count),0) FROM artworks) + (SELECT COALESCE(SUM(length(cover)),0) FROM tracks)' : '0'} + ${sections.contains('playlists') ? '(SELECT COALESCE(SUM(length(cover)),0) FROM playlists)' : '0'} AS size',
              )).single['size']
              as num;
      if (size > 64 * 1024 * 1024) {
        throw const FormatException(
          "Capas excedem 64 MB. Exporte sem capas; elas podem ser coletadas novamente.",
        );
      }
    }
    final rows = await store.database.transaction((txn) async {
      final result = <String, List<Map<String, Object?>>>{};
      for (final table in AppData.tables) {
        final include = switch (table) {
          'artworks' => artwork && sections.contains('library'),
          'tracks' => sections.any(
            {'library', 'playlists', 'favorites', 'history', 'queue'}.contains,
          ),
          'local_sources' ||
          'local_source_tracks' => sections.contains('library'),
          'playlists' =>
            sections.contains('playlists') || sections.contains('favorites'),
          'playlist_entries' => sections.contains('playlists'),
          'favorites' => sections.contains('favorites'),
          'history' => sections.contains('history'),
          'playback' || 'queue' => sections.contains('queue'),
          _ => false,
        };
        if (!include) {
          result[table] = [];
          continue;
        }
        final columns = [
          for (final column in await txn.rawQuery('PRAGMA table_info($table)'))
            column['name'] as String,
        ];
        if (!artwork || table == 'tracks' && !sections.contains('library')) {
          columns.removeWhere((c) => c == 'cover' || c == 'cover_hash');
        }
        final references = <String>[
          if (sections.contains('playlists'))
            'SELECT track_id FROM playlist_entries WHERE track_id IS NOT NULL',
          if (sections.contains('favorites')) 'SELECT track_id FROM favorites',
          if (sections.contains('history')) 'SELECT track_id FROM history',
          if (sections.contains('queue')) 'SELECT track_id FROM queue',
        ];
        result[table] = await txn.query(
          table,
          columns: columns,
          where: table == 'tracks' && !sections.contains('library')
              ? 'id IN (${references.join(' UNION ')})'
              : null,
        );
      }
      return result;
    });
    final config = <String, Object>{
      if (sections.contains('providers'))
        for (final key in prefs.getKeys().where(providerKey))
          key: prefs.get(key)!,
    };
    final secrets = <String, String>{};
    if (sections.contains('credentials')) {
      for (final key in secretKeys(config)) {
        final value = await vault.read(key);
        if (value != null) secrets[key] = value;
      }
    }
    final preferences = sections.contains('preferences')
        ? AppData.preferences(prefs)
        : <String, Object>{};
    if (sections.contains('favorites')) {
      preferences['collections.favorites'] =
          prefs.getStringList('collections.favorites') ?? <String>[];
    } else {
      preferences.remove('collections.favorites');
    }
    return Isolate.run(() async {
      final tables = {
        for (final table in rows.entries)
          table.key: [
            for (final row in table.value)
              {
                for (final cell in row.entries)
                  cell.key: cell.value is Uint8List
                      ? {'base64': base64Encode(cell.value as Uint8List)}
                      : cell.value,
              },
          ],
      };
      final doc = {
        'format': 'music_time_backup',
        'version': 1,
        'schema': 17,
        'tables': tables,
        'preferences': preferences,
      };
      AppData.parse(jsonEncode(doc));
      final plain = utf8.encode(
        jsonEncode({
          'format': 'music_time_archive',
          'version': 2,
          'sections': sections.toList(),
          'document': doc,
          'providers': config,
          'secrets': secrets,
        }),
      );
      if (plain.length > AppData.maxBytes) {
        throw const FormatException("Backup excede 128 MB. Exporte sem capas.");
      }
      final compressed = gzip.encode(plain);
      if (compressed.length > AppData.maxBytes - 1024) {
        throw const FormatException('Backup excede 128 MB. Exporte sem capas.');
      }
      if (password == null) return Uint8List.fromList(compressed);
      final salt = SecretKeyData.random(length: 16).bytes;
      final algorithm = AesGcm.with256bits();
      final nonce = algorithm.newNonce();
      final header = utf8.encode(
        jsonEncode({
          'version': 2,
          'cipher': 'AES-256-GCM',
          'kdf': 'PBKDF2-HMAC-SHA256',
          'iterations': iterations,
          'salt': base64Encode(salt),
          'nonce': base64Encode(nonce),
        }),
      );
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      final box = await algorithm.encrypt(
        compressed,
        secretKey: key,
        nonce: nonce,
        aad: header,
      );
      return Uint8List.fromList([
        ...ascii.encode(magic),
        ...header,
        10,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
    });
  }

  static Future<Map<String, dynamic>> read(
    Uint8List bytes, {
    String? password,
  }) => Isolate.run(() async {
    if (bytes.length > AppData.maxBytes) {
      throw const FormatException('Backup excede 128 MB.');
    }
    List<int> compressed = bytes;
    final protected = encrypted(bytes);
    if (protected) {
      final end = bytes.indexOf(10, magic.length);
      if (end < 0 || end > 1024 || bytes.length < end + 18) {
        throw const FormatException("Cabeçalho de backup inválido.");
      }
      final header = bytes.sublist(magic.length, end);
      final config = jsonDecode(utf8.decode(header));
      if (config is! Map ||
          config['version'] != 2 ||
          config['cipher'] != 'AES-256-GCM' ||
          config['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          config['iterations'] != iterations ||
          password == null) {
        throw const FormatException(
          "Configuração de criptografia incompatível ou senha ausente.",
        );
      }
      final salt = base64Decode(config['salt'] as String),
          nonce = base64Decode(config['nonce'] as String);
      if (salt.length != 16 || nonce.length != 12) {
        throw const FormatException("Cabeçalho de backup inválido.");
      }
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      try {
        compressed = await AesGcm.with256bits().decrypt(
          SecretBox(
            bytes.sublist(end + 1, bytes.length - 16),
            nonce: nonce,
            mac: Mac(bytes.sublist(bytes.length - 16)),
          ),
          secretKey: key,
          aad: header,
        );
      } on SecretBoxAuthenticationError {
        throw const FormatException("Senha incorreta ou backup danificado.");
      }
    }
    final isGzip =
        compressed.length > 2 && compressed[0] == 31 && compressed[1] == 139;
    final sink = _LimitedSink();
    if (isGzip) {
      final decoder = gzip.decoder.startChunkedConversion(sink);
      for (var i = 0; i < compressed.length; i += 4096) {
        decoder.add(
          compressed.sublist(i, (i + 4096).clamp(0, compressed.length)),
        );
      }
      decoder.close();
    } else {
      sink.add(compressed);
    }
    final text = utf8.decode(sink.bytes.takeBytes());
    final value = jsonDecode(text);
    if (value is Map<String, dynamic> &&
        value['format'] == 'music_time_backup') {
      return {
        'sections': backupSections.keys
            .where((s) => s != 'providers' && s != 'credentials')
            .toList(),
        'document': AppData.parse(text),
        'providers': <String, Object>{},
        'secrets': <String, String>{},
      };
    }
    if (value is! Map<String, dynamic> ||
        value['format'] != 'music_time_archive' ||
        value['version'] != 2 ||
        value['sections'] is! List ||
        (value['sections'] as List).any(
          (s) => !backupSections.containsKey(s),
        ) ||
        value['providers'] is! Map ||
        value['secrets'] is! Map) {
      throw const FormatException("Formato de backup inválido.");
    }
    value['document'] = AppData.parse(jsonEncode(value['document']));
    final config = Map<String, Object>.from(value['providers'] as Map);
    if (config.entries.any(
      (e) => !providerKey(e.key) || !AppData.validPreference(e.value),
    )) {
      throw const FormatException("Configuração de fonte inválida.");
    }
    final allowed = secretKeys(config);
    if ((value['secrets'] as Map).entries.any(
      (e) => !protected || !allowed.contains(e.key) || e.value is! String,
    )) {
      throw const FormatException("Credenciais inválidas ou sem criptografia.");
    }
    return value;
  });

  /// Merge only selected data. Playlist-only imports resolve tracks by identity;
  /// missing entries stay reviewable and never create an unrequested catalog.
  static Future<int> restore(
    LibraryStore store,
    SharedPreferences prefs,
    SecretVault vault,
    Map<String, dynamic> archive,
    Set<String> sections,
  ) async {
    if (!sections.every((s) => (archive['sections'] as List).contains(s))) {
      throw const FormatException("Seção de backup indisponível.");
    }
    final rawDocument = archive['document'];
    final doc = await Isolate.run(() => AppData.parse(jsonEncode(rawDocument)));
    final config = Map<String, Object>.from(archive['providers'] as Map);
    final secrets = Map<String, String>.from(archive['secrets'] as Map);
    if (sections.contains('credentials') && !sections.contains('providers')) {
      throw const FormatException("Restaure fontes junto com as credenciais.");
    }
    final changes = <String, Object>{
      if (sections.contains('preferences'))
        ...Map<String, Object>.from(doc['preferences'] as Map),
      if (sections.contains('providers')) ...config,
    };
    if (sections.contains('favorites') &&
        (doc['preferences'] as Map)['collections.favorites'] is List) {
      changes['collections.favorites'] =
          (doc['preferences'] as Map)['collections.favorites'] as Object;
    } else {
      changes.remove('collections.favorites');
    }
    final previous = {for (final key in changes.keys) key: prefs.get(key)};
    final oldSecrets = <String, String?>{};
    if (sections.contains('credentials')) {
      for (final key in secrets.keys) {
        oldSecrets[key] = await vault.read(key);
      }
    }
    var missing = 0;
    try {
      await store.database.transaction((txn) async {
        final tables = doc['tables'] as Map;
        final existing = await txn.query(
          'tracks',
          columns: ['id', 'title', 'artist', 'album', 'path', 'metadata'],
        );
        final ids = <String>{for (final row in existing) row['id'] as String};
        final byIdentity = <String, List<String>>{};
        for (final row in existing) {
          final track = store.trackFromRow(row);
          byIdentity.putIfAbsent(_identity(track), () => []).add(track.id);
        }
        final mapping = <String, String>{};
        Map<String, Object?> decodeRow(Map original) => {
          for (final e in original.entries)
            e.key as String: e.value is Map
                ? base64Decode(e.value['base64'] as String)
                : e.value,
        };
        if (sections.contains('library') && sections.contains('artwork')) {
          for (final row in tables['artworks'] as List) {
            final decoded = decodeRow(row as Map);
            final bytes = decoded['bytes'];
            if (bytes is! Uint8List ||
                decoded['byte_count'] != bytes.length ||
                decoded['hash'] != sha256.convert(bytes).toString()) {
              throw const FormatException('Imagem compartilhada inválida.');
            }
            await txn.insert(
              'artworks',
              decoded,
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
        var processed = 0;
        for (final original in tables['tracks'] as List) {
          if (++processed % 256 == 0) await Future<void>.delayed(Duration.zero);
          final row = decodeRow(original as Map);
          final track = store.trackFromRow(row);
          final matches = byIdentity[_identity(track)] ?? [];
          final target = ids.contains(track.id) && matches.contains(track.id)
              ? track.id
              : matches.length == 1
              ? matches.single
              : null;
          if (target != null) {
            mapping[track.id] = target;
            if (sections.contains('library')) {
              row.remove('id');
              if (!sections.contains('artwork')) {
                row.remove('cover');
                row.remove('cover_hash');
              }
              await txn.update(
                'tracks',
                row,
                where: 'id=?',
                whereArgs: [target],
              );
            }
            continue;
          }
          if (!sections.contains('library')) continue;
          if (ids.contains(track.id) || matches.length > 1) continue;
          if (!sections.contains('artwork')) {
            row.remove('cover');
            row.remove('cover_hash');
          }
          await txn.insert('tracks', row);
          ids.add(track.id);
          mapping[track.id] = track.id;
          byIdentity.putIfAbsent(_identity(track), () => []).add(track.id);
        }
        if (sections.contains('library')) {
          for (final original in tables['local_sources'] as List) {
            await txn.insert(
              'local_sources',
              decodeRow(original as Map),
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
          for (final original in tables['local_source_tracks'] as List) {
            final row = decodeRow(original as Map),
                id = mapping[original['track_id']];
            if (id == null) continue;
            row['track_id'] = id;
            await txn.insert(
              'local_source_tracks',
              row,
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
        final playlistMap = <int, int>{};
        if (sections.contains('favorites') && !sections.contains('playlists')) {
          final current = await txn.query('playlists', columns: ['id', 'name']);
          for (final row in tables['playlists'] as List) {
            final matches = current
                .where((p) => p['name'] == row['name'])
                .toList();
            if (matches.length == 1) {
              playlistMap[row['id'] as int] = matches.single['id'] as int;
            }
          }
        }
        if (sections.contains('playlists')) {
          for (final original in tables['playlists'] as List) {
            final row = decodeRow(original as Map);
            final oldId = row.remove('id') as int;
            if (!sections.contains('artwork')) row.remove('cover');
            final id = await txn.insert('playlists', row);
            playlistMap[oldId] = id;
            for (final originalEntry
                in (tables['playlist_entries'] as List).where(
                  (e) => e['playlist_id'] == oldId,
                )) {
              final entry = decodeRow(originalEntry as Map)..remove('id');
              final oldTrack = entry['track_id'] as String?;
              entry['playlist_id'] = id;
              entry['track_id'] = mapping[oldTrack];
              if (entry['track_id'] == null) {
                missing++;
                if (entry['original_reference'] is! String ||
                    (entry['original_reference'] as String).trim().isEmpty) {
                  final originalTrack = (tables['tracks'] as List)
                      .where((t) => t['id'] == oldTrack)
                      .firstOrNull;
                  entry['original_reference'] =
                      originalTrack?['path'] ?? oldTrack ?? 'unresolved';
                  entry['import_title'] ??= originalTrack?['title'];
                  entry['import_artist'] ??= originalTrack?['artist'];
                }
                entry['resolution_reason'] = 'Track not found in this library';
              }
              await txn.insert('playlist_entries', entry);
            }
          }
        }
        for (final table in ['favorites', 'history']) {
          if (!sections.contains(table)) continue;
          for (final original in tables[table] as List) {
            final row = decodeRow(original as Map)
              ..remove(table == 'history' ? 'id' : '_unused');
            final id = mapping[row['track_id']];
            if (id == null) {
              missing++;
              continue;
            }
            row['track_id'] = id;
            await txn.insert(
              table,
              row,
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
        if (sections.contains('queue')) {
          await txn.delete('queue');
          await txn.delete('playback');
          final queue =
              (tables['queue'] as List)
                  .where((r) => mapping.containsKey(r['track_id']))
                  .toList()
                ..sort(
                  (a, b) =>
                      (a['ordinal'] as int).compareTo(b['ordinal'] as int),
                );
          for (var i = 0; i < queue.length; i++) {
            await txn.insert('queue', {
              'ordinal': i,
              'track_id': mapping[queue[i]['track_id']],
            });
          }
          final playback = tables['playback'] as List;
          if (playback.isNotEmpty && queue.isNotEmpty) {
            final row = decodeRow(playback.first as Map);
            final index = queue.indexWhere(
              (r) => r['ordinal'] == row['current_index'],
            );
            row['current_index'] = index < 0 ? 0 : index;
            if (index < 0) row['position_ms'] = 0;
            await txn.insert('playback', row);
          }
        }
        if (changes['collections.favorites'] is List) {
          changes['collections.favorites'] = <String>{
            ...prefs.getStringList('collections.favorites') ?? <String>[],
            for (final v in changes['collections.favorites'] as List)
              if (!(v as String).startsWith('playlist:'))
                v
              else if (playlistMap.containsKey(int.tryParse(v.substring(9))))
                'playlist:${playlistMap[int.parse(v.substring(9))]}',
          }.toList();
        }
        for (final entry in changes.entries) {
          await AppData.writePreference(prefs, entry.key, entry.value);
        }
        if (sections.contains('credentials')) {
          for (final entry in secrets.entries) {
            await vault.write(entry.key, entry.value);
          }
        }
        await store.rebuildCatalogIndex(executor: txn);
        if ((await txn.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
          throw const FormatException("Referências de backup inválidas.");
        }
      });
    } catch (_) {
      for (final entry in previous.entries) {
        if (entry.value == null) {
          await prefs.remove(entry.key);
        } else {
          await AppData.writePreference(prefs, entry.key, entry.value!);
        }
      }
      for (final entry in oldSecrets.entries) {
        if (entry.value == null) {
          await vault.delete(entry.key);
        } else {
          await vault.write(entry.key, entry.value!);
        }
      }
      rethrow;
    }
    return missing;
  }

  static String _identity(Track track) =>
      track.itemId != null && track.driveId != null
      ? '${track.provider}|${track.provider == 'onedrive' ? track.driveId!.toLowerCase() : track.driveId}|${track.itemId}'
      : 'local|${Platform.isWindows ? track.localPath?.toLowerCase() : track.localPath}';
}

class _LimitedSink extends ByteConversionSinkBase {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > AppData.maxBytes) {
      throw const FormatException("Backup expandido excede 128 MB.");
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
