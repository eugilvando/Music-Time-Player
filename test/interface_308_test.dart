import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/queue_panel.dart';
import 'package:music_time/presentation/now_playing_page.dart';
import 'package:music_time/presentation/fullscreen_now_playing.dart';
import 'package:music_time/presentation/player_bar.dart';
import 'package:music_time/lyrics/lyrics.dart';
import 'package:music_time/lyrics/lyrics_view.dart';

void main() {
  setUpAll(
    () => MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    ),
  );
  testWidgets('queue actions share one row and save uses an accessible icon', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(296, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final p = (await tester.runAsync(() async => PlayerController()))!;
    addTearDown(p.dispose);
    const track = Track(id: 'demo', title: 'Demo', artist: 'Fixture');
    p.queue.add(track);
    p.queueKeys.add(1);
    p.queueIndex = 0;
    p.current = track;
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QueuePanel(
            controller: p,
            onClose: () {},
            onSave: () async {},
            onSavePlaylist: () async {
              saves++;
            },
            onPlay: (_) async {},
            trackActions: (_, _) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final current = find.byKey(const ValueKey('queue.current'));
    final save = find.byKey(const ValueKey('queue.save'));
    final options = find.byKey(const ValueKey('queue.actions'));
    expect(tester.getCenter(save).dy, tester.getCenter(current).dy);
    expect(tester.getCenter(options).dy, tester.getCenter(current).dy);
    final toolbar = find.byKey(const ValueKey('queue.toolbar'));
    expect(
      tester.getRect(options).right,
      closeTo(tester.getRect(toolbar).right, 1),
    );
    await tester.binding.setSurfaceSize(const Size(560, 650));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(options).right,
      closeTo(tester.getRect(toolbar).right, 1),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('queue.count'))).left -
          tester.getRect(save).right,
      greaterThan(100),
    );
    expect(tester.widget<IconButton>(save).tooltip, isNotEmpty);
    expect(find.byType(TextButton), findsNothing);
    await tester.tap(save);
    await tester.pump();
    expect(saves, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'cover and lyrics choice survives entering and leaving fullscreen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
      final settings = AppSettings(prefs);
      addTearDown(settings.dispose);
      final p = (await tester.runAsync(() async => PlayerController()))!;
      addTearDown(p.dispose);
      const track = Track(id: 'demo', title: 'Demo', artist: 'Fixture');
      p.current = track;
      p.queue.add(track);
      p.queueKeys.add(1);
      p.queueIndex = 0;
      Future<LyricsDocument?> lyrics(Track _, bool refresh) async =>
          const LyricsDocument([LyricLine('Demo lyrics')]);
      Widget normal() => MaterialApp(
        home: Scaffold(
          body: NowPlayingPage(
            controller: p,
            settings: settings,
            favorite: false,
            onFavorite: () {},
            onDetails: () {},
            onFullscreen: () {},
            loadLyrics: lyrics,
          ),
        ),
      );
      await tester.pumpWidget(normal());
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsNothing);
      tester
          .widget<SegmentedButton<bool>>(
            find.byKey(const ValueKey('nowPlaying.mode')),
          )
          .onSelectionChanged!({true});
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: FullscreenNowPlaying(
            controller: p,
            settings: settings,
            loadLyrics: lyrics,
            onExit: () {},
            onQueue: () {},
            controls: (_) => PlayerBar(
              controller: p,
              settings: settings,
              favorite: false,
              onFavorite: () {},
              onDetails: () {},
              onQueue: () {},
              onExpand: () {},
              onSave: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsOneWidget);
      tester
          .widget<SegmentedButton<bool>>(
            find.byKey(const ValueKey('fullscreen.mode')),
          )
          .onSelectionChanged!({false});
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsNothing);
      await tester.pumpWidget(normal());
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsNothing);
      expect(p.current, same(track));
      expect(p.queue, [track]);
      expect(settings.visualChoice('now_playing_content', ''), 'cover');
      await settings.updateVisual('style', 'lyrics_only');
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsOneWidget);
      await settings.resetNowPlaying();
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
