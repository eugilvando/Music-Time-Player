import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/presentation/home_page.dart';
import 'package:music_time/presentation/home_mix_picker.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'modelos de mixes selecionam, ordenam e persistem de forma independente',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'visual.home_mix_types': <String>['personal', 'favorites'],
      });
      final settings = AppSettings(await SharedPreferences.getInstance());
      addTearDown(settings.dispose);
      final mixes = <String, List<Track>>{
        'Mix de favoritos': [],
        'Mix pessoal': [],
        'Mix · Rock': [],
      };
      expect(orderedHomeMixes(mixes, settings).keys, [
        'Mix pessoal',
        'Mix de favoritos',
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => customizeHomeMixes(context, settings),
                child: const Text('Modelos'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Modelos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mix-type.personal')));
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(settings.visualList('home_mix_types', []), ['favorites']);
      expect(orderedHomeMixes(mixes, AppSettings(settings.preferences)).keys, [
        'Mix de favoritos',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('grade compacta mostra mais cards por linha que a grade normal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> render(String mode) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeCardLayout(
              mode: mode,
              children: List.generate(
                8,
                (i) => ColoredBox(
                  key: ValueKey(i),
                  color: Colors.blue,
                  child: Text('Card $i'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await render('grid');
    final normal = tester.getSize(find.byKey(const ValueKey(0))).width;
    expect(tester.getTopLeft(find.byKey(const ValueKey(4))).dy, greaterThan(0));
    await render('compact_grid');
    expect(
      tester.getSize(find.byKey(const ValueKey(0))).width,
      lessThan(normal),
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey(4))).dy, 0);
    tester.view.physicalSize = const Size(480, 800);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey(4))).dy, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('carrossel navega horizontalmente com as setas', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCardLayout(
            mode: 'carousel',
            children: List.generate(10, (i) => Card(child: Text('Card $i'))),
          ),
        ),
      ),
    );
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, 0);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, 0);
    expect(tester.takeException(), isNull);
  });

  test('modos por seção persistem independentemente', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = AppSettings(preferences);
    await settings.updateVisual(
      'home_modes',
      '{"recent":"carousel","favorites":"compact_grid"}',
    );
    final restored = AppSettings(preferences);
    expect(homeSectionMode(restored, 'recent'), 'carousel');
    expect(homeSectionMode(restored, 'favorites'), 'compact_grid');
    expect(homeSectionMode(restored, 'popular'), 'grid');
    settings.dispose();
    restored.dispose();
  });
}
