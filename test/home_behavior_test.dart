import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/catalog.dart';
import 'package:music_time/library/local_metadata.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/settings/app_settings.dart';

import 'catalog_widget_test.dart' show waitForCatalog;

void main() {
  testWidgets('início grande prepara mixes sem bloquear a interação', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'visual.home_sections': ['mixes'],
      'visual.home_mix_types': ['personal'],
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    final tracks = List.generate(
      1500,
      (i) => Track(
        id: '$i',
        title: 'Faixa $i',
        artist: 'Artista ${i % 10}',
        album: 'Álbum ${i % 100}',
      ),
    );
    final index = CatalogIndex(
      tracks: tracks,
      favorites: {},
      offline: {},
      stats: {},
      sources: {},
    );
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                onPressed: () => clicks++,
                child: const Text('Responder'),
              ),
              Expanded(
                child: HomePage(
                  index: index,
                  tracks: tracks,
                  settings: settings,
                  onAction: (_, _) async {},
                  onPlay: (_, _) async {},
                  trackActions: (_) => const SizedBox(),
                  onExplore: (_, _) {},
                  onAddSource: () {},
                  library: const SizedBox(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Responder'));
    await tester.pump();
    expect(clicks, 1);
    await waitForCatalog(
      tester,
      () => find.text('Mix pessoal').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
  const a = Track(
    id: 'a',
    title: 'Faixa A',
    artist: 'Artista A',
    album: 'Álbum A',
    year: 1995,
    genre: 'Rock',
  );
  const b = Track(
    id: 'b',
    title: 'Faixa B',
    artist: 'Artista B',
    album: 'Álbum B',
    year: 2020,
    genre: 'Pop',
  );
  test(
    'seções antigas migram favoritos sem reativar seções desabilitadas',
    () async {
      SharedPreferences.setMockInitialValues({
        'visual.home_sections': ['recent', 'favorites', 'mixes'],
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      expect(selectedHomeSections(settings), [
        'recent',
        'favorite_tracks',
        'favorite_albums',
        'mixes',
      ]);
      await settings.updateVisual('home_sections', ['favorite_tracks']);
      expect(selectedHomeSections(settings), ['favorite_tracks']);
      settings.dispose();
    },
  );

  testWidgets('mix toca direto, opções salvam tamanho e artista pede seletor', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'visual.home_sections': ['mixes'],
      'visual.home_mix_types': ['personal', 'artists'],
      'visual.home_mix_size': 2.0,
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    final index = CatalogIndex(
      tracks: [a, b],
      favorites: {},
      offline: {},
      stats: {},
      sources: {},
    );
    final plays = <List<Track>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            index: index,
            tracks: const [a, b],
            settings: settings,
            onAction: (_, _) async {},
            onPlay: (tracks, _) async => plays.add(tracks),
            trackActions: (_) => const SizedBox(),
            onExplore: (_, _) {},
            onAddSource: () {},
            library: const SizedBox(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mix pessoal'));
    await tester.pumpAndSettle();
    expect(plays.single.length, 2);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamanho dos mixes'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(1);
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(settings.visualNumber('home_mix_size', 20), 1);
    expect(plays.length, 1);
    await tester.tap(find.text('Mix pessoal'));
    await tester.pumpAndSettle();
    expect(plays.last.length, 1);
    await tester.tap(find.text('Artist mix'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.text(a.artist).last);
    await tester.pumpAndSettle();
    expect(plays.last.single.id, 'a');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets(
    'gênero e período selecionam antes de tocar; Last.fm respeita visibilidade',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'visual.home_sections': ['mixes'],
        'visual.home_mix_types': ['genres', 'decades', 'lastfm_overall'],
        'visual.home_mix_size': 2.0,
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      final index = CatalogIndex(
        tracks: [a, b],
        favorites: {},
        offline: {},
        stats: {},
        sources: {},
      );
      final plays = <List<Track>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(
              index: index,
              tracks: const [a, b],
              settings: settings,
              onAction: (_, _) async {},
              onPlay: (tracks, _) async => plays.add(tracks),
              trackActions: (_) => const SizedBox(),
              onExplore: (_, _) {},
              onAddSource: () {},
              library: const SizedBox(),
              lastfmMix: (_) async => [
                const Track(id: 'hidden', title: 'Hidden', artist: 'Hidden'),
                b,
                a,
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mix · Pop'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilterChip),
        ),
        findsNWidgets(2),
      );
      await tester.tap(find.text('Criar e reproduzir mix'));
      await tester.pumpAndSettle();
      expect(plays.last.single.id, 'b');
      await tester.ensureVisible(find.text('Mixes por década'));
      await tester.tap(find.text('Mixes por década'));
      await tester.pumpAndSettle();
      expect(find.byType(RangeSlider), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(plays.length, 1);
      await tester.ensureVisible(find.text('Last.fm · Mais ouvidas'));
      await tester.tap(find.text('Last.fm · Mais ouvidas'));
      await tester.pumpAndSettle();
      expect(plays.last.map((t) => t.id), ['b', 'a']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets('álbum favorito e faixa favorita ficam separados', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'visual.home_sections': ['favorite_tracks', 'favorite_albums'],
      'visual.home_modes':
          '{"favorite_tracks":"compact","favorite_albums":"compact"}',
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    final index = CatalogIndex(
      tracks: [a, b],
      favorites: {'b'},
      offline: {},
      stats: {},
      sources: {},
      collectionFavorites: {'album:${albumKey(a)}'},
    );
    CatalogGroup? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            index: index,
            tracks: const [a, b],
            settings: settings,
            onAction: (_, _) async {},
            onPlay: (_, _) async {},
            trackActions: (_) => const SizedBox(),
            onExplore: (_, group) => opened = group,
            onAddSource: () {},
            library: const SizedBox(),
          ),
        ),
      ),
    );
    expect(find.text('Faixas favoritas'), findsOneWidget);
    expect(find.text('Álbuns favoritos'), findsOneWidget);
    expect(find.text('Faixa B'), findsOneWidget);
    expect(find.text('Faixa A'), findsNothing);
    await tester.tap(find.text('Álbum A'));
    await tester.pump();
    expect(opened!.tracks.single.id, 'a');
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
