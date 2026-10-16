import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/application/exit_coordinator.dart';
import 'package:music_time/application/playback_save_coordinator.dart';

void main() {
  test(
    'a failure while resuming never leaves exit permanently locked',
    () async {
      var attempts = 0;
      final exit = ExitCoordinator(
        confirm: (_) async => true,
        prepare: () async {},
        save: () async {},
        releaseMedia: () async {},
        close: () async {
          if (++attempts == 1) throw StateError('close');
        },
        resume: () {
          throw StateError('resume');
        },
        log: (_) async {},
      );
      await exit.exit();
      expect(exit.running, false);
      await exit.exit();
      expect(attempts, 2);
    },
  );
  test('keeping open does not suspend tasks, save or close', () async {
    final calls = <String>[];
    final exit = ExitCoordinator(
      confirm: (_) async => false,
      prepare: () async => calls.add('prepare'),
      save: () async => calls.add('save'),
      releaseMedia: () async => calls.add('media'),
      close: () async => calls.add('close'),
      resume: () => calls.add('resume'),
      log: (_) async {},
    );
    await exit.exit();
    expect(calls, isEmpty);
    expect(exit.running, false);
  });

  test('hung save allows keeping open and a later exit retry', () async {
    final calls = <String>[];
    var hung = true, allowUnsaved = false;
    final exit = ExitCoordinator(
      confirm: (unsaved) async {
        calls.add('confirm:$unsaved');
        return !unsaved || allowUnsaved;
      },
      prepare: () async => calls.add('prepare'),
      save: () => hung ? Completer<void>().future : Future.value(),
      releaseMedia: () async => calls.add('media'),
      close: () async => calls.add('close'),
      resume: () => calls.add('resume'),
      log: (_) async {},
      saveTimeout: const Duration(milliseconds: 10),
    );
    await exit.exit();
    expect(calls, contains('confirm:true'));
    expect(calls, contains('resume'));
    expect(calls, isNot(contains('close')));
    expect(exit.running, false);
    hung = false;
    allowUnsaved = true;
    await exit.exit();
    expect(calls.last, 'close');
  });

  test(
    'explicit unsaved exit survives a stuck media plugin and duplicate clicks',
    () async {
      final confirmation = Completer<bool>();
      var confirms = 0, closes = 0;
      final exit = ExitCoordinator(
        confirm: (unsaved) {
          confirms++;
          return unsaved ? Future.value(true) : confirmation.future;
        },
        prepare: () async {},
        save: () => Future.error(StateError('write failed')),
        releaseMedia: () => Completer<void>().future,
        close: () async {
          closes++;
        },
        resume: () {},
        log: (_) async {},
        stepTimeout: const Duration(milliseconds: 5),
      );
      final first = exit.exit();
      await exit.exit();
      expect(confirms, 1);
      confirmation.complete(true);
      await first;
      expect(confirms, 2);
      expect(closes, 1);
      expect(exit.running, false);
    },
  );

  test(
    'diagnostic failures do not block exit; failed close stays retryable',
    () async {
      var attempts = 0, resumed = 0;
      final exit = ExitCoordinator(
        confirm: (_) async => true,
        prepare: () async {},
        save: () async {},
        releaseMedia: () async {},
        close: () async {
          if (++attempts == 1) throw StateError('native close');
        },
        resume: () {
          resumed++;
        },
        log: (_) => Completer<void>().future,
        stepTimeout: const Duration(milliseconds: 1),
      );
      await exit.exit();
      expect(resumed, 1);
      await exit.exit();
      expect(attempts, 2);
    },
  );

  test(
    'periodic saves coalesce and final flush writes a fresh snapshot',
    () async {
      final gate = Completer<void>();
      var writes = 0;
      final saves = PlaybackSaveCoordinator(() async {
        if (++writes == 1) await gate.future;
      });
      final requests = List.generate(20, (_) => saves.save());
      final flush = saves.flush();
      expect(writes, 1);
      gate.complete();
      await Future.wait([...requests, flush]);
      expect(writes, 2);
      expect(saves.saving, false);
    },
  );

  test('failed saves release coordinator for retry', () async {
    var attempts = 0;
    final saves = PlaybackSaveCoordinator(() async {
      if (++attempts == 1) throw StateError('disk');
    });
    await expectLater(saves.save(), throwsStateError);
    await saves.flush();
    expect(attempts, 2);
  });
}
