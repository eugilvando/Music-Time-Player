import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/now_playing_page.dart';
import 'package:music_time/presentation/now_playing_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    ),
  );
  testWidgets(
    'all artwork modes respond throughout the slider in wide and narrow layouts',
    (tester) async {
      SharedPreferences.setMockInitialValues({'visual.animations': false});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final controller = (await tester.runAsync(
        () async => PlayerController(),
      ))!;
      addTearDown(() {
        controller.dispose();
        settings.dispose();
      });
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [480.0, 1400.0]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        for (final style in [
          'classic',
          'vinyl',
          'minimal',
          'cover_only',
          'lyrics',
        ]) {
          if (style == 'lyrics' && width < 740) continue;
          await settings.updateVisual(
            'style',
            style == 'lyrics' ? 'classic' : style,
          );
          var previous = 0.0;
          for (final scale in [.7, 1.2, 1.8, 2.6]) {
            await settings.updateVisual('cover_scale', scale);
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: NowPlayingPage(
                    controller: controller,
                    settings: settings,
                    favorite: false,
                    onFavorite: () {},
                    onDetails: () {},
                    showLyrics: style == 'lyrics',
                  ),
                ),
              ),
            );
            await tester.pump();
            final actual = tester.getSize(find.byType(NowPlayingArtwork)).width;
            expect(
              actual,
              greaterThan(previous),
              reason: '$style at $width / $scale',
            );
            expect(actual, lessThanOrEqualTo(width));
            expect(tester.takeException(), isNull);
            previous = actual;
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
