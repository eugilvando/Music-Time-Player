import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/platform/tray_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final calls = <String>[];
  var minimized = false;
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'isMinimized') return minimized;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'hidden normal or maximized window keeps its existing placement',
    () async {
      minimized = false;
      await showTrayWindow();
      expect(calls, ['setSkipTaskbar', 'isMinimized', 'show', 'focus']);
    },
  );
  test('minimized window is restored before receiving focus', () async {
    minimized = true;
    await showTrayWindow();
    expect(calls, [
      'setSkipTaskbar',
      'isMinimized',
      'restore',
      'show',
      'focus',
    ]);
  });
}
