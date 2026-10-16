import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/settings/player_bar_layout.dart';
import 'package:music_time/presentation/player_bar_organizer.dart';

void main() {
  test(
    'preferências legadas, IDs válidos e persistência independente',
    () async {
      SharedPreferences.setMockInitialValues({
        'visual.secondary_controls': false,
        'visual.show_volume': false,
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      expect(playerBarVisible(settings), isNot(contains('shuffle')));
      expect(playerBarVisible(settings), isNot(contains('volume')));
      await settings.updateVisual('bar_items', <String>[]);
      expect(playerBarVisible(settings), isEmpty);
      await settings.updateVisual('bar_item_order', ['queue', 'play']);
      expect(playerBarOrder(AppSettings(settings.preferences)).take(2), [
        'queue',
        'play',
      ]);
      expect(playerBarOrder(settings).toSet().length, playerBarItems.length);
      expect(
        AppData.validPreferenceType('visual.bar_items', ['play', 'lyrics']),
        isTrue,
      );
      expect(
        AppData.validPreferenceType('visual.bar_items', ['play', 'play']),
        isFalse,
      );
      expect(
        AppData.validPreferenceType('visual.bar_item_order', ['unknown']),
        isFalse,
      );
      settings.dispose();
    },
  );

  testWidgets('organizador ordena, oculta, persiste e restaura', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlayerBarOrganizer(settings: settings),
          ),
        ),
      ),
    );
    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('player.organizer')),
    );
    list.onReorderItem!(2, 0);
    await tester.pumpAndSettle();
    expect(playerBarOrder(settings).first, 'previous');
    await tester.tap(find.byKey(const ValueKey('player.visibility.cover')));
    await tester.pumpAndSettle();
    expect(playerBarVisible(settings), isNot(contains('cover')));
    expect(
      playerBarVisible(AppSettings(settings.preferences)),
      isNot(contains('cover')),
    );
    await tester.ensureVisible(find.text('Restaurar barra padrão'));
    await tester.tap(find.text('Restaurar barra padrão'));
    await tester.pumpAndSettle();
    expect(playerBarOrder(settings), playerBarItems.keys);
    expect(
      playerBarVisible(settings),
      playerBarItems.keys.where((id) => !id.startsWith('separator')).toSet(),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
