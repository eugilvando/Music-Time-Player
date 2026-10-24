import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/player_bar.dart';

void main() {
  testWidgets(
    'barra mantém ordem offline contínuo letras e Last.fm junto às ações',
    (tester) async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final controller = PlayerController();
      tester.view.physicalSize = const Size(1600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: settings,
            builder: (context, _) => Scaffold(
              bottomNavigationBar: PlayerBar(
                controller: controller,
                settings: settings,
                favorite: false,
                onFavorite: () {},
                onDetails: () {},
                onQueue: () {},
                onExpand: () {},
                onSave: () async {},
                onLyrics: () {},
                lastfmStatus: 'Last.fm conectado',
              ),
            ),
          ),
        ),
      );
      final icons = [Icons.offline_pin, Icons.auto_awesome, Icons.lyrics];
      final info = tester.getRect(
        find.byKey(const ValueKey('player.item.info')),
      );
      final previous = tester.getRect(
        find.byKey(const ValueKey('player.item.previous')),
      );
      expect(previous.left - info.right, 4);
      expect(previous.left, greaterThan(info.left));
      final positions = icons
          .map((icon) => tester.getCenter(find.byIcon(icon)))
          .toList();
      expect(positions[0].dx, lessThan(positions[1].dx));
      expect(positions[1].dx, lessThan(positions[2].dx));
      expect(positions.map((p) => p.dy).toSet().length, 1);
      final actions = tester.getCenter(find.byIcon(Icons.more_horiz));
      final lastfm = tester.getCenter(
        find.byKey(const ValueKey('player.lastfm')),
      );
      expect(lastfm.dx, greaterThan(actions.dx));
      expect(lastfm.dx - actions.dx, lessThan(40));
      expect(lastfm.dy, actions.dy);
      final seekbar = find.byKey(const ValueKey('player.seekbar'));
      final wideWidth = tester.getSize(seekbar).width;
      expect(wideWidth, greaterThan(200));
      tester.view.physicalSize = const Size(2000, 800);
      await tester.pump();
      expect(
        tester.getSize(seekbar).width,
        inInclusiveRange(wideWidth + 350, wideWidth + 400),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('player.item.info'))).width,
        lessThanOrEqualTo(310),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('player.single-line'))).width,
        1968,
      );
      tester.view.physicalSize = const Size(480, 600);
      await tester.pump();
      expect(tester.getSize(seekbar).width, greaterThanOrEqualTo(140));
      expect(
        tester.getCenter(find.byIcon(Icons.lyrics)).dy,
        tester.getCenter(find.byIcon(Icons.offline_pin)).dy,
      );
      expect(tester.takeException(), isNull);
      await settings.updateVisual('bar_item_order', [
        'play',
        'info',
        'progress',
      ]);
      await settings.updateVisual('bar_items', ['play', 'info', 'progress']);
      await tester.pump();
      expect(find.byIcon(Icons.offline_pin), findsNothing);
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(
        tester.getCenter(find.byKey(const ValueKey('player.item.play'))).dx,
        lessThan(
          tester.getCenter(find.byKey(const ValueKey('player.item.info'))).dx,
        ),
      );
      await settings.updateVisual('bar_items', <String>[]);
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      settings.dispose();
    },
  );
}
