import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/artist_similarity.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/artist_selection_dialog.dart';
import 'package:music_time/settings/app_settings.dart';

void main() {
  for (final seedCount in [0, 1, 2]) {
    testWidgets(
      'artist/track/album mix uses ranking rather than similarity: $seedCount',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final settings = AppSettings(await SharedPreferences.getInstance());
        final store = (await tester.runAsync(
          () => LibraryStore.open(':memory:'),
        ))!;
        var similarityCalls = 0, rankingCalls = 0;
        List<Track>? played;
        String? title;
        const a = Track(id: 'a', title: 'A', artist: 'Band');
        const b = Track(id: 'b', title: 'B', artist: 'Band');
        const other = Track(id: 'c', title: 'C', artist: 'Other');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showArtistSelection(
                    context,
                    artist: 'Band',
                    radio: false,
                    action: 'play',
                    seeds: [a, b].take(seedCount).toList(),
                    seedLabel: seedCount == 0 ? null : 'Seed title',
                    eligible: [a, b, other],
                    settings: settings,
                    similarity: ArtistSimilarity(store, () async {
                      similarityCalls++;
                      throw StateError('must not query similarity for mixes');
                    }),
                    ranking: (artist, eligible, count, refresh) async {
                      rankingCalls++;
                      expect(artist, 'Band');
                      expect(eligible, [a, b, other]);
                      return (tracks: [b, a], remoteMatches: 2);
                    },
                    onPlay: (tracks, index, name) async {
                      played = tracks;
                      title = name;
                    },
                    onSave: (_) async {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(played, [b, a]);
        expect(title, 'Artist mix · Band');
        expect(rankingCalls, 1);
        expect(similarityCalls, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(store.close);
        settings.dispose();
      },
    );
  }
}
