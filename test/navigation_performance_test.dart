import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/library/local_similarity.dart';
import 'package:music_time/library/listening_insights.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/presentation/insights_sources_page.dart';
import 'package:music_time/presentation/listening_insights_page.dart';

import 'catalog_widget_test.dart' show drainCatalog;
import 'provider_auth_test.dart' show MemoryVault;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'similarity survives reopening and invalidates after metadata edits',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'music-time-similarity-',
      );
      var store = await LibraryStore.open('${dir.path}/catalog.db');
      try {
        await store.addTracks(const [
          Track(
            id: 'a',
            title: 'A',
            artist: 'Artist A',
            genre: 'Rock',
            localPath: 'fixture.mp3',
          ),
          Track(
            id: 'b',
            title: 'B',
            artist: 'Artist B',
            genre: 'Rock',
            localPath: 'fixture.mp3',
          ),
        ]);
        await store.saveCloudSource(
          'fixture',
          'fixture-account',
          '/music',
          'Fixture',
          true,
        );
        final values = await Future.wait(
          List.generate(4, (_) => localSimilarArtists(store, 'Artist A')),
        );
        expect(values.every((v) => v.single == 'artist b'), isTrue);
        final before = (await store.database.query('local_similarity_results'))
            .single;
        await store.close();
        store = await LibraryStore.open('${dir.path}/catalog.db');
        await store.saveCloudSource(
          'fixture',
          'fixture-account',
          '/music',
          'Fixture',
          true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(await localSimilarArtists(store, 'Artist A'), ['artist b']);
        expect(
          (await store.database.query('local_similarity_results')).single,
          before,
        );
        await store.addTracks(const [
          Track(
            id: 'b',
            title: 'B',
            artist: 'Artist B',
            genre: 'Jazz',
            localPath: 'fixture.mp3',
          ),
        ]);
        expect(await localSimilarArtists(store, 'Artist A'), isEmpty);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'Insights keeps source repositories and refresh guards after navigation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final providers = ProviderConnections(
        settings.preferences,
        store,
        vault: MemoryVault(),
      );
      final sources = InsightsSourceRepositories(store, providers);
      final lastfm = ListeningInsightsRepository(store, sources.localApi);
      Widget page() => MaterialApp(
        home: Scaffold(
          body: InsightsSourcesPage(
            providers: providers,
            repository: lastfm,
            sources: sources,
            settings: settings,
            store: store,
            catalog: const [],
            catalogRevision: 0,
            availableOffline: () async => {},
            onPlay: (_, _, _) async {},
            onSaved: () {},
            onConfigure: () {},
            onOpen: (_, _) {},
          ),
        ),
      );
      await tester.pumpWidget(page());
      await drainCatalog(tester);
      final first = tester
          .widget<ListeningInsightsPage>(find.byType(ListeningInsightsPage))
          .repository;
      expect(first.beginAutomaticRefresh('fixture', '30'), isTrue);
      expect(sources.brainz.beginAutomaticRefresh('fixture', '30'), isTrue);
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      await tester.pumpWidget(page());
      await drainCatalog(tester);
      final second = tester
          .widget<ListeningInsightsPage>(find.byType(ListeningInsightsPage))
          .repository;
      expect(second, same(first));
      expect(second.beginAutomaticRefresh('fixture', '30'), isFalse);
      expect(sources.brainz.beginAutomaticRefresh('fixture', '30'), isFalse);
      expect(
        sources.brainz.beginAutomaticRefresh('different-account', '30'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await drainCatalog(tester);
      providers.dispose();
      await tester.runAsync(store.close);
    },
  );
}
