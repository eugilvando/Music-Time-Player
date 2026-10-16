import 'package:flutter/material.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/sources/additional_sources.dart';
import 'package:music_time/sources/provider_connections.dart';
import 'package:music_time/presentation/additional_source_settings.dart';
import 'package:music_time/presentation/sources_dialog.dart';

import 'provider_auth_test.dart' show MemoryVault;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/home_catalog.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/presentation/home_mix_picker.dart';
import 'package:music_time/presentation/information_cards.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/settings/app_settings.dart';

void main() {
  const tracks = [
    Track(id: 'a', title: 'First', artist: 'Alpha', year: 1985),
    Track(id: 'b', title: 'Second', artist: 'Beta', year: 1995),
    Track(id: 'c', title: 'Third', artist: 'Gamma', year: 2005),
  ];
  CatalogIndex index() => CatalogIndex(
    tracks: tracks,
    favorites: {},
    offline: {},
    stats: {},
    sources: {},
  );
  Widget app(Widget child) => MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('pt')],
    localizationsDelegates: const [
      UiLanguageDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(body: child),
  );
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'visual.home_sections': ['mixes'],
      'visual.home_mix_types': ['artists', 'decades'],
    }),
  );
  testWidgets('Every new source form is usable in English without connecting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final prefs = await SharedPreferences.getInstance();
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final client = MockClient((_) async => http.Response('', 503));
    final sources = AdditionalSources(prefs, store, MemoryVault(), client);
    for (final type in additionalSourceTypes.keys) {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  addAdditionalSource(context, sources, type, () {}),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Add ${additionalSourceTypes[type]}'), findsOneWidget);
      expect(find.text('Source name'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    sources.dispose();
    client.close();
    await tester.runAsync(store.close);
  });
  testWidgets(
    'OneDrive status and setup instructions use the selected language',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = await SharedPreferences.getInstance();
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final providers = ProviderConnections(
        prefs,
        store,
        vault: MemoryVault(),
        client: MockClient((_) async => http.Response('', 503)),
      );
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: ProviderSettingsPage(
              providers: providers,
              onImported: () {},
              onlyMicrosoft: true,
              sourceOnly: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('OneDrive disconnected'), findsOneWidget);
      expect(find.text('No folder selected'), findsOneWidget);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Microsoft desktop app registration. Do not enter a password or client secret.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      providers.dispose();
      await tester.runAsync(store.close);
    },
  );
  test(
    'Home has one artist selector and one period selector across decades',
    () {
      final result = prepareHome((
        index: index(),
        tracks: tracks,
        quick: 'all',
        limit: 20,
        lastfm: false,
      ));
      expect(
        result.mixes.keys.where((k) => homeMixType(k) == 'artists'),
        hasLength(1),
      );
      expect(
        result.mixes.keys.where((k) => homeMixType(k) == 'decades'),
        hasLength(1),
      );
      expect(englishLabel('Mixes por artista'), 'Artist mix');
      expect(englishLabel('Mixes por década'), 'Period mix');
      expect(englishLabel('Faixas: 25'), 'Tracks: 25');
      expect(englishLabel('Quantidade de itens: 12'), 'Item count: 12');
    },
  );
  testWidgets(
    'Artist mix selects an artist; Home stays scrollable while customizing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = AppSettings(await SharedPreferences.getInstance());
      addTearDown(settings.dispose);
      List<Track>? played;
      await tester.pumpWidget(
        app(
          HomePage(
            index: index(),
            tracks: tracks,
            settings: settings,
            onAction: (_, _) async {},
            onPlay: (values, _) async {
              played = values;
            },
            trackActions: (_) => const SizedBox(),
            onExplore: (_, _) {},
            onAddSource: () {},
            library: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Artist mix'), findsOneWidget);
      expect(find.text('Period mix'), findsOneWidget);
      expect(find.text('Recently added'), findsNothing);
      await tester.tap(find.text('Artist mix'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha').last);
      await tester.pumpAndSettle();
      expect(played, isNotEmpty);
      expect(played!.every((t) => t.artist == 'Alpha'), true);
      await tester.binding.setSurfaceSize(const Size(1200, 380));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Customize home'));
      await tester.pumpAndSettle();
      expect(
        find.text('Changes apply live. Scroll Home to preview your edits.'),
        findsOneWidget,
      );
      expect(find.textContaining('Item count:'), findsWidgets);
      final homeScroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.dragFrom(const Offset(180, 280), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(homeScroll.position.pixels, greaterThan(0));
      await tester.binding.setSurfaceSize(const Size(1200, 750));
      await tester.pumpAndSettle();
      final mixStyle = find.byKey(const ValueKey('home.style.mixes'));
      final family = find.descendant(
        of: mixStyle,
        matching: find.byKey(const ValueKey('view.family')),
      );
      await tester.ensureVisible(family);
      await tester.tap(family);
      await tester.pumpAndSettle();
      await tester.tap(find.text('List').last);
      await tester.pumpAndSettle();
      final styles = find.descendant(
        of: mixStyle,
        matching: find.byKey(const ValueKey('view.style')),
      );
      await tester.tap(styles);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detailed').last);
      await tester.pumpAndSettle();
      expect(homeSectionMode(settings, 'mixes'), 'detailed');
      await tester.tap(styles);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compact List').last);
      await tester.pumpAndSettle();
      expect(homeSectionMode(settings, 'mixes'), 'compact');
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Information summaries keep four cards in each row at desktop widths',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(
          const InformationCards(
            values: {
              'Tracks': '30000',
              'Albums': '2000',
              'Artists': '1200',
              'Sources': '7',
              'Cache': '10 GB',
            },
          ),
        ),
      );
      final cards = find.byType(Card);
      expect(cards, findsNWidgets(5));
      final first = tester.getTopLeft(cards.at(0));
      for (var i = 1; i < 4; i++) {
        expect(tester.getTopLeft(cards.at(i)).dy, first.dy);
      }
      expect(tester.getTopLeft(cards.at(4)).dy, greaterThan(first.dy));
      expect(tester.takeException(), isNull);
    },
  );
}
