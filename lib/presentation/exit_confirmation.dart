import 'package:flutter/material.dart';

import 'ui_language.dart';

Future<bool> showExitConfirmation(
  BuildContext context, {
  required List<String> tasks,
  required bool unsaved,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          title: UiText(
            unsaved
                ? 'Não foi possível concluir o salvamento'
                : 'Há tarefas em andamento',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!unsaved) ...[
                  for (final task in tasks) UiText('• ${ui(context, task)}'),
                  const SizedBox(height: 16),
                ],
                UiText(
                  unsaved
                      ? 'A fila ou posição mais recente pode não ser salva. Deseja sair mesmo assim?'
                      : 'Sair interrompe as tarefas em andamento. Downloads incompletos poderão ser tentados novamente; sincronizações poderão ser retomadas. Deseja sair mesmo assim?',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const UiText('Manter aberto'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const UiText('Sair mesmo assim'),
            ),
          ],
        ),
      ) ??
      false;
}
