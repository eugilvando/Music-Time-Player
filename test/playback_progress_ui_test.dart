import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/presentation/player_bar.dart';
import 'package:music_time/lyrics/lyrics_view.dart';
import 'package:music_time/lyrics/lyrics.dart';
import 'package:music_time/settings/app_settings.dart';

void main() {
  testWidgets(
    'progress and lyric highlight advance without rebuilding the page',
    (tester) async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      SharedPreferences.setMockInitialValues({
        'visual.bar_items': ['elapsed', 'progress', 'duration'],
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final controller = PlayerController()
        ..current = const Track(id: 'demo', title: 'Demo', artist: 'Fixture')
        ..duration = const Duration(seconds: 20);
      var loads = 0, pageBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                pageBuilds++;
                return Column(
                  children: [
                    Expanded(
                      child: LyricsView(
                        controller: controller,
                        settings: settings,
                        loader: (_, _) async {
                          loads++;
                          return parseLyrics(
                            '[00:00.00]First line\n[00:02.00]Second line',
                          );
                        },
                      ),
                    ),
                    PlayerBar(
                      controller: controller,
                      settings: settings,
                      favorite: false,
                      onFavorite: () {},
                      onDetails: () {},
                      onQueue: () {},
                      onExpand: () {},
                      onSave: () async {},
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final builds = pageBuilds;
      final firstColor = tester
          .widget<Text>(find.text('First line'))
          .style!
          .color;
      controller.position = const Duration(seconds: 3);
      controller.progress.value = controller.position;
      await tester.pumpAndSettle();
      expect(find.text('0:03'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider).first).value, 3000);
      expect(
        tester.widget<Text>(find.text('Second line')).style!.color,
        firstColor,
      );
      expect(loads, 1);
      expect(pageBuilds, builds);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      settings.dispose();
    },
  );
}
