import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/home_catalog.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_widget_test.dart' show waitForCatalog;

void main() {
  late AppSettings settings;
  late Map<String, HomeData> memory;
  final a = Track(
    id: 'a',
    title: 'Cached track',
    artist: 'Artist',
    album: 'Album',
    addedAt: DateTime(2026),
  );
  final b = Track(
    id: 'b',
    title: 'New track',
    artist: 'Artist',
    album: 'Album',
    addedAt: DateTime(2026),
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'visual.home_sections': ['favorite_tracks'],
      'visual.artist_photos': false,
    });
    settings = AppSettings(await SharedPreferences.getInstance());
    memory = {};
  });
  tearDown(() => settings.dispose());
  Widget page(
    List<Track> tracks,
    String revision, {
    String scope = 'all',
    Set<String>? offline,
  }) => MaterialApp(
    home: Scaffold(
      body: HomePage(
        index: CatalogIndex(
          tracks: tracks,
          favorites: tracks.map((t) => t.id).toSet(),
          offline: offline ?? {},
          stats: {},
          sources: {},
        ),
        tracks: tracks,
        settings: settings,
        memory: memory,
        cacheKey: revision,
        cacheScope: scope,
        onAction: (_, _) async {},
        onPlay: (_, _) async {},
        trackActions: (_) => const SizedBox(),
        onExplore: (_, _) {},
        onAddSource: () {},
        library: const SizedBox(),
      ),
    ),
  );

  testWidgets(
    'Home reuses its exact snapshot on revisit with an equivalent recreated index',
    (tester) async {
      await tester.pumpWidget(page([a], '1'));
      await tester.pumpAndSettle();
      final saved = memory.values.single;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page([a], '1'));
      expect(find.text('Cached track'), findsWidgets);
      expect(find.byKey(const ValueKey('home.refreshing')), findsNothing);
      expect(identical(memory.values.single, saved), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Home keeps cached content during background refresh and replaces it only on completion',
    (tester) async {
      await tester.pumpWidget(page([a], '1'));
      await tester.pumpAndSettle();
      final saved = memory.values.single;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page([a, b], '2'));
      expect(find.text('Cached track'), findsWidgets);
      expect(find.text('New track'), findsNothing);
      expect(find.byKey(const ValueKey('home.refreshing')), findsOneWidget);
      expect(identical(memory.values.single, saved), isTrue);
      await waitForCatalog(
        tester,
        () => memory.values.last.lists['values']!.length == 2,
      );
      expect(find.byKey(const ValueKey('home.refreshing')), findsNothing);
      expect(find.text('New track'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Home never reuses hidden tracks or a different filter scope', (
    tester,
  ) async {
    await tester.pumpWidget(page([a, b], '1'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page([b], '2', scope: 'source-b'));
    expect(find.text('Cached track'), findsNothing);
    expect(find.text('New track'), findsWidgets);
    await tester.pumpWidget(page([a, b], '3', offline: {'b'}));
    await waitForCatalog(
      tester,
      () => find.byKey(const ValueKey('home.refreshing')).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home.offline')));
    await tester.pump();
    expect(find.text('Cached track'), findsNothing);
    expect(find.text('New track'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
