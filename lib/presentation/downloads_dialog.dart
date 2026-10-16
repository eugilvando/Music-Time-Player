import 'settings_card.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../offline/download_manager.dart';
import 'collection_browser.dart';
import 'storage_settings.dart' show storageSize;
import 'information_cards.dart';
import 'ui_language.dart';

class DownloadsDialog extends StatefulWidget {
  const DownloadsDialog({
    super.key,
    required this.manager,
    this.embedded = false,
    this.fixedCacheTab,
    this.shrinkWrap = false,
    this.overviewOnly = false,
  });
  final DownloadManager manager;
  final bool embedded;
  final bool? fixedCacheTab;
  final bool shrinkWrap, overviewOnly;
  @override
  State<DownloadsDialog> createState() => _DownloadsDialogState();
}

class _DownloadsDialogState extends State<DownloadsDialog> {
  List<Map<String, Object?>> downloads = [], cache = [], selections = [];
  Set<String> valid = {};
  bool loading = true, busy = false, again = false;
  String? error;
  bool cacheTab = false;
  DownloadManager get manager => widget.manager;
  @override
  void initState() {
    super.initState();
    cacheTab = widget.fixedCacheTab ?? false;
    manager.addListener(refresh);
    manager.cache?.addListener(refresh);
    refresh();
  }

  @override
  void dispose() {
    manager.removeListener(refresh);
    manager.cache?.removeListener(refresh);
    super.dispose();
  }

  Future<void> refresh() async {
    if (busy) {
      again = true;
      return;
    }
    busy = true;
    try {
      final tasks = await manager.store.downloadTasks(includeCovers: false);
      final cached =
          await manager.cache?.rows(validOnly: true) ??
          <Map<String, Object?>>[];
      final selected = await manager.store.offlineSelections();
      final files = <Map<String, Object?>>[
        for (final row in tasks)
          if (row['status'] == 'complete' && row['download_path'] is String)
            {
              'id': 'download:${row['id']}',
              'path': row['download_path'],
              if ((row['received'] as int) > 0) 'bytes': row['received'],
            },
        for (final row in cached)
          {
            'id': 'cache:${row['track_id']}',
            'path': row['path'],
            'bytes': row['bytes'],
          },
      ];
      final available = await compute(validOfflineFiles, files);
      if (mounted) {
        setState(() {
          downloads = tasks;
          cache = cached;
          selections = selected;
          valid = available;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Não foi possível consultar os downloads.';
        });
      }
    } finally {
      busy = false;
      if (again && mounted) {
        again = false;
        refresh();
      }
    }
  }

  Future<bool> confirm(String message) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const UiText('Remover arquivos gerenciados?'),
      content: UiText(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const UiText('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const UiText('Remover'),
        ),
      ],
    ),
  ).then((v) => v == true);
  Future<void> clearCache() async {
    if (!await confirm(
      'Remove somente cache automático. Downloads explícitos, músicas originais e a faixa em reprodução são preservados.',
    )) {
      return;
    }
    try {
      await manager.cache?.clear();
      await refresh();
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível limpar o cache.');
    }
  }

  Widget filesCard(
    String key,
    String title,
    String subtitle,
    List<Map<String, Object?>> rows, {
    bool cached = false,
  }) => SettingsCard(
    padding: 0,
    child: ExpansionTile(
      key: PageStorageKey('downloads.files.$key'),
      initiallyExpanded: true,
      title: Text(title),
      subtitle: Text(subtitle),
      children: [
        if (rows.isEmpty)
          const ListTile(title: UiText('No files'))
        else
          SizedBox(
            height: (rows.length * 60.0).clamp(60.0, 420.0),
            child: ListView.builder(
              key: PageStorageKey('downloads.scroll.$key'),
              primary: false,
              itemExtent: 60,
              itemCount: rows.length,
              itemBuilder: (_, i) =>
                  cached ? cachedTask(rows[i]) : task(rows[i]),
            ),
          ),
      ],
    ),
  );
  Widget task(Map<String, Object?> row) => ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    minVerticalPadding: 0,
    title: Text(
      row['title'] as String,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      '${row['artist']} • ${row['status']} • ${storageSize(row['received'] as int)}',
    ),
    trailing: row['status'] == 'downloading'
        ? IconButton(
            tooltip: ui(context, 'Pausar download'),
            icon: const Icon(Icons.pause),
            onPressed: () => manager.pause(row['id'] as String),
          )
        : {'failed', 'paused'}.contains(row['status'])
        ? IconButton(
            tooltip: ui(context, 'Tentar novamente'),
            icon: const Icon(Icons.refresh),
            onPressed: () => manager.retry(row['id'] as String),
          )
        : row['status'] == 'complete'
        ? IconButton(
            key: ValueKey('download.remove.${row['id']}'),
            tooltip: ui(context, 'Remover download desta faixa'),
            icon: const Icon(Icons.delete_outline),
            onPressed: manager.cache?.pinned == row['id']
                ? null
                : () async {
                    if (!await confirm(
                      'Remove esta cópia permanente de todas as seleções offline. A faixa continua no catálogo e nas playlists; originais e cache automático são preservados.',
                    )) {
                      return;
                    }
                    try {
                      await manager.removePermanentTrack(row['id'] as String);
                      await refresh();
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => error = 'Não foi possível remover o download. A faixa pode estar em uso.',
                        );
                      }
                    }
                  },
          )
        : null,
  );
  Widget cachedTask(Map<String, Object?> row) => ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    minVerticalPadding: 0,
    title: Text(row['title'] as String),
    subtitle: Text(
      '${row['artist']} • ${storageSize(row['bytes'] as int)} • ${row['last_played'] == null ? 'pré-carregada em' : 'último uso'} ${DateTime.tryParse(row['last_played'] as String? ?? row['cached_at'] as String)?.toLocal()}',
    ),
    trailing: IconButton(
      tooltip: ui(context, 'Remover do cache'),
      icon: const Icon(Icons.delete_outline),
      onPressed: manager.cache?.pinned == row['track_id']
          ? null
          : () async {
              if (await confirm(
                'Remove somente esta cópia automática; original e downloads explícitos são preservados.',
              )) {
                try {
                  await manager.cache?.remove(row['track_id'] as String);
                  await refresh();
                } catch (_) {
                  if (mounted) {
                    setState(
                      () =>
                          error = 'Não foi possível remover a cópia em cache.',
                    );
                  }
                }
              }
            },
    ),
  );
  Widget body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    final active = downloads
        .where((r) => {'pending', 'downloading'}.contains(r['status']))
        .toList();
    final complete = downloads
        .where(
          (r) =>
              r['status'] == 'complete' &&
              valid.contains('download:${r['id']}'),
        )
        .toList();
    final others = downloads
        .where((r) => {'failed', 'paused'}.contains(r['status']))
        .toList();
    final items = <Object>[
      InformationCards(
        values: {
          'Active downloads': '${active.length}',
          'Available downloads': '${complete.length}',
          'Download size': storageSize(
            complete.fold<int>(
              0,
              (sum, row) => sum + (row['received'] as num).toInt(),
            ),
          ),
          'Cached tracks':
              '${cache.where((r) => valid.contains('cache:${r['track_id']}')).length}',
          'Cache size': storageSize(
            cache
                .where((r) => valid.contains('cache:${r['track_id']}'))
                .fold<int>(
                  0,
                  (sum, row) => sum + (row['bytes'] as num).toInt(),
                ),
          ),
          'Paused or failed': '${others.length}',
        },
      ),
      const SizedBox(height: 48),
      if (error != null) UiText(error!),
      if (active.isNotEmpty || manager.cache?.current != null) ...[
        const ListTile(
          title: UiText('Downloads ativos'),
          leading: Icon(Icons.downloading),
        ),
        ...active,
        if (manager.cache?.current != null)
          ListTile(
            title: const UiText('Pré-carregamento automático'),
            subtitle: Text(
              '${manager.cache!.pending.length} ${ui(context, 'faixas aguardando cache')}',
            ),
          ),
      ],
      if (!widget.overviewOnly && widget.fixedCacheTab == null)
        DefaultTabController(
          length: 2,
          initialIndex: cacheTab ? 1 : 0,
          child: TabBar(
            key: const ValueKey('downloads.tabs'),
            onTap: (index) => setState(() => cacheTab = index == 1),
            tabs: const [
              Tab(text: 'Permanent downloads'),
              Tab(text: 'Automatic cache'),
            ],
          ),
        ),
      const SizedBox(height: 24),
      if (!widget.overviewOnly && !cacheTab) ...[
        filesCard(
          'permanent',
          ui(context, 'Arquivos baixados · permanentes'),
          ui(context, 'arquivos disponíveis. Não expiram automaticamente.'),
          complete,
        ),
        if (others.isNotEmpty) ...[
          const ListTile(title: UiText('Pausados ou com falha')),
          ...others,
        ],
        ExpansionTile(
          title: const UiText('Seleções de downloads explícitos'),
          children: [
            for (final row in selections)
              ListTile(
                title: Text('${row['selection']}'),
                subtitle: Text('${row['count']} ${ui(context, 'faixas')}'),
                trailing: IconButton(
                  tooltip: ui(context, 'Remover seleção offline'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirm(
                      'Remove a seleção. Arquivos usados por outra seleção, cache automático e músicas originais são preservados.',
                    )) {
                      await manager.unselect(row['selection'] as String);
                    }
                  },
                ),
              ),
          ],
        ),
        TextButton(
          onPressed: manager.process,
          child: const UiText('Processar pendentes'),
        ),
      ] else if (!widget.overviewOnly) ...[
        ListTile(
          title: const UiText('Cache automático · 30 dias'),
          subtitle: Text(
            '${cache.where((r) => valid.contains('cache:${r['track_id']}')).length} ${ui(context, 'arquivos completos. Removidos após 30 dias sem uso ou ao atingir o limite.')}',
          ),
          leading: const Icon(Icons.cached),
          trailing: TextButton(
            onPressed: clearCache,
            child: const UiText('Limpar'),
          ),
        ),
        filesCard(
          'cache',
          ui(context, 'Automatic cache'),
          ui(context, 'Available offline'),
          cache.where((r) => valid.contains('cache:${r['track_id']}')).toList(),
          cached: true,
        ),
      ],
    ];
    return ListView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(32),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is Widget) {
          if (item is SettingsCard ||
              item is InformationCards ||
              item is SizedBox ||
              item is DefaultTabController ||
              item is UiText) {
            return item;
          }
          return SettingsCard(padding: 0, child: item);
        }
        final row = item as Map<String, Object?>;
        return SettingsCard(
          padding: 0,
          child: row.containsKey('last_played') ? cachedTask(row) : task(row),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? body()
      : AlertDialog(
          title: const UiText('Downloads'),
          content: SizedBox(width: 660, height: 560, child: body()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const UiText('Fechar'),
            ),
          ],
        );
}
