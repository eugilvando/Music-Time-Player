import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/presentation/library_hub.dart';
import 'package:music_time/presentation/navigation.dart';
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
      await tester.tap(find.byKey(const ValueKey('library.organize')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MediaCardSizePicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extra Small').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library.organize.close')));
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

  testWidgets(
    'Card visibility persists independently from sidebar and history navigates',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'visual.sidebar_items': <String>['songs'],
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      addTearDown(settings.dispose);
      AppSection? destination;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryHub(
              tracks: const [],
              favorites: const {},
              settings: settings,
              onNavigate: (value) => destination = value,
            ),
          ),
        ),
      );
      final history = find.byKey(const ValueKey('library.card.history'));
      await tester.ensureVisible(history);
      await tester.tap(history);
      expect(destination, AppSection.history);
      await tester.ensureVisible(
        find.byKey(const ValueKey('library.organize')),
      );
      await tester.tap(find.byKey(const ValueKey('library.organize')));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('library.visibility.history'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library.organize.close')));
      await tester.pumpAndSettle();
      expect(history, findsNothing);
      expect(settings.visualList('sidebar_items', []), ['songs']);
      final restored = AppSettings(await SharedPreferences.getInstance());
      expect(
        restored.visualList('library_hub_items', []),
        isNot(contains('history')),
      );
      expect(restored.visualList('library_hub_items', []), contains('albums'));
      restored.dispose();
      await settings.updateVisual('sidebar_items', <String>['history']);
      await tester.pumpAndSettle();
      expect(history, findsNothing);
      expect(find.byKey(const ValueKey('library.card.songs')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Empty library cards can be restored using organizer in a narrow window',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'visual.library_hub_items': <String>[],
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: LibraryHub(
              tracks: const [],
              favorites: const {},
              settings: settings,
              onNavigate: (_) {},
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('library.card.history')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('library.organize')));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('library.visibility.history'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library.organize.close')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('library.card.history')),
        200,
      );
      expect(
        find.byKey(const ValueKey('library.card.history')),
        findsOneWidget,
      );
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
