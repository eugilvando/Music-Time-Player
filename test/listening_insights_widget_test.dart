import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/infrastructure/lastfm.dart';
import 'package:music_time/library/listening_insights.dart';
import 'package:music_time/main.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/listening_insights_page.dart';
import 'package:music_time/presentation/listening_playlist_dialog.dart';
import 'package:music_time/presentation/navigation.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/flutter_sdk.dart';

class CachedInsights extends ListeningInsightsRepository {
  CachedInsights(LibraryStore store, this.report)
    : super(store, () async => throw StateError('Network must not run'));
  final ListeningReport report;
  @override
  Future<ListeningReport?> cached(String user, String period) async =>
      user == report.user ? report : null;
}

ListeningReport fixture() {
  final end = DateTime.now().toUtc();
  return aggregateListening((
    base: null,
    user: 'fixture',
    from: end.subtract(const Duration(days: 30)),
    until: end,
    previousFrom: end.subtract(const Duration(days: 60)),
    events: [
      for (var i = 0; i < 40; i++)
        LastFmTrack(
          'First Light',
          'Northbound',
          'After the Rain',
          end.subtract(Duration(days: i % 20 + 1)),
        ),
      for (var i = 0; i < 20; i++)
        LastFmTrack(
          'Moving Lines',
          'Lina Vale',
          'Golden Hour',
          end.subtract(Duration(days: i % 15 + 1)),
        ),
      LastFmTrack(
        'Missing',
        'Other',
        'Unknown',
        end.subtract(const Duration(days: 1)),
      ),
    ],
    nextPage: 2,
    totalPages: 1,
    complete: true,
    invalid: 0,
  ));
}

const catalog = [
  Track(
    id: 'first',
    localPath: 'C:/fixture/first.wav',
    title: 'First Light',
    artist: 'Northbound',
    album: 'After the Rain',
  ),
  Track(
    id: 'second',
    localPath: 'C:/fixture/second.wav',
    title: 'Moving Lines',
    artist: 'Lina Vale',
    album: 'Golden Hour',
  ),
];

Future<void> settleInsights(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test('Insights is immediately after History in sidebar navigation', () {
    expect(
      AppSection.values.indexOf(AppSection.insights),
      AppSection.values.indexOf(AppSection.history) + 1,
    );
  });
  for (final language in ['en', 'pt']) {
    for (final width in [480.0, 1440.0]) {
      testWidgets(
        'Insights cached dashboard and reports work in $language at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({
            'lastfm.profile_user': 'fixture',
            'visual.offline_only': true,
          });
          final settings = AppSettings(await SharedPreferences.getInstance());
          final store = (await tester.runAsync(
            () => LibraryStore.open(':memory:'),
          ))!;
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('pt')],
              localizationsDelegates: const [
                ...GlobalMaterialLocalizations.delegates,
                UiLanguageDelegate(),
              ],
              theme: musicTimeTheme(Brightness.dark, const Color(0xffff7668)),
              home: Scaffold(
                body: ListeningInsightsPage(
                  repository: CachedInsights(store, fixture()),
                  settings: settings,
                  store: store,
                  catalog: catalog,
                  catalogRevision: 0,
                  availableOffline: () async => {'first', 'second'},
                  onPlay: (_, _, _) async {},
                  onSaved: () {},
                  onConfigure: () {},
                  onOpen: (_, _) {},
                ),
              ),
            ),
          );
          await settleInsights(tester);
          expect(find.text('61'), findsOneWidget);
          expect(
            find.text(
              language == 'en'
                  ? 'Offline · saved data'
                  : 'Offline · dados salvos',
            ),
            findsOneWidget,
          );
          final reports = find.widgetWithText(
            ChoiceChip,
            language == 'en' ? 'Reports' : 'Relatórios',
          );
          await tester.ensureVisible(reports);
          await tester.tap(reports);
          await tester.pump();
          expect(
            find.text(
              language == 'en' ? 'Listening reports' : 'Relatórios de escuta',
            ),
            findsOneWidget,
          );
          if (language == 'en' && width == 480) {
            final period = find.byKey(const ValueKey('insights.period.30.0'));
            await tester.ensureVisible(period);
            await tester.tap(period);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Custom dates').last);
            await tester.pumpAndSettle();
            expect(find.byType(DateRangePickerDialog), findsOneWidget);
            Navigator.of(tester.element(find.byType(DateRangePickerDialog)))
                .pop();
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('insights.period.30.1')),
              findsOneWidget,
            );
            expect(find.text('Last 30 days'), findsOneWidget);
            expect(find.text('61'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(store.close);
          settings.dispose();
        },
      );
    }
  }
  testWidgets(
    'playlist preview saves matched IDs only and never starts playback',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      await tester.runAsync(() => store.addTracks(catalog));
      var played = 0, saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [UiLanguageDelegate()],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => ListeningPlaylistDialog(
                    report: fixture(),
                    catalog: catalog,
                    store: store,
                    offlineIds: const {'first'},
                    onPlay: (_, _, _) async {
                      played++;
                    },
                    onSaved: () => saved++,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settleInsights(tester);
      expect(find.textContaining('2 matched'), findsOneWidget);
      expect(find.textContaining('1 need review'), findsOneWidget);
      expect((await tester.runAsync(store.playlists))!, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Save playlist · 2'));
      await settleInsights(tester);
      final playlists = (await tester.runAsync(store.playlists))!;
      expect(playlists.length, 1);
      expect(
        (await tester.runAsync(
          () => store.playlistTrackIds(playlists.single['id'] as int),
        ))!,
        ['first', 'second'],
      );
      expect(played, 0);
      expect(saved, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'playlist dialog stays usable at small width and Play now does not save',
    (tester) async {
      tester.view.physicalSize = const Size(480, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      var played = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [UiLanguageDelegate()],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => ListeningPlaylistDialog(
                    report: fixture(),
                    catalog: catalog,
                    store: store,
                    offlineIds: const {'first'},
                    offlineOnly: true,
                    onPlay: (values, _, _) async {
                      expect(values.single.id, 'first');
                      played++;
                    },
                    onSaved: () => fail('Unexpected save'),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settleInsights(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Play now'));
      await settleInsights(tester);
      expect(played, 1);
      expect((await tester.runAsync(store.playlists))!, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.close);
    },
  );
  testWidgets('capture implemented Listening Insights dashboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final font in {
      'Material Symbols Rounded': 'MaterialSymbolsRounded',
      'Inter': 'Inter',
      'Bricolage Grotesque': 'BricolageGrotesque',
    }.entries) {
      await tester.runAsync(() async {
        final bytes = await File('assets/fonts/${font.value}.ttf')
            .readAsBytes();
        await (FontLoader(
          font.key,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
    }
    await tester.runAsync(() async {
      final bytes = await File(materialIconFontPath()).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });
    SharedPreferences.setMockInitialValues({'lastfm.profile_user': 'fixture'});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [UiLanguageDelegate()],
          theme: musicTimeTheme(Brightness.dark, const Color(0xffff7668)),
          home: Scaffold(
            body: ListeningInsightsPage(
              repository: CachedInsights(store, fixture()),
              settings: settings,
              store: store,
              catalog: catalog,
              catalogRevision: 0,
              availableOffline: () async => {'first'},
              onPlay: (_, _, _) async {},
              onSaved: () {},
              onConfigure: () {},
              onOpen: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await settleInsights(tester);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/listening-insights').create(recursive: true);
      await File('build/listening-insights/dashboard.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.close);
    settings.dispose();
  });
}
