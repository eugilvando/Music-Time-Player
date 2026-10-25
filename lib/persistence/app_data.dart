import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../sources/microsoft_auth.dart';
import '../sources/microsoft_sources.dart';
import '../settings/equalizer_presets.dart';
import '../settings/player_bar_layout.dart';
import 'library_store.dart';

class AppData {
  static const tables = [
    'artworks',
    'tracks',
    'local_sources',
    'local_source_tracks',
    'playlists',
    'playlist_entries',
    'favorites',
    'history',
    'playback',
    'queue',
  ];
  static const transientTables = [
    'catalog_search',
    'cloud_sources',
    'cloud_sync_seen',
    'media_cache',
    'offline_memberships',
    'downloads',
    'sync_cursors',
    'scrobble_outbox',
  ];
  static const maxBytes = 128 * 1024 * 1024;
  static bool preferenceAllowed(String key) =>
      key == 'theme' ||
      key == 'accent' ||
      key.startsWith('visual.') ||
      key.startsWith('collections.') ||
      key.startsWith('lyrics.') ||
      key.startsWith('windows.');
  static Map<String, Object> preferences(SharedPreferences prefs) => {
    for (final key in prefs.getKeys().where(preferenceAllowed))
      key: prefs.get(key)!,
  };

  static Future<String> backup(
    LibraryStore store,
    SharedPreferences prefs,
  ) async {
    final rows = await store.database.transaction(
      (txn) async => {
        for (final table in tables)
          table: [
            for (final row in await txn.query(table))
              {
                for (final entry in row.entries)
                  entry.key: entry.value is Uint8List
                      ? {'base64': base64Encode(entry.value as Uint8List)}
                      : entry.value,
              },
          ],
      },
    );
    final content = jsonEncode({
      'format': 'music_time_backup',
      'version': 1,
      'schema': 17,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': rows,
      'preferences': preferences(prefs),
    });
    if (utf8.encode(content).length > maxBytes) {
      throw const FormatException('Backup maior que 128 MB.');
    }
    return content;
  }

  static Map<String, dynamic> parse(String content) {
    if (utf8.encode(content).length > maxBytes) {
      throw const FormatException('Backup maior que 128 MB.');
    }
    final doc = jsonDecode(content);
    if (doc is! Map<String, dynamic> ||
        doc['format'] != 'music_time_backup' ||
        doc['version'] != 1 ||
        !{6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 17}.contains(doc['schema']) ||
        doc['tables'] is! Map ||
        doc['preferences'] is! Map) {
      throw const FormatException('Formato ou versão de backup incompatível.');
    }
    final rows = doc['tables'] as Map;
    if ((doc['schema'] as int) < 15 && !rows.containsKey('artworks')) {
      rows['artworks'] = <dynamic>[];
    }
    if (rows.keys.toSet().difference(tables.toSet()).isNotEmpty ||
        tables.any((table) => rows[table] is! List)) {
      throw const FormatException('Tabelas inválidas.');
    }
    for (final table in tables) {
      for (final row in rows[table] as List) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Registro inválido.');
        }
        for (final entry in row.entries) {
          final value = entry.value;
          if ((entry.key == 'cover' ||
                  table == 'artworks' && entry.key == 'bytes') &&
              value is Map &&
              value.keys.length == 1 &&
              value['base64'] is String) {
            base64Decode(value['base64'] as String);
          } else if (value != null && value is! String && value is! num) {
            throw const FormatException('Valor inválido.');
          }
        }
      }
    }
    for (final entry in (doc['preferences'] as Map).entries) {
      if (entry.key is! String ||
          !preferenceAllowed(entry.key as String) ||
          !validPreference(entry.value) ||
          !validPreferenceType(entry.key as String, entry.value)) {
        throw const FormatException('Preferência inválida ou privada.');
      }
    }
    return doc;
  }

  static bool validPreference(Object? value) =>
      value is bool ||
      value is String ||
      value is int ||
      value is double && value.isFinite ||
      value is List && value.every((v) => v is String);

  static bool validPreferenceType(String key, Object? value) {
    if (key.startsWith('visual.details_columns_')) {
      return value is List &&
          value.every((v) => v is String && int.tryParse(v) != null);
    }
    if (key == 'visual.bar_item_order' || key == 'visual.bar_items') {
      return validPlayerBarItems(value);
    }
    if (key == 'theme') return value is String;
    if (key == 'accent' || key.startsWith('lyrics.offset.')) {
      return value is int;
    }
    if (key.startsWith('windows.')) return value is bool;
    if (key == 'collections.favorites' ||
        key == 'visual.home_sections' ||
        key == 'visual.home_sections_before_0_7_3' ||
        key == 'visual.home_mix_types' ||
        key == 'visual.songs_columns' ||
        key == 'visual.bar_fields' ||
        key.endsWith('_columns')) {
      return value is List && value.every((v) => v is String);
    }
    if (!key.startsWith('visual.')) return true;
    final name = key.substring(7);
    if (name.startsWith('home_count_')) {
      return value is double && value >= 1 && value <= 100;
    }
    if (name == 'home_modes') {
      if (value is! String) return false;
      final modes = jsonDecode(value);
      return modes is Map && modes.values.every((v) => v is String);
    }
    if (name.startsWith('font_') || name == 'lyrics_font') {
      return value is double && value >= 10 && value <= 40;
    }
    const ranges = {
      'queue_panel_width': (280.0, 960.0),
      'lyrics_panel_width': (280.0, 960.0),
      'home_section_spacing': (0.0, 96.0),
      'bar_icon_spacing': (0.0, 24.0),
      'lyrics_spacing': (1.0, 2.0),
      'cover_scale': (.7, 1.8),
      'background_intensity': (.05, .45),
      'home_count': (4.0, 24.0),
      'home_mix_size': (1.0, 100.0),
      'artist_mix_size': (1.0, 500.0),
      'artist_radio_size': (1.0, 500.0),
      'cache_gb': (1.0, 100.0),
      'prefetch_count': (0.0, 20.0),
      'continuous_count': (1.0, 100.0),
      'catalog_cover_size': (96.0, 360.0),
    };
    if (ranges.containsKey(name)) {
      final range = ranges[name]!;
      return value is double && value >= range.$1 && value <= range.$2;
    }
    if (name == 'eq_presets') {
      return value is String && validEqualizerPresets(jsonDecode(value));
    }
    if (name == 'eq_preset') return value is String;
    if (name.startsWith('eq_') && name != 'eq_enabled') {
      return value is double && value >= -12 && value <= 12;
    }
    const flags = {
      'home_layout_0_7_3',
      'artist_radio_1_2',
      'system_accent',
      'eq_enabled',
      'cache_enabled',
      'smart_play',
      'offline_only',
      'merge_artists',
      'merge_albums',
      'sidebar_collapsed',
      'artist_photos',
      'artist_biographies',
      'online_lyrics',
      'catalog_dense',
      'songs_descending',
      'playlists_descending',
      'show_queue',
      'additional_info',
      'animations',
      'reduce_motion',
      'secondary_controls',
      'show_volume',
      'show_progress',
      'show_times',
      'lyrics_auto_scroll',
    };
    if (flags.contains(name) ||
        name.endsWith('_grid') ||
        name.endsWith('_controls_expanded')) {
      return value is bool;
    }
    return value is String;
  }

  static Future<void> writePreference(
    SharedPreferences prefs,
    String key,
    Object value,
  ) async {
    final ok = switch (value) {
      bool v => await prefs.setBool(key, v),
      String v => await prefs.setString(key, v),
      int v => await prefs.setInt(key, v),
      double v => await prefs.setDouble(key, v),
      List v => await prefs.setStringList(key, v.cast<String>()),
      _ => false,
    };
    if (!ok) throw StateError('Não foi possível salvar preferências.');
  }

  static Future<void> replacePreferences(
    SharedPreferences prefs,
    Map values,
  ) async {
    for (final key in prefs.getKeys().where(preferenceAllowed).toList()) {
      if (!await prefs.remove(key)) {
        throw StateError('Falha ao limpar preferências.');
      }
    }
    for (final entry in values.entries) {
      await writePreference(prefs, entry.key as String, entry.value as Object);
    }
  }

  static Future<void> restore(
    LibraryStore store,
    SharedPreferences prefs,
    String content,
  ) async {
    final doc = parse(content), previous = preferences(prefs);
    try {
      await store.database.transaction((txn) async {
        await txn.execute('DROP TABLE IF EXISTS lastfm_profile_cache');
        await txn.execute('DROP TABLE IF EXISTS artist_similarity_cache');
        for (final table in [...transientTables, ...tables.reversed]) {
          await txn.delete(table);
        }
        for (final table in tables) {
          final columns = {
            for (final column in await txn.rawQuery(
              'PRAGMA table_info($table)',
            ))
              column['name']: column['type'],
          };
          for (final original in doc['tables'][table] as List) {
            final row = Map<String, Object?>.from(original as Map);
            if (row.keys.any((key) => !columns.containsKey(key))) {
              throw const FormatException('Coluna desconhecida.');
            }
            for (final key in ['cover', if (table == 'artworks') 'bytes']) {
              if (row[key] is Map) {
                row[key] = base64Decode((row[key] as Map)['base64'] as String);
              }
            }
            for (final entry in row.entries) {
              final value = entry.value;
              if (value == null) continue;
              final valid = switch (columns[entry.key]) {
                'TEXT' => value is String,
                'INTEGER' => value is int,
                'REAL' => value is num && value.isFinite,
                'BLOB' => value is Uint8List,
                _ => false,
              };
              if (!valid) {
                throw const FormatException('Tipo de coluna inválido.');
              }
            }
            if (table == 'playlist_entries' &&
                row['track_id'] == null &&
                (row['original_reference'] is! String ||
                    (row['original_reference'] as String).isEmpty)) {
              throw const FormatException(
                'Unresolved playlist item without reference.',
              );
            }
            if (table == 'tracks') {
              final metadata = jsonDecode(row['metadata'] as String? ?? '{}');
              if (metadata is! Map) {
                throw const FormatException('Metadados inválidos.');
              }
              store.trackFromRow(row); // Validate values before committing.
            }
            if (table == 'artworks') {
              final bytes = row['bytes'];
              if (bytes is! Uint8List ||
                  row['byte_count'] != bytes.length ||
                  row['hash'] != sha256.convert(bytes).toString()) {
                throw const FormatException('Imagem compartilhada inválida.');
              }
            }
            await txn.insert(table, row);
          }
        }
        if ((await txn.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
          throw const FormatException('Referências inválidas.');
        }
        await store.rebuildCatalogIndex(executor: txn);
        await replacePreferences(prefs, doc['preferences'] as Map);
      });
    } catch (_) {
      await replacePreferences(prefs, previous);
      rethrow;
    }
  }

  static File requestFile(Directory root) =>
      File(path.join(root.path, 'maintenance-request.json'));
  static Future<void> stage(Directory root, {String? backup}) async {
    if (backup != null) parse(backup);
    await root.create(recursive: true);
    final temporary = File(
      '${requestFile(root).path}.${secureRandomString()}.tmp',
    );
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'action': backup == null ? 'reset' : 'restore',
        if (backup != null) 'backup': backup,
      }),
      flush: true,
    );
    await temporary.rename(requestFile(root).path);
  }

  static Future<String?> applyPending(
    Directory root,
    LibraryStore store,
    SharedPreferences prefs,
    SecretVault vault,
  ) async {
    final file = requestFile(root);
    if (!await file.exists()) return null;
    try {
      if (await file.length() > maxBytes * 2) {
        throw const FormatException('Solicitação inválida.');
      }
      final doc = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (doc['version'] != 1) {
        throw const FormatException('Solicitação incompatível.');
      }
      if (doc['action'] == 'restore' && doc['backup'] is String) {
        await restore(store, prefs, doc['backup'] as String);
        return 'Backup restaurado. Reconecte fontes quando necessário; a reprodução permanece pausada.';
      }
      if (doc['action'] != 'reset') {
        throw const FormatException('Ação inválida.');
      }
      // Never delete paths from source metadata or traverse user music folders.
      String canonical(String value) => Platform.isWindows
          ? path.normalize(path.absolute(value)).toLowerCase()
          : path.normalize(path.absolute(value));
      final originals = (await store.database.query(
        'tracks',
        columns: ['path'],
      )).map((r) => canonical(r['path'] as String)).toSet();
      for (final key in [
        for (final row in jsonDecode(
          prefs.getString('additional_sources') ?? '[]',
        ) as List)
          if (row is Map &&
              row['id'] is String &&
              RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(row['id'] as String))
            'source.${row['id']}.session',
        'microsoft.session',
        for (final id
            in prefs.getStringList(microsoftSourcesPreference) ??
                const <String>[])
          if (validMicrosoftSourceId(id)) microsoftSourceSessionKey(id),
        'lastfm.session',
        'lastfm.api_key',
        'lastfm.api_secret',
      ]) {
        await vault.delete(key);
      }
      await store.database.transaction((txn) async {
        await txn.execute('DROP TABLE IF EXISTS lastfm_profile_cache');
        await txn.execute('DROP TABLE IF EXISTS artist_similarity_cache');
        for (final table in [...transientTables, ...tables.reversed]) {
          await txn.delete(table);
        }
        await txn.delete('sqlite_sequence');
      });
      if (!await prefs.clear()) {
        throw StateError('Falha ao limpar preferências.');
      }
      for (final folder in [
        'offline',
        'media-cache',
        'artist-photos',
        'artist-custom',
        'lyrics-cache',
        'artist-biographies',
      ]) {
        final directory = Directory(path.join(root.path, folder));
        if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        await for (final entry in directory.list(followLinks: false)) {
          if (await FileSystemEntity.type(entry.path, followLinks: false) !=
              FileSystemEntityType.file) {
            continue;
          }
          if (!RegExp(
            {'lyrics-cache', 'artist-biographies'}.contains(folder)
                ? r'^[a-f0-9]{64}\.txt(\.tmp)?$'
                : !{'artist-photos', 'artist-custom'}.contains(folder)
                ? r'^[a-f0-9]{64}\.audio(\.part)?$'
                : r'^[a-f0-9]{64}\.jpg$',
          ).hasMatch(path.basename(entry.path))) {
            continue;
          }
          if (!originals.contains(canonical(entry.path))) {
            await File(entry.path).delete();
          }
        }
      }
      await for (final entry in root.list(followLinks: false)) {
        if (await FileSystemEntity.type(entry.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        if (RegExp(
              r'^[a-f0-9]{64}(-([a-f0-9]{64}|fallback))?\.(cover|png|jpg)$',
            ).hasMatch(path.basename(entry.path)) ||
            path.basename(entry.path) == 'windows_diagnostics.log') {
          if (!originals.contains(canonical(entry.path))) {
            await File(entry.path).delete();
          }
        }
      }
      await store.database.execute('VACUUM');
      return 'Music Time resetado. Adicione suas fontes para começar novamente.';
    } finally {
      await file.delete();
    }
  }
}
