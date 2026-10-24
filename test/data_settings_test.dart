import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/presentation/data_settings.dart';
import 'package:music_time/presentation/home_page.dart';

void main() {
  testWidgets(
    'reset exige três confirmações e texto exato; cancelar não executa',
    (tester) async {
      var resets = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataSettings(
              onBackup: () async {},
              onRestore: () async {},
              onReset: () async {
                resets++;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Resetar todo o aplicativo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(resets, 0);
      await tester.tap(find.text('Resetar todo o aplicativo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Resetar e reiniciar'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('data.confirmation')),
        'RESETAR',
      );
      await tester.pump();
      await tester.tap(find.text('Resetar e reiniciar'));
      await tester.pumpAndSettle();
      expect(resets, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start again and restart'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Start again and restart'));
      await tester.pumpAndSettle();
      expect(resets, 1);
      await tester.pump(const Duration(seconds: 1));
    },
  );
  testWidgets(
    'cards da home respeitam a largura Medium do Figma e adaptam janelas pequenas',
    (tester) async {
      for (final width in [800.0, 480.0, 320.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: HomeCardGrid(
                    children: [
                      for (var i = 0; i < 8; i++)
                        ColoredBox(key: ValueKey('card-$i'), color: Colors.red),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final columns = ((width + 16) / (196 + 16)).floor().clamp(1, 100);
        final first = tester.getTopLeft(find.byKey(const ValueKey('card-0')));
        final last = tester.getTopLeft(
          find.byKey(ValueKey('card-${columns - 1}')),
        );
        final next = tester.getTopLeft(find.byKey(ValueKey('card-$columns')));
        expect(last.dy, first.dy);
        expect(next.dy, greaterThan(first.dy));
        expect(next.dx, first.dx);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
