import 'design_icon.dart';
import 'ui_language.dart';
import 'additional_source_settings.dart' show sourceRemovalWarning;

import 'package:flutter/material.dart';

import 'dart:convert';

import '../library/local_source_sync.dart';

import '../persistence/library_store.dart';

class LocalSourcesPanel extends StatefulWidget {
  const LocalSourcesPanel({
    super.key,
    required this.store,
    required this.onAddFiles,
    required this.onAddFolder,
    required this.onChanged,
    required this.onSync,
    required this.sync,
  });
  final LibraryStore store;
  final LocalSourceSync sync;
  final Future<void> Function(String) onSync;
  final Future<void> Function() onAddFiles, onAddFolder, onChanged;
  @override
  State<LocalSourcesPanel> createState() => _LocalSourcesPanelState();
}

class _LocalSourcesPanelState extends State<LocalSourcesPanel> {
  List<Map<String, Object?>> sources = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final values = await widget.store.localSources();
    if (mounted) setState(() => sources = values);
  }

  Future<void> run(
    Future<void> Function() action, {
    bool syncing = false,
  }) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (syncing && widget.sync.error != null) error = widget.sync.error;
      await refresh();
      await widget.onChanged();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is StateError
              ? failure.message.toString()
              : 'Não foi possível atualizar as fontes.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: const UiText('Remover fonte local?'),
        content: const UiText(sourceRemovalWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const UiText('Remover fonte'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await run(() => widget.store.removeLocalSource(id));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.sync,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UiText('Fontes locais', style: Theme.of(context).textTheme.titleLarge),
        const UiText('Adicione pastas ou grupos de arquivos deste computador.'),
        if (error != null) UiText(error!),
        if (busy) const LinearProgressIndicator(),
        if (widget.sync.running) ...[
          Text(
            uiFormat(
              context,
              '${widget.sync.cancelled ? "Cancelando" : "Sincronizando"}: ${widget.sync.processed} músicas; ${widget.sync.examined} itens examinados.',
              '${widget.sync.cancelled ? "Cancelling" : "Synchronizing"}: ${widget.sync.processed} tracks; ${widget.sync.examined} items checked.',
            ),
          ),
          TextButton(
            onPressed: widget.sync.cancelled ? null : widget.sync.cancel,
            child: const UiText('Cancelar sincronização local'),
          ),
        ],
        for (final source in sources)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const MtIcon(Icons.folder),
            title: Text(
              source['label'] as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: source['sync_summary'] == null
                ? null
                : Text(summary(source['sync_summary'] as String)),
            trailing: PopupMenuButton<String>(
              enabled: !busy && !widget.sync.running,
              tooltip: ui(context, 'Ações da fonte'),
              onSelected: (value) => value == 'sync'
                  ? run(
                      () => widget.onSync(source['id'] as String),
                      syncing: true,
                    )
                  : remove(source['id'] as String),
              itemBuilder: (_) => [
                if (source['id'] != 'legacy' &&
                    !(source['id'] as String).startsWith('files:'))
                  const PopupMenuItem(
                    value: 'sync',
                    child: UiText('Sincronizar tags e capas'),
                  ),
                const PopupMenuItem(
                  value: 'remove',
                  child: UiText('Remover fonte'),
                ),
              ],
            ),
          ),
        const Divider(height: 40),
      ],
    ),
  );
  String summary(String value) {
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final date = DateTime.parse(data['completedAt'] as String).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return uiFormat(
        context,
        '${data['total']} músicas • ${data['missing']} ausentes • ${data['placeholders']} somente online\nÚltima sincronização: ${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}',
        '${data['total']} tracks • ${data['missing']} missing • ${data['placeholders']} online only\nLast synchronization: ${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}',
      );
    } catch (_) {
      return 'Resumo indisponível';
    }
  }
}
