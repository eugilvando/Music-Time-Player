import 'package:flutter/material.dart';

import '../persistence/library_store.dart';
import 'settings_card.dart';
import 'ui_language.dart';

class ArtworkStorageSettings extends StatefulWidget {
  const ArtworkStorageSettings({
    super.key,
    required this.store,
    required this.canOptimize,
  });
  final LibraryStore store;
  final bool Function() canOptimize;
  @override
  State<ArtworkStorageSettings> createState() => _ArtworkStorageSettingsState();
}

class _ArtworkStorageSettingsState extends State<ArtworkStorageSettings> {
  String? result;
  Future<void> optimize() async {
    if (!widget.canOptimize()) {
      setState(
        () => result = 'Aguarde as tarefas de sincronização e downloads antes de otimizar.',
      );
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const UiText('Otimizar armazenamento das capas?'),
        content: const UiText(
          'Capas idênticas serão compartilhadas sem perder qualidade. A conversão é feita em lotes e pode ser interrompida. Ao final, a compactação reduz o arquivo do banco e precisa de espaço temporário em disco, que pode chegar a duas vezes o tamanho do banco atual. Músicas originais e preferências são preservadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const UiText('Otimizar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (!widget.canOptimize()) {
      setState(
        () => result = 'Aguarde as tarefas de sincronização e downloads antes de otimizar.',
      );
      return;
    }
    setState(() => result = null);
    try {
      await widget.store.artwork.optimize();
      if (mounted) {
        setState(
          () => result = widget.store.artwork.cancelled
              ? 'Otimização interrompida. Você pode continuar depois; capas já convertidas foram preservadas.'
              : 'Capas compartilhadas e banco compactado.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => result = 'Não foi possível concluir a otimização. Confira o espaço livre e tente novamente. As capas já convertidas foram preservadas.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store.artwork,
    builder: (context, _) {
      final artwork = widget.store.artwork;
      return SettingsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiText(
              'Armazenamento das capas',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const UiText(
              'Novas capas idênticas são armazenadas uma única vez. Otimize para converter as capas antigas e recuperar espaço no banco.',
            ),
            const SizedBox(height: 12),
            if (artwork.running) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                artwork.compacting
                    ? ui(context, 'Compactando banco…')
                    : uiFormat(
                        context,
                        '${artwork.progress?.processed ?? 0} capas processadas',
                        '${artwork.progress?.processed ?? 0} covers processed',
                      ),
              ),
              if (!artwork.compacting)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: artwork.cancel,
                    child: const UiText('Interromper após este lote'),
                  ),
                ),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: optimize,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const UiText('Otimizar capas e compactar banco'),
                ),
              ),
            if (result != null) UiText(result!),
          ],
        ),
      );
    },
  );
}
