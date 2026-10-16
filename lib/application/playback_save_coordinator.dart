import 'dart:async';

/// Concurrent callers join one write instead of queueing another transaction.
class PlaybackSaveCoordinator {
  PlaybackSaveCoordinator(this.write);
  final Future<void> Function() write;
  Future<void>? _pending;
  bool get saving => _pending != null;

  Future<void> save() => _pending ??= Future<void>.sync(write).whenComplete(() {
    _pending = null;
  });

  /// After any earlier write, take a fresh snapshot for the final save.
  Future<void> flush() async {
    await _pending;
    await save();
  }
}
