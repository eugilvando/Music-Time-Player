import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/domain/queue_navigation.dart';
import 'package:music_time/library/intelligent_queue.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/settings/app_settings.dart';

const a = Track(id: 'a', title: 'A', artist: 'One', genre: 'Rock', year: 1993);
const b = Track(id: 'b', title: 'B', artist: 'Two', genre: 'Jazz', year: 2003);
const c = Track(id: 'c', title: 'C', artist: 'One', genre: 'Rock', year: 1996);
const d = Track(id: 'd', title: 'D', artist: 'Two', genre: 'Jazz', year: 2005);
const e = Track(
  id: 'e',
  title: 'E',
  artist: 'Related',
  genre: 'Other',
  year: 1997,
);
const catalog = [a, b, c, d, e];

void main() {
  test('queue modes use all choices, not just final song', () {
    for (final mode in ['related', 'artist']) {
      final result = intelligentTracks(
        IntelligentQueueWork(catalog, [a, b], mode: mode),
      );
      expect(result.map((t) => t.id).toSet(), {'c', 'd'});
    }
    expect(
      intelligentTracks(
        const IntelligentQueueWork(catalog, [a, b], mode: 'era'),
      ).map((t) => t.id).toSet(),
      {'c', 'd', 'e'},
    );
  });
  test('manual context outweighs generated tracks and recency has weight', () {
    final context = QueueContext([a, b], automatic: {1})..analyze();
    expect(context.artists['one']!, greaterThan(context.artists['two']!));
    final manual = QueueContext([a, b])..analyze();
    expect(manual.artists['two']!, greaterThan(manual.artists['one']!));
  });
  test('eligibility, duplicates, hidden items and offline are respected', () {
    const hidden = Track(
      id: 'hidden',
      title: 'Hidden',
      artist: 'One',
      libraryHidden: true,
    );
    const missing = Track(
      id: 'missing',
      title: 'Missing',
      artist: 'One',
      available: false,
    );
    final result = intelligentTracks(
      const IntelligentQueueWork(
        [...catalog, c, hidden, missing],
        [a, b],
        mode: 'shuffle',
        offlineOnly: true,
        offline: {'c', 'hidden', 'missing'},
      ),
    );
    expect(result.map((t) => t.id).toSet(), {'c', 'missing'});
    expect(result.length, 2);
    expect(
      intelligentTracks(
        const IntelligentQueueWork(catalog, catalog, mode: 'shuffle'),
      ),
      isEmpty,
    );
  });
  test('weighted sampling represents multiple genres over rounds', () {
    final ids = <String>{};
    for (var i = 0; i < 20; i++) {
      ids.add(
        intelligentTracks(
          const IntelligentQueueWork(catalog, [a, b], count: 1),
          random: Random(i),
        ).single.id,
      );
    }
    expect(ids, {'c', 'd'});
  });
  test(
    'flow pairs artists and never repeats an existing or inserted track',
    () {
      final result = prepareSmartFlow(
        const SmartFlowWork(catalog, [a, b, a], [0, 1], mode: 'double'),
      );
      expect(result[0], c);
      expect(result[1], d);
      expect(
        prepareSmartFlow(
          const SmartFlowWork(catalog, [a, c, b], [0, 1], mode: 'double'),
        ),
        isEmpty,
      );
    },
  );
  test('flow uses similarity and same decade, and local fallback', () {
    expect(
      prepareSmartFlow(
        const SmartFlowWork(
          [a, b, e],
          [a, b],
          [0],
          mode: 'artist',
          similar: {
            'one': {'Related'},
          },
        ),
      )[0],
      e,
    );
    expect(
      prepareSmartFlow(
        const SmartFlowWork([a, b, e], [a, b], [0], mode: 'era'),
      )[0],
      e,
    );
    expect(
      prepareSmartFlow(
        const SmartFlowWork([a, b, c], [a, b], [0], mode: 'artist'),
      )[0],
      c,
    );
    expect(
      prepareSmartFlow(
        const SmartFlowWork(
          catalog,
          [a, b],
          [0],
          offlineOnly: true,
          offline: {},
        ),
      ),
      isEmpty,
    );
  });
  test(
    'legacy double mode preserves queue intent, flow remains opt-in',
    () async {
      SharedPreferences.setMockInitialValues({
        'visual.smart_play': true,
        'visual.continuous_mode': 'double',
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      expect(settings.intelligentQueueEnabled, true);
      expect(settings.intelligentQueueMode, 'artist');
      expect(settings.smartFlowEnabled, false);
      settings.dispose();
    },
  );
  test(
    'flow lifecycle: stale responses, provenance, reorder, repeat and restore',
    () async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      final p = PlayerController();
      final restored = PlayerController();
      try {
        p.queue.addAll([a, b]);
        p.queueKeys.addAll([100, 101]);
        p.queueIndex = 0;
        p.current = a;
        p.configureSmartFlow((_, _) async => {0: c});
        await p.prepareFlow();
        expect(p.queue, [a, c, b]);
        expect(p.automaticOrigin(1), 'flow');
        await p.prepareFlow();
        expect(p.queue, [a, c, b]);
        restored.queue.addAll(p.queue);
        restored.queueKeys.addAll([10, 11, 12]);
        restored.queueIndex = 0;
        restored.configureSmartFlow((_, _) async => {});
        restored.restoreAutomationSnapshot(p.automationSnapshot);
        expect(restored.automaticOrigin(1), 'flow');
        restored.configureSmartFlow(null);
        expect(restored.queue, [a, b]);
        p.reorderQueue(1, 2);
        p.configureSmartFlow(null);
        expect(p.queue, [a, b, c]);
        expect(p.automaticIndices, isEmpty);
        final pending = Completer<Map<int, Track>>();
        p.configureSmartFlow((_, _) => pending.future);
        final task = p.prepareFlow();
        p.configureSmartFlow(null);
        pending.complete({0: d});
        await task;
        expect(p.queue, [a, b, c]);
        p.configureSmartFlow((_, _) async => {0: d});
        p.repeat = PlaybackRepeat.queue;
        await p.prepareFlow();
        expect(p.queue, [a, b, c]);
        p.repeat = PlaybackRepeat.off;
        await p.prepareFlow();
        expect(p.queue, [a, d, b, c]);
        p.cycleRepeat();
        expect(p.queue, [a, b, c]);
      } finally {
        p.dispose();
        restored.dispose();
      }
    },
    skip: Platform.environment['MUSIC_TIME_LIBMPV'] == null
        ? 'Native playback library required'
        : false,
  );
}
