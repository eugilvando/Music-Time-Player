import 'package:window_manager/window_manager.dart';

Future<void> showTrayWindow() async {
  await windowManager.setSkipTaskbar(false);
  // show() restores minimized windows itself. An extra restore would also
  // unmaximize a window that was only hidden in the tray.
  await windowManager.show();
  await windowManager.focus();
}
