import 'design_icon.dart';
import 'settings_card.dart';
import 'ui_language.dart';

import 'package:flutter/material.dart';

Future<bool> confirmDataChange(
  BuildContext context, {
  required bool reset,
  String? summary,
}) async {
  final first = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      scrollable: true,
      title: UiText(reset ? 'Resetar todo o Music Time?' : 'Restaurar backup?'),
      content: UiText(
        reset
            ? 'Remove biblioteca, fontes, playlists, favoritos, histórico, fila, preferências, sessões e downloads gerenciados pelo app. As músicas originais no computador e nas nuvens são preservadas. Exporte um backup antes se quiser guardar seu catálogo. O app será reiniciado.'
            : uiFormat(
                context,
                '$summary\n\nSubstitui o catálogo e as preferências atuais. Não restaura credenciais nem arquivos musicais. O app será reiniciado, sem reprodução automática.',
                '$summary\n\nReplaces the current catalog and preferences. Credentials and music files are not restored. The app will restart with playback paused.',
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const UiText('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const UiText('Continuar'),
        ),
      ],
    ),
  );
  if (first != true || !context.mounted) return false;
  final input = TextEditingController();
  final word = ui(context, reset ? 'RESETAR' : 'RESTAURAR');
  final second = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        scrollable: true,
        title: const UiText('Confirmação final'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${ui(context, 'Type the confirmation word')}: $word'),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('data.confirmation'),
              controller: input,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: word),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed: input.text == word
                ? () => Navigator.pop(context, true)
                : null,
            child: UiText(
              reset ? 'Resetar e reiniciar' : 'Restaurar e reiniciar',
            ),
          ),
        ],
      ),
    ),
  );
  // The route may still animate out with its TextField attached.
  Future<void>.delayed(const Duration(seconds: 1), input.dispose);
  if (second != true || !context.mounted) return false;
  if (!reset) return true;
  var acknowledged = false;
  final third = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: const UiText('Final review · 3 of 3'),
        content: CheckboxListTile(
          value: acknowledged,
          onChanged: (value) => update(() => acknowledged = value ?? false),
          title: const UiText(
            'I understand that app data, sessions and managed downloads will be removed. Original music files will be preserved.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed: acknowledged ? () => Navigator.pop(context, true) : null,
            child: const UiText('Start again and restart'),
          ),
        ],
      ),
    ),
  );
  return third == true;
}

class DataSettings extends StatefulWidget {
  const DataSettings({
    super.key,
    required this.onBackup,
    required this.onRestore,
    required this.onReset,
    this.storage,
    this.storageHasSurface = false,
  });
  final Future<void> Function() onBackup, onRestore, onReset;
  final Widget? storage;
  final bool storageHasSurface;
  @override
  State<DataSettings> createState() => _DataSettingsState();
}

class _DataSettingsState extends State<DataSettings> {
  bool busy = false;
  String? message;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => message = error is FormatException ? error.message : 'Não foi possível concluir. Aguarde operações em andamento e tente novamente. Confira se o backup é válido e se há espaço no disco.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.zero,
    children: [
      SettingsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiText(
              'Backup e dados',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const UiText(
              'Escolha biblioteca, playlists, favoritos, histórico, fila, preferências e fontes. Capas são opcionais. Credenciais exigem um backup criptografado com senha. Músicas e downloads físicos não são incluídos.',
            ),
            if (busy) const LinearProgressIndicator(),
            if (message != null) UiText(message!),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : () => run(widget.onBackup),
                  icon: const MtIcon(Icons.save_alt),
                  label: const UiText('Exportar backup'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : () => run(widget.onRestore),
                  icon: const MtIcon(Icons.restore),
                  label: const UiText('Restaurar backup'),
                ),
              ],
            ),
          ],
        ),
      ),
      if (widget.storage != null)
        if (widget.storageHasSurface)
          widget.storage!
        else
          SettingsCard(child: widget.storage!),
      SettingsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiText(
              'Começar novamente',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const UiText(
              'Clears Music Time data and disconnects accounts. Original music files are preserved. Three confirmations are required.',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: busy
                    ? null
                    : () async {
                        if (await confirmDataChange(context, reset: true)) {
                          await run(widget.onReset);
                        }
                      },
                icon: const MtIcon(Icons.delete_forever),
                label: const UiText('Resetar todo o aplicativo'),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
