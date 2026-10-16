import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/presentation/exit_confirmation.dart';
import 'package:music_time/presentation/ui_language.dart';

void main() {
  for (final language in ['en', 'pt']) {
    testWidgets('exit confirmation keeps explicit choices in $language', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('pt')],
          localizationsDelegates: const [
            UiLanguageDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showExitConfirmation(
                    context,
                    tasks: ['Downloads'],
                    unsaved: false,
                  );
                },
                child: const Text('Exit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();
      final keep = language == 'en' ? 'Keep open' : 'Manter aberto';
      final leave = language == 'en' ? 'Exit anyway' : 'Sair mesmo assim';
      expect(
        find.text('Downloads'),
        findsNothing,
      ); // Bullet keeps task visually distinct.
      expect(find.text('• ${uiForDownloads(language)}'), findsOneWidget);
      expect(find.text(leave), findsOneWidget);
      await tester.tap(find.text(keep));
      await tester.pumpAndSettle();
      expect(result, false);
      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(leave));
      await tester.pumpAndSettle();
      expect(result, true);
    });
  }
}

String uiForDownloads(String language) =>
    language == 'en' ? 'Downloads' : portugueseLabel('Downloads');
