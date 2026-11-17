import 'package:flutter_test/flutter_test.dart';

/// Device initialization is asynchronous; wait for observable playback rather
/// than assuming the first position update arrives within a fixed 350 ms.
Future<void> waitForNative(bool Function() ready, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(
    ready(),
    isTrue,
    reason: reason ?? 'Native audio did not become ready within 8 seconds',
  );
}
