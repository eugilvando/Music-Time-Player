import 'dart:io';

/// A created SNI icon alone does not prove that GNOME has an active panel host.
/// Keep the window reachable if the AppIndicator extension is disabled.
Future<bool> linuxTrayHostAvailable({
  Future<ProcessResult> Function(String, List<String>)? run,
}) async {
  try {
    final result =
        await (run ?? ((command, args) => Process.run(command, args)))(
          'gdbus',
          [
            'call',
            '--session',
            '--timeout',
            '2',
            '--dest',
            'org.kde.StatusNotifierWatcher',
            '--object-path',
            '/StatusNotifierWatcher',
            '--method',
            'org.freedesktop.DBus.Properties.Get',
            'org.kde.StatusNotifierWatcher',
            'IsStatusNotifierHostRegistered',
          ],
        ).timeout(const Duration(seconds: 3));
    return result.exitCode == 0 &&
        RegExp(r'<true>').hasMatch(result.stdout.toString());
  } catch (_) {
    return false;
  }
}
