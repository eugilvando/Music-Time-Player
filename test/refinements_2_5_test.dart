import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/queue_navigation.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/listening_insights.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/alphabet_scrollbar.dart';
import 'package:music_time/presentation/home_skeleton.dart';
import 'package:music_time/presentation/player_bar.dart';
import 'package:music_time/presentation/listening_insights_page.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/catalog_browser.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;
import 'catalog_widget_test.dart' show waitForCatalog, drainCatalog;

import 'listening_insights_widget_test.dart' show fixture, settleInsights;

class BackgroundInsights extends ListeningInsightsRepository {
  BackgroundInsights(LibraryStore store, this.saved)
    : super(store, () async => throw StateError('fixture'));
  ListeningReport saved;
  int calls = 0;
  bool evicted = false;
  Completer<ListeningReport> pending = Completer();
  @override
  Future<ListeningReport?> cached(String user, String period) async =>
      evicted ? null : saved;
  @override
  Future<ListeningReport> load({
    required String user,
    required String period,
    required DateTime from,
    required DateTime until,
    required ListeningRequest request,
    ListeningReport? resume,
    int pageBudget = 250,
    void Function(int, int)? onProgress,
  }) async {
    calls++;
    saved = await pending.future;
    return saved;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('shuffle preserves current occurrence and duplicates in a visible stable order', () {
    final order = shuffledQueueOrder(8, 4, random: Random(12));
    expect(order.first, 4);
    expect(order.toSet(), Set.of(List.generate(8, (i) => i)));
    MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    );
    final player = PlayerController();
    addTearDown(player.dispose);
    const track = Track(id: 'same', title: 'Same', artist: 'Artist');
    player.queue.addAll(List.filled(8, track));
    player.queueKeys.addAll(List.generate(8, (i) => i));
    player.queueIndex = 4;
    player.current = track;
    player.toggleShuffle();
    expect(player.queueIndex, 0);
    expect(player.queueKeys.first, 4);
    expect(player.queueKeys.toSet().length, 8);
    expect(player.nextIndex, 1);
    expect(player.upcoming(7), player.queue.skip(1));
    player.toggleShuffle();
    expect(player.queueKeys, List.generate(8, (i) => i));
    expect(player.queueIndex, 4);
  });

  for (final grid in [false, true]) {
    testWidgets(
      'alphabet reaches a lazy ${grid ? 'grid' : 'list'} item without building the whole catalog',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final names = List.generate(
          1040,
          (i) => '${String.fromCharCode(65 + i ~/ 40)}-$i',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AlphabetScrollbar(
                controller: scroll,
                positions: alphabetPositions(names),
                itemCount: names.length,
                child: grid
                    ? GridView.builder(
                        controller: scroll,
                        itemCount: names.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisExtent: 80,
                            ),
                        itemBuilder: (_, i) => Text(names[i]),
                      )
                    : ListView.builder(
                        controller: scroll,
                        itemExtent: 60,
                        itemCount: names.length,
                        itemBuilder: (_, i) => Text(names[i]),
                      ),
              ),
            ),
          ),
        );
        final z = find.byKey(const ValueKey('alphabet.Z'));
        await tester.ensureVisible(z);
        await tester.tap(z);
        await tester.pumpAndSettle();
        expect(find.text('Z-1000'), findsOneWidget);
        expect(tester.getTopLeft(find.text('Z-1000')).dy, closeTo(0, 2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test('alphabet folds accents and groups symbols', () {
    expect(alphabetPositions(['Água', 'Âmbar', '2 discos', 'Época']), {
      'A': 0,
      '#': 2,
      'E': 3,
    });
  });

  testWidgets('alphabet jumps across SQL pages, preserving title sorting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'visual.catalog_page_size': '50'});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final tracks = List.generate(
      180,
      (i) => Track(
        id: 'az$i',
        title:
            '${['A', 'M', 'Z'][i ~/ 60]} ${(i % 60).toString().padLeft(3, '0')}',
        artist: 'Artist',
        localPath: 'C:/fixture/$i.mp3',
      ),
    );
    await tester.runAsync(() => store.addTracks(tracks));
    final providers = ProviderConnections(
      settings.preferences,
      store,
      vault: MemoryVault(),
    );
    final downloads = DownloadManager(store, providers);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogBrowser(
            tracks: tracks,
            favorites: {},
            store: store,
            settings: settings,
            downloads: downloads,
            query: '',
            onPlay: (_, _) async {},
            onAction: (_, _) async {},
            trackActions: (_) => const Icon(Icons.more_horiz),
            onAddSource: () {},
            onPlaylist: (_) {},
          ),
        ),
      ),
    );
    final state = tester.state<CatalogBrowserState>(
      find.byType(CatalogBrowser),
    );
    await waitForCatalog(
      tester,
      () =>
          !state.pageLoading &&
          !state.refreshing &&
          state.pageLetters.containsKey('Z'),
    );
    await tester.pump();
    expect(find.byType(AlphabetScrollbar), findsOneWidget);
    expect(state.pageLetters['Z'], 120);
    final z = find.byKey(const ValueKey('alphabet.Z'));
    await tester.scrollUntilVisible(
      z,
      100,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('alphabet.rail')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(z);
    await waitForCatalog(
      tester,
      () => !state.pageLoading && state.loadedOffset == 100,
    );
    await tester.pumpAndSettle();
    expect(find.text('Z 000'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await drainCatalog(tester);
    downloads.dispose();
    providers.dispose();
    settings.dispose();
    await tester.runAsync(store.close);
  });

  testWidgets('skeleton exposes loading and respects reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: HomeSkeleton()),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('home.skeleton')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'player keeps all enabled controls within half-screen widths and volume gap is 8',
    (tester) async {
      MediaKit.ensureInitialized(
        libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
      );
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final player = PlayerController();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [480.0, 700.0, 960.0, 1600.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: PlayerBar(
                controller: player,
                settings: settings,
                favorite: false,
                onFavorite: () {},
                onDetails: () {},
                onQueue: () {},
                onExpand: () {},
                onSave: () async {},
                onLyrics: () {},
                lastfmActive: true,
              ),
            ),
          ),
        );
        await tester.pump();
        final expand = find.byKey(const ValueKey('player.item.expand'));
        expect(tester.getRect(expand).right, lessThanOrEqualTo(width));
        expect(tester.getRect(expand).bottom, lessThanOrEqualTo(900));
        final mute = tester.getRect(find.byKey(const ValueKey('player.mute')));
        final slider = tester.getRect(
          find.byKey(const ValueKey('player.volume-slider')),
        );
        expect(slider.left - mute.right, 8);
        expect(tester.takeException(), isNull, reason: 'width $width');
      }
      tester.view.physicalSize = const Size(480, 600);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(480, 600),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              bottomNavigationBar: PlayerBar(
                controller: player,
                settings: settings,
                favorite: false,
                onFavorite: () {},
                onDetails: () {},
                onQueue: () {},
                onExpand: () {},
                onSave: () async {},
                onLyrics: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(PlayerBar)).height,
        lessThanOrEqualTo(180),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('player.item.expand')),
      );
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('player.item.expand'))).bottom,
        lessThanOrEqualTo(600),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      player.dispose();
      settings.dispose();
      await tester.pump(const Duration(seconds: 6));
    },
  );

  testWidgets(
    'Insights keeps saved data during refresh and only automatically refreshes once per selection per session',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'lastfm.profile_user': 'fixture',
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final repo = BackgroundInsights(store, fixture());
      Widget page() => MaterialApp(
        home: Scaffold(
          body: ListeningInsightsPage(
            repository: repo,
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
      await settleInsights(tester);
      expect(repo.calls, 1);
      expect(
        (tester.state(find.byType(ListeningInsightsPage)) as dynamic).data,
        repo.saved,
      );
      final refreshed = ListeningReport.fromJson({
        ...repo.saved.toJson(),
        'scrobbles': 81,
      });
      repo.pending.complete(refreshed);
      await settleInsights(tester);
      expect(
        (tester.state(
          find.byType(ListeningInsightsPage),
        ) as dynamic).data.scrobbles,
        81,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await settleInsights(tester);
      expect(repo.calls, 1);
      repo.pending = Completer();
      final refresh = find.byKey(const ValueKey('insights.refresh'));
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await settleInsights(tester);
      expect(repo.calls, 2);
      expect(
        (tester.state(
          find.byType(ListeningInsightsPage),
        ) as dynamic).data.scrobbles,
        81,
      );
      repo.pending.complete(refreshed);
      await settleInsights(tester);
      await tester.pumpWidget(const SizedBox());
      repo.evicted = true;
      repo.pending = Completer();
      await tester.pumpWidget(page());
      await settleInsights(tester);
      expect(
        repo.calls,
        3,
        reason: 'A missing/evicted cache must not leave an empty page for the rest of the session',
      );
      repo.pending.complete(refreshed);
      await settleInsights(tester);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );
}
