import 'package:flutter/material.dart';

import 'ui_language.dart';

Future<T> runBackupProgress<T>(
  BuildContext context,
  Future<T> Function(void Function(String)) operation,
) async {
  final status = ValueNotifier('Preparando backup…');
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const UiText('Backup'),
        content: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 20),
              Text(value),
            ],
          ),
        ),
      ),
    ),
  );
  final closed = navigator.push(route);
  try {
    return await operation((message) => status.value = message);
  } finally {
    if (route.isActive) navigator.removeRoute(route);
    await closed;
    // The outgoing dialog may still hold the notifier until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => status.dispose());
  }
}
