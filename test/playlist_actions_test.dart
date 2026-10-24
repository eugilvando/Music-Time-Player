import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/playlist_pending_items.dart';

void main() {
  testWidgets('playlist merges track actions and supports right click', (
    tester,
  ) async {
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    addTearDown(() async => tester.runAsync(store.close));
    const track = Track(id: 'one', title: 'Song', artist: 'Artist');
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistPendingItems(
            store: store,
            id: 1,
            rows: const [
              {'id': 1, 'track_id': 'one'},
            ],
            queue: const [track],
            busy: false,
            onChanged: (work) => work(),
            onPlay: (_, _) {},
            trackActions: (_) => PopupMenuButton<String>(
              onSelected: (value) => selected = value,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'favorite', child: Text('Favorite track')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Favorite track'), findsOneWidget);
    expect(find.text('Remove from playlist'), findsOneWidget);
    await tester.tap(find.text('Favorite track'));
    await tester.pumpAndSettle();
    expect(selected, 'favorite');
    await tester.tap(
      find.text('Song'),
      kind: PointerDeviceKind.mouse,
      buttons: 2,
    );
    await tester.pumpAndSettle();
    expect(find.text('Favorite track'), findsOneWidget);
    expect(find.text('Remove from playlist'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
