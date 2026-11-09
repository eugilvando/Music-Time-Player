import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/presentation/library_hub.dart';
import 'package:music_time/presentation/navigation.dart';
import 'package:music_time/settings/app_settings.dart';

void main() {
  test(
    'sidebar upgrade keeps hidden choices and custom order, only once',
    () async {
      SharedPreferences.setMockInitialValues({
        'visual.sidebar_items': ['albums', 'library'],
        'visual.sidebar_order': ['albums', 'library', 'home'],
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      await settings.migrateHomeLayout();
      expect(settings.preferences.getStringList('visual.sidebar_items'), [
        'albums',
        'library',
        'songs',
        'years',
        'genres',
      ]);
      expect(settings.preferences.getStringList('visual.sidebar_order'), [
        'albums',
        'library',
        'songs',
        'years',
        'genres',
        'home',
      ]);
      await settings.updateVisual('sidebar_items', ['library']);
      await settings.migrateHomeLayout();
      expect(settings.preferences.getStringList('visual.sidebar_items'), [
        'library',
      ]);
      settings.dispose();
    },
  );
  for (final width in [420.0, 1200.0]) {
    testWidgets('library overview offers all destinations at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      addTearDown(settings.dispose);
      AppSection? destination;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryHub(
              settings: settings,
              tracks: const [
                Track(
                  id: 'fixture',
                  title: 'Aurora',
                  artist: 'Artista de demonstração',
                  album: 'Horizontes',
                  year: 2004,
                  genre: 'Rock',
                  duration: Duration(minutes: 4),
                ),
              ],
              favorites: const {'fixture'},
              onNavigate: (value) => destination = value,
            ),
          ),
        ),
      );
      expect(find.text('Sua coleção, em um só lugar'), findsOneWidget);
      await tester.tap(find.text('Músicas'));
      expect(destination, AppSection.songs);
      await tester.ensureVisible(find.text('Playlists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playlists'));
      expect(destination, AppSection.playlists);
      expect(tester.takeException(), isNull);
    });
  }
}
