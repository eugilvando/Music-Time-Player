import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/presentation/library_hub.dart';
import 'package:music_time/presentation/media_card_size.dart';
import 'package:music_time/settings/app_settings.dart';

void main() {
  testWidgets(
    'Library card size changes immediately and persists independently',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'visual.media_card_size': 'Large',
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryHub(
              settings: settings,
              tracks: const [],
              favorites: const {},
              onNavigate: (_) {},
            ),
          ),
        ),
      );
      final card = find.byKey(const ValueKey('library.card.songs'));
      final normal = tester.getSize(card).width;
      await tester.tap(find.byType(MediaCardSizePicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extra Small').last);
      await tester.pumpAndSettle();
      expect(tester.getSize(card).width, lessThan(normal));
      expect(settings.visualChoice('library_hub_card_size', ''), 'Extra Small');
      expect(settings.visualChoice('media_card_size', ''), 'Large');
      final restored = AppSettings(await SharedPreferences.getInstance());
      expect(restored.visualChoice('library_hub_card_size', ''), 'Extra Small');
      restored.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('All five sizes fit narrow and wide windows in both themes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    addTearDown(settings.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final brightness in Brightness.values) {
      for (final size in [const Size(360, 700), const Size(1280, 900)]) {
        await tester.binding.setSurfaceSize(size);
        for (final choice in LibraryHub.widths.keys) {
          await settings.updateVisual('library_hub_card_size', choice);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: LibraryHub(
                    settings: settings,
                    tracks: const [],
                    favorites: const {},
                    onNavigate: (_) {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$brightness $size $choice',
          );
        }
      }
    }
  });
}
