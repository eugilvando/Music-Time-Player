import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/playlists_dialog.dart';
import 'package:music_time/settings/app_settings.dart';

import 'catalog_widget_test.dart' show waitForCatalog;

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6X0AAAAASUVORK5CYII=',
);
void main() {
  testWidgets('playlist search filters loaded data without restarting reads', (
    tester,
  ) async {
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    await tester.runAsync(() async {
      await store.createPlaylist('Alfa');
      await store.createPlaylist('Beta');
    });
    Widget build(String query) => MaterialApp(
      home: Scaffold(
        body: PlaylistsPage(
          store: store,
          tracks: const [],
          query: query,
          onPlay: (_, _) {},
        ),
      ),
    );
    await tester.pumpWidget(build(''));
    await waitForCatalog(tester, () => find.text('Alfa').evaluate().isNotEmpty);
    final dynamic state = tester.state(find.byType(PlaylistsPage));
    final generation = state.loadGeneration;
    await tester.pumpWidget(build('Beta'));
    expect(state.loading, isFalse);
    expect(state.loadGeneration, generation);
    expect(find.text('Alfa'), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.close);
  });
  test('capa de playlist integra backup e remoção preserva faixas', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    const track = Track(
      id: 'a',
      title: 'A',
      artist: 'Artist',
      localPath: 'C:/fixture/a.mp3',
    );
    await store.addTracks([track]);
    final id = await store.importPlaylist('Lista', ['a', 'a']);
    await store.setPlaylistCover(id, png);
    expect((await store.playlists()).single['has_cover'], 1);
    expect((await store.playlists()).single.containsKey('cover'), isFalse);
    expect(await store.playlistCover(id), png);
    final prefs = await SharedPreferences.getInstance();
    final backup = await AppData.backup(store, prefs);
    expect(AppData.parse(backup)['schema'], 16);
    await store.setPlaylistCover(id, null);
    await AppData.restore(store, prefs, backup);
    expect(await store.playlistCover(id), png);
    await expectLater(
      store.setPlaylistCover(id, Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(await store.playlistCover(id), png);
    await store.setPlaylistCover(id, null);
    expect(await store.playlistCover(id), isNull);
    expect((await store.playlistEntries(id)).length, 2);
  });

  testWidgets(
    'lista de playlists ordena por quantidade e alterna grade persistente',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      final store = (await tester.runAsync(
        () => LibraryStore.open(':memory:'),
      ))!;
      const track = Track(
        id: 'a',
        title: 'A',
        artist: 'Artist',
        localPath: 'C:/fixture/a.mp3',
      );
      await tester.runAsync(() async {
        await store.addTracks([track]);
        await store.importPlaylist('Alfa', ['a', 'a']);
        await store.importPlaylist('Beta', ['a']);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistsPage(
              store: store,
              settings: settings,
              tracks: const [track],
              onPlay: (_, _) {},
            ),
          ),
        ),
      );
      await waitForCatalog(
        tester,
        () => find.text('Alfa').evaluate().isNotEmpty,
      );
      expect(
        tester.getTopLeft(find.text('Alfa')).dy,
        lessThan(tester.getTopLeft(find.text('Beta')).dy),
      );
      final toggle = find.byKey(const ValueKey('playlists.controls.toggle'));
      final right = tester.getTopRight(toggle).dx;
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.getTopRight(toggle).dx, right);
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('playlists.sort')),
          )
          .onChanged!('count');
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Beta')).dy,
        lessThan(tester.getTopLeft(find.text('Alfa')).dy),
      );
      await tester.tap(find.byKey(const ValueKey('playlists.view')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Grid'));
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(settings.visualChoice('playlists_view', ''), 'grid');
      expect(settings.visualChoice('playlists_sort', ''), 'count');
      await tester.tap(find.byTooltip('Ordem crescente'));
      await tester.pumpAndSettle();
      expect(
        settings.visualBool('playlists_descending', fallback: false),
        isTrue,
      );
      final backup = (await tester.runAsync(
        () => AppData.backup(store, settings.preferences),
      ))!;
      expect(
        AppData.parse(backup)['preferences']['visual.playlists_descending'],
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      await tester.runAsync(store.close);
    },
  );
}
