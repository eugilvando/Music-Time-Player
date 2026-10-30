import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/catalog_query.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/sidebar_settings.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/settings/sidebar_layout.dart';

Track cloud(
  String id, {
  String folder = '/drive/root:/Music',
  String name = 'song.mp3',
  String drive = 'ABCDEF1234567890',
}) => Track(
  id: id,
  title: id,
  artist: 'Artist',
  album: 'Album',
  driveId: drive,
  itemId: id,
  sourceProvider: 'onedrive',
  sourceAccount: drive,
  sourcePath: folder,
  fileName: name,
);

void main() {
  test('completed cloud scan retires missing paths within its account and folder only', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([
      cloud('kept'),
      cloud('missing'),
      cloud('sibling', folder: '/drive/root:/Music2'),
      cloud('other', drive: '1111111111111111'),
    ]);
    await store.database.insert('cloud_sources', {
      'id': 'source',
      'label': 'Music',
      'account': 'abcdef1234567890',
      'folder': '/drive/root:/Music',
      'active': 1,
    });
    await store.database.insert('cloud_sources', {
      'id': 'sibling-source',
      'label': 'Sibling',
      'account': 'abcdef1234567890',
      'folder': '/drive/root:/Music2',
      'active': 1,
    });
    final playlist = await store.importPlaylist('Keep references', [
      'kept',
      'missing',
      'kept',
    ]);
    await store.finishOneDriveFolder('abcdef1234567890', '/drive/root:/Music', {
      'kept',
    });
    expect(
      (await store.loadTracks()).map((t) => t.id),
      containsAll(['kept', 'sibling', 'other']),
    );
    expect((await store.loadTracks()).any((t) => t.id == 'missing'), isFalse);
    expect(
      (await store.catalogPage(
        CatalogSqlQuery(filters: CatalogFilters()..visibility = 'all'),
      )).tracks.any((t) => t.id == 'missing'),
      isFalse,
    );
    expect(
      (await store.loadTracks(includeHidden: true))
          .singleWhere((t) => t.id == 'missing')
          .available,
      isFalse,
    );
    expect(await store.playlistTrackIds(playlist), ['kept', 'missing', 'kept']);
    // Renaming a stable item updates the location without duplicating references.
    await store.addTracks([
      cloud('kept', name: 'renamed.mp3'),
      cloud('missing', name: 'replacement.mp3'),
    ]);
    await store.finishOneDriveFolder('abcdef1234567890', '/drive/root:/Music', {
      'kept',
      'missing',
    });
    expect(
      (await store.loadTracks())
          .singleWhere((t) => t.id == 'kept')
          .sourceFilePath,
      '/drive/root:/Music/renamed.mp3',
    );
    expect(
      (await store.loadTracks()).where((t) => t.id == 'missing'),
      hasLength(1),
    );
  });

  test('additional source removed entries leave catalog and return after rediscovery', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final track = cloud('webdav');
    await store.addTracks([track]);
    await store.finishSync(
      'webdav-source',
      Uri.parse('catalog:webdav-source'),
      ['webdav'],
    );
    expect(await store.loadTracks(), isEmpty);
    await store.addTracks([track]);
    expect((await store.loadTracks()).single.id, 'webdav');
  });

  test('manual hiding persists through rescan, edits and restart; SQL and memory agree', () async {
    final folder = await Directory.systemTemp.createTemp('music-time-hidden-');
    var store = await LibraryStore.open('${folder.path}/library.db');
    const a = Track(
      id: 'a',
      title: 'A',
      artist: 'Artist',
      localPath: 'C:/A.mp3',
    );
    const b = Track(
      id: 'b',
      title: 'B',
      artist: 'Artist',
      localPath: 'C:/B.mp3',
    );
    try {
      await store.addTracks([a, b]);
      final playlist = await store.importPlaylist('Repeated', ['a', 'b', 'a']);
      await store.setFavorite('a', true);
      await store.setLibraryHidden(['a'], true);
      await store.addTracks([a, b]);
      await store.setUserMetadata(['a'], {'title': 'Edited'});
      await store.setUserMetadata(['a'], {}, clear: true);
      await store.close();
      store = await LibraryStore.open('${folder.path}/library.db');
      final all = await store.loadTracks(includeCovers: false);
      expect(all.singleWhere((t) => t.id == 'a').libraryHidden, isTrue);
      expect(
        all.singleWhere((t) => t.id == 'a').withCover(null).libraryHidden,
        isTrue,
      );
      final index = CatalogIndex(
        tracks: all,
        favorites: {'a'},
        offline: {},
        stats: {},
        sources: {},
      );
      for (final mode in ['visible', 'hidden', 'all']) {
        final filters = CatalogFilters()..visibility = mode;
        final page = await store.catalogPage(CatalogSqlQuery(filters: filters));
        expect(
          page.tracks.map((t) => t.id).toList(),
          index.query(filters).map((t) => t.id).toList(),
        );
      }
      expect(index.query(CatalogFilters()).map((t) => t.id), ['b']);
      expect(await store.playlistTrackIds(playlist), ['a', 'b', 'a']);
      expect(await store.favoriteIds(), contains('a'));
      await store.setLibraryHidden(['a'], false);
      expect(
        (await store.catalogPage(CatalogSqlQuery(filters: CatalogFilters())))
            .total,
        2,
      );
    } finally {
      await store.close();
      await folder.delete(recursive: true);
    }
  });

  test('visibility filter survives preferences serialization and source path is persistent', () {
    expect(
      CatalogFilters.fromJson(
        (CatalogFilters()..visibility = 'hidden').toJson(),
      ).visibility,
      'hidden',
    );
    expect(
      CatalogFilters.fromJson({'visibility': 'bad'}).visibility,
      'visible',
    );
    expect(
      const Track(
        id: 'local',
        title: '',
        artist: '',
        localPath: r'C:\Music\song.mp3',
      ).sourceFilePath,
      r'C:\Music\song.mp3',
    );
    expect(cloud('a').sourceFilePath, '/drive/root:/Music/song.mp3');
    expect(englishLabel('Somente itens ocultos'), 'Hidden items only');
    expect(portugueseLabel('Hide from library'), 'Ocultar da biblioteca');
  });

  testWidgets(
    'sidebar uses drag handles and switches and persists drag ordering',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SidebarSettings(settings: settings),
            ),
          ),
        ),
      );
      final reorder = tester.widget<ReorderableListView>(
        find.byKey(const ValueKey('sidebar.organizer')),
      );
      // Exercise the callback that Flutter invokes after dropping a dragged item.
      reorder.onReorderItem!(2, 0);
      await tester.pumpAndSettle();
      expect(
        settings.visualList('sidebar_order', sidebarItems).first,
        'library',
      );
      expect(find.byType(ReorderableDragStartListener), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('sidebar.visibility.library')),
      );
      await tester.pumpAndSettle();
      expect(
        settings.visualList('sidebar_items', sidebarItems),
        isNot(contains('library')),
      );
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
