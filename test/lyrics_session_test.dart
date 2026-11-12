import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/lyrics/lyrics.dart';
import 'package:music_time/lyrics/lyrics_session.dart';

Track track(String id) => Track(id: id, title: id, artist: 'Test');
void main() {
  test('prefetch and panels share in-flight work and parsed results', () async {
    final response = Completer<LyricsDocument?>();
    var calls = 0;
    final session = LyricsSession((t, refresh) {
      calls++;
      return response.future;
    });
    session.prefetch([track('a')]);
    final panel = session.load(track('a'), false);
    expect(calls, 1);
    response.complete(parseLyrics('Synthetic line'));
    final result = await panel;
    expect(await session.load(track('a'), false), same(result));
    expect(calls, 1);
    session.dispose();
  });
  test('miss expires and explicit refresh retries immediately', () async {
    var now = DateTime(2026);
    var calls = 0;
    final session = LyricsSession((t, refresh) async {
      calls++;
      return null;
    }, now: () => now);
    await session.load(track('a'), false);
    await session.load(track('a'), false);
    expect(calls, 1);
    await session.load(track('a'), true);
    expect(calls, 2);
    now = now.add(const Duration(minutes: 3));
    await session.load(track('a'), false);
    expect(calls, 3);
  });
  test(
    'queue changes drop obsolete look-ahead without blocking caller',
    () async {
      final first = Completer<LyricsDocument?>();
      final calls = <String>[];
      final session = LyricsSession((t, refresh) async {
        calls.add(t.id);
        if (t.id == 'a') return first.future;
        return null;
      });
      session.prefetch([track('a'), track('b'), track('c'), track('d')]);
      expect(calls, ['a']);
      session.prefetch([track('x'), track('y')]);
      first.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['a', 'x', 'y']);
      session.dispose();
      session.prefetch([track('z')]);
      expect(calls, ['a', 'x', 'y']);
    },
  );
  test('refresh failure does not erase a successful cached document', () async {
    var fail = false;
    final session = LyricsSession((t, refresh) async {
      if (fail) throw StateError('offline');
      return parseLyrics('Synthetic');
    });
    final result = await session.load(track('a'), false);
    fail = true;
    await expectLater(session.load(track('a'), true), throwsStateError);
    expect(await session.load(track('a'), false), same(result));
  });
}
