import 'dart:async';

/// Keeps exit retryable, including when a plugin or a database job never returns.
class ExitCoordinator {
  ExitCoordinator({
    required this.confirm,
    required this.prepare,
    required this.save,
    required this.releaseMedia,
    required this.close,
    required this.resume,
    required this.log,
    this.saveTimeout = const Duration(seconds: 10),
    this.stepTimeout = const Duration(seconds: 3),
  });
  final Future<bool> Function(bool unsaved) confirm;
  final Future<void> Function() prepare, save, releaseMedia, close;
  final void Function() resume;
  final Future<void> Function(String) log;
  final Duration saveTimeout, stepTimeout;
  bool running = false;

  Future<void> _log(String event) async {
    try {
      await log(event).timeout(stepTimeout);
    } catch (_) {
      // Diagnostics must never prevent exiting.
    }
  }

  Future<void> exit() async {
    if (running) return;
    running = true;
    var prepared = false, closed = false;
    try {
      if (!await confirm(false)) return;
      await _log('exit_requested');
      prepared = true;
      await prepare().timeout(stepTimeout);
      try {
        await save().timeout(saveTimeout);
        await _log('exit_saved');
      } catch (_) {
        await _log('exit_save_incomplete');
        if (!await confirm(true)) return;
        await _log('exit_without_latest_save_confirmed');
      }
      try {
        await releaseMedia().timeout(stepTimeout * 3);
      } catch (_) {
        await _log('exit_media_release_incomplete');
      }
      await close().timeout(stepTimeout * 3);
      closed = true;
    } catch (_) {
      await _log('exit_failed_retry_available');
    } finally {
      running = false;
      if (prepared && !closed) {
        try {
          resume();
        } catch (_) {
          await _log('exit_resume_failed_retry_available');
        }
      }
    }
  }
}
