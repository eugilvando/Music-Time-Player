import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/presentation/player_bar.dart';
import 'package:music_time/settings/app_settings.dart';

void main() {
  testWidgets(
    'existing continuous control selects a persistent mode; queue accepts dragged tracks',
    (tester) async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      SharedPreferences.setMockInitialValues({
        'visual.bar_items': ['favorite', 'continuous', 'queue'],
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final controller = PlayerController();
      const track = Track(id: 'a', title: 'A', artist: 'Band');
      controller.queue.add(track);
      controller.queueKeys.add(-1);
      controller.queueIndex = 0;
      var saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Draggable<List<Track>>(
                  data: [track],
                  feedback: Text('drag'),
                  child: Text('source'),
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
                  onQueueEdited: () => saved++,
                ),
              ],
            ),
          ),
        ),
      );
      final autoplay = find.byTooltip('Play contínuo');
      final favorite = find.byTooltip('Favoritar');
      expect(tester.getSize(autoplay), const Size(32, 32));
      expect(
        tester.getCenter(autoplay).dy,
        closeTo(tester.getCenter(favorite).dy, 0.5),
      );
      await tester.tap(find.byTooltip('Play contínuo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Era').last);
      await tester.pumpAndSettle();
      expect(settings.visualBool('smart_play', fallback: false), true);
      expect(
        AppSettings(settings.preferences)
            .visualChoice('continuous_mode', 'related'),
        'era',
      );
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      final source = tester.getCenter(find.text('source'));
      final target = tester.getCenter(find.byType(DragTarget<List<Track>>));
      await tester.dragFrom(source, target - source);
      await tester.pumpAndSettle();
      expect(controller.queue.length, 2);
      expect(saved, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      settings.dispose();
    },
  );
}
