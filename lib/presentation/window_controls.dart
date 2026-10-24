import 'design_icon.dart';
import 'ui_language.dart';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowControls extends StatelessWidget {
  const WindowControls({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8, right: 16),
    child: IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          visualDensity: VisualDensity.standard,
          maximumSize: const Size(32, 32),
          padding: const EdgeInsets.all(8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: ui(context, 'Minimizar'),
            iconSize: 16,
            onPressed: windowManager.minimize,
            icon: const MtIcon(Icons.remove),
          ),
          IconButton(
            tooltip: ui(context, 'Maximizar/restaurar'),
            iconSize: 16,
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            icon: const MtIcon(Icons.crop_square),
          ),
          IconButton(
            tooltip: ui(context, 'Fechar'),
            iconSize: 16,
            style: ButtonStyle(
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? Theme.of(context).colorScheme.errorContainer
                    : null,
              ),
            ),
            onPressed: windowManager.close,
            icon: const MtIcon(Icons.close),
          ),
        ],
      ),
    ),
  );
}
