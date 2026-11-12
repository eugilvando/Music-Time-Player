import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sources/microsoft_auth.dart';
import 'app_data.dart';
import 'backup_archive.dart';
import 'library_store.dart';

/// Framed, optionally authenticated archive. Only one image is decoded at a time.
/// Legacy archives remain readable. No plaintext credential staging is used.
class BackupFile {
  static const magic = 'MTBACKUP3\n';
  static const maxFileBytes = 16 * 1024 * 1024 * 1024;
  static const maxImageBytes = 32 * 1024 * 1024;
  static const maxFrameBytes = 128 * 1024 * 1024 + 4096;

  static Future<bool> encrypted(File file) async {
    final handle = await file.open();
    try {
      final prefix = await handle.read(magic.length);
      if (utf8.decode(prefix, allowMalformed: true) == magic) {
        return (await _header(handle)).$1['encrypted'] == true;
      }
      return BackupArchive.encrypted(prefix);
    } finally {
      await handle.close();
    }
  }

  static Future<void> write(
    File file,
    LibraryStore store,
    SharedPreferences prefs,
    SecretVault vault,
    Set<String> sections, {
    String? password,
    void Function(String)? onProgress,
  }) async {
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    RandomAccessFile? output;
    try {
      if (!sections.contains('artwork')) {
        onProgress?.call('Preparando catálogo e preferências…');
        final bytes = await BackupArchive.create(
          store,
          prefs,
          vault,
          sections,
          password: password,
        );
        await temp.writeAsBytes(bytes, flush: true);
      } else {
        if (!sections.contains('library') && !sections.contains('playlists')) {
          throw const FormatException(
            'Selecione biblioteca ou playlists para incluir capas.',
          );
        }
        final salt = SecretKeyData.random(length: 16).bytes;
        final header = utf8.encode(
          jsonEncode({
            'encrypted': password != null,
            'salt': base64Encode(salt),
            'iterations': BackupArchive.iterations,
          }),
        );
        onProgress?.call('Preparando proteção do backup…');
        final key = password == null ? null : await _key(password, salt);
        output = await temp.open(mode: FileMode.write);
        await output.writeFrom(ascii.encode(magic));
        await output.writeFrom(_length(header.length));
        await output.writeFrom(header);
        var count = 0;
        Future<void> frame(List<int> bytes) async {
          final index = count++;
          final encoded = await _encodeAsync(bytes, key, header, index);
          if (encoded.length > maxFrameBytes) {
            throw const FormatException(
              'Uma imagem excede o limite do backup.',
            );
          }
          await output!.writeFrom(_length(encoded.length));
          await output!.writeFrom(encoded);
          if (await output!.position() > maxFileBytes) {
            throw const FormatException('Backup excede 16 GB.');
          }
        }

        await store.database.transaction((txn) async {
          onProgress?.call('Preparando catálogo e preferências…');
          final base = await BackupArchive.create(
            store,
            prefs,
            vault,
            sections.difference({'artwork'}),
            password: password,
            executor: txn,
            retainArtworkReferences: true,
          );
          await frame(
            _join([
              Uint8List.fromList([0]),
              base,
            ]),
          );
          final queries = <String, String>{
            if (sections.contains('library')) 'artworks': "hash IN (SELECT cover_hash FROM tracks UNION SELECT json_extract(metadata,'\$.userOverride.catalogCoverHash') FROM tracks)",
            if (sections.contains('library')) 'tracks': 'cover IS NOT NULL',
            if (sections.contains('playlists'))
              'playlists': 'cover IS NOT NULL',
          };
          var done = 0;
          for (final entry in queries.entries) {
            final table = entry.key;
            final id = table == 'artworks' ? 'hash' : 'id';
            final blob = table == 'artworks' ? 'bytes' : 'cover';
            // IDs only: avoid retaining the collection's images in memory.
            final ids = await txn.query(
              table,
              columns: [id],
              where: entry.value,
            );
            for (final identity in ids) {
              final rows = await txn.query(
                table,
                columns: table == 'artworks' ? null : ['id', 'cover'],
                where: '$id=?',
                whereArgs: [identity[id]],
              );
              final row = rows.single;
              final bytes = row[blob] as Uint8List;
              if (bytes.length > maxImageBytes) {
                throw const FormatException(
                  'Uma capa excede 32 MB. Exporte sem capas ou substitua essa imagem.',
                );
              }
              final meta = utf8.encode(
                jsonEncode({
                  'table': table,
                  'row': {
                    for (final cell in row.entries)
                      if (cell.key != blob) cell.key: cell.value,
                  },
                }),
              );
              await frame(
                _join([
                  Uint8List.fromList([1]),
                  _length(meta.length),
                  meta,
                  bytes,
                ]),
              );
              onProgress?.call(
                'Salvando capas: ${++done} (${(await output!.position() / 1048576).toStringAsFixed(1)} MB)…',
              );
            }
          }
          await frame([2, ..._length(count)]);
        });
        await output.flush();
        await output.close();
        output = null;
      }
      onProgress?.call('Concluindo arquivo…');
      await temp.rename(file.path);
    } finally {
      await output?.close();
      if (await temp.exists()) await temp.delete();
    }
  }

  static Future<Map<String, dynamic>> read(
    File file, {
    String? password,
    void Function(String)? onProgress,
  }) async {
    if (await file.length() > maxFileBytes) {
      throw const FormatException('Backup excede 16 GB.');
    }
    final handle = await file.open();
    try {
      final prefix = await handle.read(magic.length);
      if (utf8.decode(prefix, allowMalformed: true) != magic) {
        if (await file.length() > AppData.maxBytes) {
          throw const FormatException('Backup antigo excede 128 MB.');
        }
        return await BackupArchive.read(
          await file.readAsBytes(),
          password: password,
        );
      }
      final (config, header) = await _header(handle);
      final protected = config['encrypted'] == true;
      if (protected && password == null) {
        throw const FormatException('Informe a senha do backup.');
      }
      final key = protected
          ? await _key(password!, base64Decode(config['salt'] as String))
          : null;
      final source = _Images(file, header, key);
      Map<String, dynamic>? archive;
      var index = 0;
      while (true) {
        final offset = await handle.position();
        final bytes = await _frame(handle, key, header, index);
        if (bytes.isEmpty) {
          throw const FormatException('Registro de backup inválido.');
        }
        if (index == 0) {
          if (bytes[0] != 0 ||
              BackupArchive.encrypted(bytes.sublist(1)) != protected) {
            throw const FormatException('Catálogo de backup inválido.');
          }
          archive = await BackupArchive.read(
            Uint8List.fromList(bytes.sublist(1)),
            password: password,
          );
          final sections = (archive['sections'] as List).cast<String>();
          if (!sections.any({'library', 'playlists'}.contains)) {
            throw const FormatException('Seções de backup inválidas.');
          }
          sections.add('artwork');
          archive['sections'] = sections;
        } else if (bytes[0] == 2) {
          if (bytes.length != 5 ||
              _integer(bytes.sublist(1)) != index ||
              await handle.position() != await handle.length()) {
            throw const FormatException(
              'Backup incompleto ou com registros extras.',
            );
          }
          archive!['_images'] = source;
          return archive;
        } else {
          final (table, row) = await _decodeImage(bytes);
          final id = row[table == 'artworks' ? 'hash' : 'id'];
          final name = '$table/$id';
          if (source.entries.containsKey(name) ||
              source.entries.length >= 500000) {
            throw const FormatException('Capas duplicadas ou limite excedido.');
          }
          source.entries[name] = (offset, index);
          onProgress?.call('Verificando capas: ${source.entries.length}…');
        }
        index++;
      }
    } finally {
      await handle.close();
    }
  }

  static Uint8List _join(List<List<int>> parts) {
    final builder = BytesBuilder(copy: false);
    for (final part in parts) {
      builder.add(part);
    }
    return builder.takeBytes();
  }

  static Uint8List _length(int n) =>
      (ByteData(4)..setUint32(0, n)).buffer.asUint8List();
  static int _integer(List<int> bytes) =>
      ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0);
  static Future<Uint8List> _exact(RandomAccessFile f, int n) async {
    final bytes = await f.read(n);
    if (bytes.length != n) throw const FormatException('Backup incompleto.');
    return bytes;
  }

  static Future<(Map<String, dynamic>, List<int>)> _header(
    RandomAccessFile f,
  ) async {
    final size = _integer(await _exact(f, 4));
    if (size > 1024) throw const FormatException('Cabeçalho inválido.');
    final bytes = await _exact(f, size);
    final config = jsonDecode(utf8.decode(bytes));
    if (config is! Map<String, dynamic> ||
        config['encrypted'] is! bool ||
        config['iterations'] != BackupArchive.iterations ||
        config['salt'] is! String ||
        base64Decode(config['salt']).length != 16) {
      throw const FormatException('Cabeçalho inválido.');
    }
    return (config, bytes);
  }

  static Future<List<int>> _key(String password, List<int> salt) => Isolate.run(
    () async =>
        (await Pbkdf2(
              macAlgorithm: Hmac.sha256(),
              iterations: BackupArchive.iterations,
              bits: 256,
            ).deriveKey(
              secretKey: SecretKey(utf8.encode(password)),
              nonce: salt,
            ))
            .extractBytes(),
  );
  static Future<List<int>> _encodeAsync(
    List<int> bytes,
    List<int>? key,
    List<int> header,
    int index,
  ) => Isolate.run(() => _encode(bytes, key, header, index));
  static Future<(String, Map<String, Object?>)> _decodeImage(List<int> bytes) =>
      Isolate.run(() => _image(bytes));

  static Future<List<int>> _encode(
    List<int> bytes,
    List<int>? key,
    List<int> header,
    int index,
  ) async {
    if (key == null) return _join([sha256.convert(bytes).bytes, bytes]);
    final box = await AesGcm.with256bits().encrypt(
      bytes,
      secretKey: SecretKey(key),
      aad: [...header, ..._length(index)],
    );
    return _join([box.nonce, box.mac.bytes, box.cipherText]);
  }

  static Future<Uint8List> _frame(
    RandomAccessFile f,
    List<int>? key,
    List<int> header,
    int index,
  ) async {
    final length = _integer(await _exact(f, 4));
    if (length < 28 || length > maxFrameBytes) {
      throw const FormatException('Registro de backup inválido.');
    }
    final encoded = await _exact(f, length);
    return Isolate.run(() async {
      if (key == null) {
        if (encoded.length < 32) {
          throw const FormatException('Registro inválido.');
        }
        final bytes = encoded.sublist(32);
        if (base64Encode(sha256.convert(bytes).bytes) !=
            base64Encode(encoded.sublist(0, 32))) {
          throw const FormatException('Backup danificado.');
        }
        return bytes;
      }
      try {
        return Uint8List.fromList(
          await AesGcm.with256bits().decrypt(
            SecretBox(
              encoded.sublist(28),
              nonce: encoded.sublist(0, 12),
              mac: Mac(encoded.sublist(12, 28)),
            ),
            secretKey: SecretKey(key),
            aad: [...header, ..._length(index)],
          ),
        );
      } on SecretBoxAuthenticationError {
        throw const FormatException('Senha incorreta ou backup danificado.');
      }
    });
  }

  static (String, Map<String, Object?>) _image(List<int> bytes) {
    if (bytes.length < 5 || bytes[0] != 1) {
      throw const FormatException('Capa inválida.');
    }
    final length = _integer(bytes.sublist(1, 5));
    if (length > 8192 ||
        length + 5 > bytes.length ||
        bytes.length - length - 5 > maxImageBytes) {
      throw const FormatException('Capa inválida.');
    }
    final meta = jsonDecode(utf8.decode(bytes.sublist(5, 5 + length)));
    if (meta is! Map ||
        !{'artworks', 'tracks', 'playlists'}.contains(meta['table']) ||
        meta['row'] is! Map) {
      throw const FormatException('Capa inválida.');
    }
    final table = meta['table'] as String;
    final row = Map<String, Object?>.from(meta['row']);
    final data = Uint8List.fromList(bytes.sublist(5 + length));
    if (table == 'artworks') {
      if (row['hash'] != sha256.convert(data).toString() ||
          row['byte_count'] != data.length) {
        throw const FormatException('Imagem compartilhada inválida.');
      }
      row['bytes'] = data;
    } else {
      if (table == 'tracks' ? row['id'] is! String : row['id'] is! int) {
        throw const FormatException('Referência de capa inválida.');
      }
      row['cover'] = data;
    }
    return (table, row);
  }
}

class _Images implements BackupArtworkSource {
  _Images(this.file, this.header, this.key);
  final File file;
  final List<int> header;
  final List<int>? key;
  final entries = <String, (int, int)>{};
  Future<Map<String, Object?>> _load(String name) async {
    final (offset, index) = entries[name]!;
    final handle = await file.open();
    try {
      await handle.setPosition(offset);
      final bytes = await BackupFile._frame(handle, key, header, index);
      final (table, row) = await BackupFile._decodeImage(bytes);
      if ('$table/${row[table == 'artworks' ? 'hash' : 'id']}' != name) {
        throw const FormatException('O backup foi alterado durante a leitura.');
      }
      return row;
    } finally {
      await handle.close();
    }
  }

  @override
  Stream<Map<String, Object?>> artworks() async* {
    for (final name in entries.keys.where((e) => e.startsWith('artworks/'))) {
      yield await _load(name);
    }
  }

  @override
  Future<Uint8List?> cover(String table, Object id) async =>
      entries.containsKey('$table/$id')
      ? (await _load('$table/$id'))['cover'] as Uint8List
      : null;
}
