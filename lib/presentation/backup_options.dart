import 'package:flutter/material.dart';

import '../persistence/backup_archive.dart';
import 'ui_language.dart';

class BackupOptions {
  const BackupOptions(this.sections, this.password);
  final Set<String> sections;
  final String? password;
}

Future<BackupOptions?> showBackupOptions(
  BuildContext context, {
  Set<String>? available,
  bool passwordOnly = false,
}) async {
  final exporting = available == null && !passwordOnly;
  final selected = <String>{
    ...available ??
        backupSections.keys.where((s) => s != 'artwork' && s != 'credentials'),
  };
  var encrypt = false;
  final password = TextEditingController(),
      confirmation = TextEditingController();
  final result = await showDialog<BackupOptions>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, update) => AlertDialog(
        insetPadding: const EdgeInsets.all(24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: UiText(
          passwordOnly
              ? 'Senha do backup'
              : exporting
              ? 'Exportar backup'
              : 'Importar dados do backup',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!passwordOnly) ...[
                  UiText(
                    exporting
                        ? 'Escolha o conteúdo. Músicas e downloads físicos não são incluídos.'
                        : 'Os itens selecionados serão importados sem apagar os demais dados. Playlists serão adicionadas como cópias.',
                  ),
                  const SizedBox(height: 12),
                  for (final item in backupSections.entries)
                    if (available == null || available.contains(item.key))
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: UiText(item.value),
                        value: selected.contains(item.key),
                        onChanged:
                            item.key == 'artwork' &&
                                !selected.contains('library') &&
                                !selected.contains('playlists')
                            ? null
                            : (v) => update(() {
                                v == true
                                    ? selected.add(item.key)
                                    : selected.remove(item.key);
                                if (item.key == 'credentials' && v == true) {
                                  encrypt = true;
                                  selected.add('providers');
                                }
                                if (item.key == 'providers' && v != true) {
                                  selected.remove('credentials');
                                }
                                if (!selected.contains('library') &&
                                    !selected.contains('playlists')) {
                                  selected.remove('artwork');
                                }
                              }),
                      ),
                  if (exporting)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const UiText('Criptografar com senha'),
                      value: encrypt,
                      onChanged: selected.contains('credentials')
                          ? null
                          : (v) => update(() => encrypt = v),
                    ),
                  if (exporting)
                    const UiText(
                      'Capas são opcionais para reduzir o tamanho. Sessões podem expirar; reconexão pode ser necessária em outro computador.',
                    ),
                ],
                if (encrypt || passwordOnly) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: password,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: ui(context, 'Senha do backup'),
                    ),
                    onChanged: (_) => update(() {}),
                  ),
                  if (exporting) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmation,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: ui(context, 'Confirmar senha'),
                      ),
                      onChanged: (_) => update(() {}),
                    ),
                    const UiText(
                      'Use pelo menos 12 caracteres. A senha não é salva e não pode ser recuperada.',
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed:
                (!passwordOnly && selected.isEmpty) ||
                    ((encrypt || passwordOnly) &&
                        (password.text.isEmpty ||
                            (exporting &&
                                (password.text.length < 12 ||
                                    password.text != confirmation.text))))
                ? null
                : () => Navigator.pop(
                    dialog,
                    BackupOptions(
                      Set.of(selected),
                      encrypt || passwordOnly ? password.text : null,
                    ),
                  ),
            child: const UiText('Continuar'),
          ),
        ],
      ),
    ),
  );
  Future<void>.delayed(const Duration(seconds: 1), () {
    password.dispose();
    confirmation.dispose();
  });
  return result;
}
