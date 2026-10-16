import 'ui_language.dart';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowControls extends StatelessWidget {
  const WindowControls({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: ui(context, 'Minimizar'),
        iconSize: 18,
        onPressed: windowManager.minimize,
        icon: const Icon(Icons.remove),
      ),
      IconButton(
        tooltip: ui(context, 'Maximizar/restaurar'),
        iconSize: 18,
        onPressed: () async {
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        },
        icon: const Icon(Icons.crop_square),
      ),
      IconButton(
        tooltip: ui(context, 'Fechar'),
        iconSize: 18,
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? Theme.of(context).colorScheme.errorContainer
                : null,
          ),
        ),
        onPressed: windowManager.close,
        icon: const Icon(Icons.close),
      ),
    ],
  );
}
