import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/m3u8.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/presentation/playlist_import_review.dart';
import 'package:music_time/presentation/playlists_dialog.dart';

import 'catalog_widget_test.dart' show waitForCatalog;

void main() {
  const cloud = Track(
    id: 'a',
    title: 'Encontrada',
    artist: 'Autor',
    driveId: 'A',
    itemId: '1',
    sourcePath: '/drive/root:/Música',
    fileName: 'song.mp3',
  );
  const choice = Track(
    id: 'b',
    title: 'Escolhida',
    artist: 'Outro',
    localPath: 'C:/other.mp3',
  );
  test('relativos Symfonium e caminhos percent-encoded resolvem sem inferir título', () {
    final report = reviewM3u8(
      '../song.mp3\n/M%C3%BAsica/song.mp3',
      r'C:\Users\fixture\OneDrive\Música\_Playlists\list.m3u8',
      [cloud],
    );
    expect(report.unresolved, 0);
    expect(report.ids, ['a', 'a']);
  });
  testWidgets(
    'revisão localiza ou remove referências e mantém ordem/repetições',
    (tester) async {
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final report = reviewM3u8(
        '/Música/song.mp3\n/Música/missing.mp3\n/Música/remove.mp3\n/Música/song.mp3',
        'list.m3u8',
        [cloud, choice],
      );
      List<String>? imported;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  imported = await showDialog<List<String>>(
                    context: context,
                    builder: (_) => PlaylistImportReview(
                      report: report,
                      tracks: const [cloud, choice],
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(report.unresolved, 2);
      await tester.tap(
        find.widgetWithText(TextButton, 'Localizar faixa').first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Escolhida');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Escolhida'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('playlist.resolved.2')), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Localizar faixa'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Alterar faixa confirmada'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextButton, 'Localizar faixa'),
        findsNWidgets(2),
      );
      await tester.tap(find.byTooltip('Recolher faixa confirmada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover da importação').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importar faixas revisadas'));
      await tester.pumpAndSettle();
      expect(imported, ['a', 'b', 'a']);
      expect(cloud.fileName, 'song.mp3');
      expect(choice.localPath, 'C:/other.mp3');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cabeçalho de playlist toca ordem real, shuffle e ações extras', (
    tester,
  ) async {
    final store = (await tester.runAsync(() => LibraryStore.open(':memory:')))!;
    await tester.runAsync(() => store.addTracks([cloud, choice]));
    final id = (await tester.runAsync(
      () => store.importPlaylist('Lista de teste', ['a', 'b', 'a']),
    ))!;
    List<Track> played = [];
    var shuffled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistsPage(
            store: store,
            tracks: const [cloud, choice],
            initialPlaylist: id,
            onPlay: (values, index) => played = values,
            onShuffle: (values) {
              played = values;
              shuffled = true;
            },
          ),
        ),
      ),
    );
    await waitForCatalog(
      tester,
      () =>
          find.text('Lista de teste').evaluate().isNotEmpty &&
          find.widgetWithText(FilledButton, 'Reproduzir').evaluate().isNotEmpty,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reproduzir'));
    await tester.pump();
    expect(played.map((t) => t.id), ['a', 'b', 'a']);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Aleatório'));
    await tester.pump();
    expect(shuffled, true);
    await tester.tap(find.byKey(const ValueKey('playlist.actions')));
    await tester.pumpAndSettle();
    expect(find.text('Exportar playlist'), findsOneWidget);
    expect(find.text('Excluir playlist'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.close);
    await tester.pump();
  });
}
