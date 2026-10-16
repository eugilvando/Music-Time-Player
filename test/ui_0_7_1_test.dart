import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/ports.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/offline/download_manager.dart';
import 'package:music_time/offline/media_cache.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/data_settings.dart';
import 'package:music_time/presentation/downloads_dialog.dart';
import 'package:music_time/presentation/settings_card.dart';
import 'package:music_time/presentation/sources_dialog.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;

class _Resolver implements MediaSourceResolver {
  @override
  Future<Uri> resolve(Track track) async =>
      Uri.https('fixture.invalid', '/audio');
}

Widget app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: const [Locale('en'), Locale('pt')],
  localizationsDelegates: const [
    UiLanguageDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: Scaffold(body: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Permanent and cache tabs show separate files without changing retention',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('music-time-tabs-'),
      ))!;
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      final cacheRoot = Directory('${root.path}/cache');
      final offlineRoot = Directory('${root.path}/offline');
      final cache = MediaCache(
        store,
        _Resolver(),
        directory: () async => cacheRoot,
      );
      final manager = DownloadManager(
        store,
        _Resolver(),
        directory: () async => offlineRoot,
        cache: cache,
      );
      const permanent = Track(
        id: 'permanent',
        title: 'Permanent Fixture',
        artist: 'Fixture',
        driveId: 'drive',
        itemId: 'one',
      );
      const cached = Track(
        id: 'cached',
        title: 'Cache Fixture',
        artist: 'Fixture',
        driveId: 'drive',
        itemId: 'two',
      );
      await tester.runAsync(() async {
        await cacheRoot.create();
        await offlineRoot.create();
        await store.addTracks([permanent, cached]);
        await store.selectOffline('Fixture selection', [permanent]);
        final saved = File('${offlineRoot.path}/saved.audio');
        await saved.writeAsBytes([1, 2, 3, 4]);
        await store.updateDownload(
          permanent.id,
          'complete',
          path: saved.path,
          received: 4,
          total: 4,
        );
        final temporary = File(
          '${cacheRoot.path}/${cache.key(cached.id)}.audio',
        );
        await temporary.writeAsBytes([1, 2, 3, 4]);
        await store.database.insert('media_cache', {
          'track_id': cached.id,
          'revision': cached.revision,
          'path': temporary.path,
          'bytes': 4,
          'cached_at': DateTime.now().toUtc().toIso8601String(),
        });
      });
      await tester.pumpWidget(
        app(DownloadsDialog(manager: manager, embedded: true)),
      );
      for (
        var i = 0;
        i < 60 && find.text('Permanent Fixture').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      expect(find.text('Permanent Fixture'), findsOneWidget);
      expect(find.text('Cache Fixture'), findsNothing);
      await tester.tap(find.text('Automatic cache'));
      await tester.pumpAndSettle();
      expect(find.text('Cache Fixture'), findsOneWidget);
      expect(find.text('Permanent Fixture'), findsNothing);
      await tester.tap(find.text('Permanent downloads'));
      await tester.pumpAndSettle();
      expect(find.text('Permanent Fixture'), findsOneWidget);
      expect(find.text('Cache Fixture'), findsNothing);
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const PageStorageKey('downloads.files.permanent')),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Permanent Fixture'), findsNothing);
      await tester.tap(
        find.byKey(const PageStorageKey('downloads.files.permanent')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Permanent Fixture'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      manager.dispose();
      cache.dispose();
      await tester.runAsync(() async {
        expect((await store.downloadTasks()).single['status'], 'complete');
        expect(await cache.rows(validOnly: true), hasLength(1));
        await store.close();
        await root.delete(recursive: true);
      });
    },
  );
  testWidgets('Data and Last.fm controls are grouped in settings cards', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        DataSettings(
          onBackup: () async {},
          onRestore: () async {},
          onReset: () async {},
          storage: const Text('Storage Fixture'),
        ),
      ),
    );
    for (final label in [
      'Export backup',
      'Storage Fixture',
      'Reset the entire app',
    ]) {
      final item = find.text(label);
      expect(item, findsOneWidget);
      expect(
        find.ancestor(of: item, matching: find.byType(SettingsCard)),
        findsOneWidget,
      );
    }
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    final providers = ProviderConnections(
      await SharedPreferences.getInstance(),
      store,
      vault: MemoryVault(),
      client: MockClient((_) async => http.Response('', 503)),
    );
    await tester.pumpWidget(
      app(
        ProviderSettingsPage(
          providers: providers,
          onImported: () {},
          onlyMicrosoft: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Advanced'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.text('Last.fm API key'),
        matching: find.byType(SettingsCard),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    providers.dispose();
    await tester.runAsync(store.close);
  });
}
