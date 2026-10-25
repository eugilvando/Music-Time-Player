import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/settings_dialog.dart';

void main() {
  testWidgets(
    'organizers collapse independently without changing preferences',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      addTearDown(settings.dispose);
      final before = settings.preferences.getKeys().toSet();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPage(
              settings: settings,
              onAddFiles: () {},
              trackCount: 0,
              initialCategory: SettingsCategory.customization,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byKey(const ValueKey('settings.organizer.Sidebar'));
      final bar = find.byKey(
        const ValueKey('settings.organizer.Organizar barra de reprodução'),
      );
      expect(find.byKey(const ValueKey('sidebar.setting.home')), findsNothing);
      expect(find.byKey(const ValueKey('player.organizer')), findsNothing);
      await tester.ensureVisible(sidebar);
      await tester.tapAt(tester.getTopLeft(sidebar) + const Offset(100, 24));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sidebar.setting.home')),
        findsOneWidget,
      );
      await tester.tapAt(tester.getTopLeft(sidebar) + const Offset(100, 24));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sidebar.setting.home')), findsNothing);
      await tester.ensureVisible(bar);
      await tester.tapAt(tester.getTopLeft(bar) + const Offset(100, 24));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('player.organizer')), findsOneWidget);
      await tester.ensureVisible(bar);
      await tester.tapAt(tester.getTopLeft(bar) + const Offset(100, 24));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('player.organizer')), findsNothing);
      expect(settings.preferences.getKeys(), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
