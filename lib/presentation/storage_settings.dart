import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../offline/download_manager.dart';
import 'artist_portrait.dart';
import 'ui_language.dart';
import 'information_cards.dart';

String storageSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

/// Only regular files in a dedicated cache directory; never follows links.
Future<int> ownedCacheFiles(
  Directory root, {
  bool clear = false,
  required bool Function(String) accepts,
}) async {
  if (await FileSystemEntity.type(root.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    return 0;
  }
  var bytes = 0;
  await for (final entry in root.list(followLinks: false)) {
    if (entry is! File || !accepts(path.basename(entry.path))) continue;
    try {
      bytes += await entry.length();
      if (clear) await entry.delete();
    } on FileSystemException {
      /* File may have disappeared during the scan. */
    }
  }
  return bytes;
}

class StorageSettings extends StatefulWidget {
  const StorageSettings({
    super.key,
    required this.manager,
    this.showOverview = true,
    this.showCleanup = true,
  });
  final bool showOverview, showCleanup;
  final DownloadManager manager;
  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  Map<String, int>? sizes;
  String? error;
  bool busy = false;
  bool photo(String name) =>
      RegExp(r'^[a-f0-9]{64}\.jpg(\.tmp)?$').hasMatch(name);
  bool offline(String name) => RegExp(r'^[a-f0-9]{64}\.audio$').hasMatch(name);
  bool partial(String name) =>
      RegExp(r'^[a-f0-9]{64}\.audio\.part$').hasMatch(name);
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final support = await getApplicationSupportDirectory();
      final root = await widget.manager.dataDirectory();
      final coverBytes = await widget.manager.store.artwork.storedBytes();
      final db = File(widget.manager.store.database.path);
      final data = {
        'Lyrics cache': await ownedCacheFiles(
          Directory(path.join(support.path, 'lyrics-cache')),
          accepts: (name) =>
              RegExp(r'^[a-f0-9]{64}\.txt(\.tmp)?$').hasMatch(name),
        ),
        'Artist biographies': await ownedCacheFiles(
          Directory(path.join(support.path, 'artist-biographies')),
          accepts: (name) => RegExp(r'^[a-f0-9]{64}\.txt$').hasMatch(name),
        ),
        'Fotos de artistas': await ownedCacheFiles(
          Directory(path.join(support.path, 'artist-photos')),
          accepts: photo,
        ),
        'Downloads de áudio': await ownedCacheFiles(root, accepts: offline),
        'Downloads incompletos': await ownedCacheFiles(root, accepts: partial),
        'Banco da biblioteca':
            (await db.exists() ? await db.length() : 0) +
            (await File('${db.path}-wal').exists()
                ? await File('${db.path}-wal').length()
                : 0) +
            (await File('${db.path}-shm').exists()
                ? await File('${db.path}-shm').length()
                : 0),
        'Cache automático de áudio': widget.manager.cache == null
            ? 0
            : await ownedCacheFiles(
                await widget.manager.cache!.root(),
                accepts: (name) => offline(name) || partial(name),
              ),
        'Imagens personalizadas': await ownedCacheFiles(
          Directory(path.join(support.path, 'artist-custom')),
          accepts: photo,
        ),
        'Capas no catálogo': coverBytes,
      };
      if (mounted) {
        setState(() {
          sizes = data;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível calcular o armazenamento. Tente novamente.',
        );
      }
    }
  }

  Future<void> clean(bool photos) async {
    if (busy || widget.manager.running) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: UiText(
          photos
              ? 'Limpar fotos de artistas?'
              : 'Limpar downloads incompletos?',
        ),
        content: UiText(
          photos
              ? 'As fotos serão buscadas novamente quando necessário. As músicas, capas do catálogo e downloads offline são preservados.'
              : 'Remove apenas arquivos temporários de downloads interrompidos. Downloads concluídos e músicas originais são preservados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const UiText('Limpar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || widget.manager.running) return;
    setState(() => busy = true);
    try {
      if (photos) {
        final support = await getApplicationSupportDirectory();
        await ArtistPhotos.instance.clearDiskCache(() async {
          await ownedCacheFiles(
            Directory(path.join(support.path, 'artist-photos')),
            accepts: photo,
            clear: true,
          );
        });
      } else {
        await widget.manager.clearIncomplete();
      }
      await refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Não foi possível concluir a limpeza. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const UiText('Armazenamento e cache'),
    initiallyExpanded: MediaQuery.sizeOf(context).height > 650,
    children: [
      TextButton(
        onPressed: busy ? null : refresh,
        child: const UiText('Atualizar tamanhos'),
      ),
      if (error != null) UiText(error!),
      if (sizes == null && error == null) const LinearProgressIndicator(),
      if (sizes != null && widget.showOverview) ...[
        InformationCards(
          values: {
            for (final entry in sizes!.entries)
              ui(context, entry.key): storageSize(entry.value),
          },
        ),
        const SizedBox(height: 48),
        for (final entry in sizes!.entries.where(
          (e) => e.key != 'Capas no catálogo',
        ))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${ui(context, entry.key)} · ${storageSize(entry.value)}'),
                const SizedBox(height: 8),
                Semantics(
                  label: ui(context, entry.key),
                  value: storageSize(entry.value),
                  child: LinearProgressIndicator(
                    minHeight: 12,
                    borderRadius: BorderRadius.circular(6),
                    value:
                        entry.value /
                        (sizes!.entries
                                .where((e) => e.key != 'Capas no catálogo')
                                .fold<int>(0, (sum, e) => sum + e.value))
                            .clamp(1, 1 << 62),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
      ],
      const UiText(
        'Capas fazem parte do banco; seu tamanho está incluído no banco da biblioteca. Downloads explícitos são removidos em Downloads; cache automático é separado. Arquivos originais e credenciais não são limpos.',
      ),
      if (widget.showCleanup)
        Wrap(
          spacing: 8,
          children: [
            if (widget.manager.cache != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final accepted = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const UiText('Limpar cache de áudio?'),
                            content: const UiText(
                              'Downloads explícitos, músicas originais e faixa em reprodução são preservados.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const UiText('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const UiText('Limpar'),
                              ),
                            ],
                          ),
                        );
                        if (accepted == true) {
                          try {
                            await widget.manager.cache!.clear();
                            await refresh();
                          } catch (_) {
                            if (mounted) {
                              setState(
                                () =>
                                    error = 'Não foi possível limpar o cache.',
                              );
                            }
                          }
                        }
                      },
                child: const UiText('Limpar cache de áudio'),
              ),

            TextButton(
              onPressed: busy || widget.manager.running
                  ? null
                  : () => clean(true),
              child: const UiText('Limpar fotos de artistas'),
            ),
            TextButton(
              onPressed: busy || widget.manager.running
                  ? null
                  : () => clean(false),
              child: const UiText('Limpar downloads incompletos'),
            ),
          ],
        ),
    ],
  );
}
