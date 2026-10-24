import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/main.dart';
import 'package:music_time/presentation/design_icon.dart';
import 'package:music_time/presentation/view_style_selector.dart';
import 'package:music_time/presentation/window_controls.dart';
import 'package:music_time/presentation/media_details_table.dart';
import 'package:music_time/presentation/media_card_size.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'detailed column selection persists independently and keeps title visible',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      addTearDown(settings.dispose);
      Widget page(String section) => MaterialApp(
        home: Scaffold(
          body: MediaCardSizeScope(
            value: 'Medium',
            onChanged: (_) {},
            settings: settings,
            contextKey: section,
            child: MediaDetailsTable(
              headers: const ['Title', 'Artist', 'Duration', ''],
              widths: const [300, 180, 100, 64],
              itemCount: 1,
              rowBuilder: (_) => const [
                Text('Example song'),
                Text('Example artist'),
                Text('3:42'),
                SizedBox(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(page('albums'));
      await tester.tap(find.byTooltip('Escolher colunas'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Artist'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('Artist'), findsNothing);
      expect(find.text('Example artist'), findsNothing);
      expect(find.text('Example song'), findsOneWidget);
      expect(
        settings.visualList('details_columns_albums_4', []),
        isNot(contains('1')),
      );
      await tester.pumpWidget(page('artists'));
      await tester.pumpAndSettle();
      expect(find.text('Artist'), findsOneWidget);
      expect(find.text('Example artist'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('view modal keeps content and actions inset from its surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: musicTimeTheme(Brightness.dark, const Color(0xffff7668)),
        home: Scaffold(
          body: Center(
            child: ViewStyleButton(
              value: 'grid',
              families: const {
                'grid': {'grid': 'Card Grid'},
                'list': {'compact': 'Compact List'},
              },
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.contentPadding, const EdgeInsets.fromLTRB(24, 8, 24, 24));
    expect(dialog.actionsPadding, const EdgeInsets.fromLTRB(24, 0, 24, 24));
    final surface = tester.getRect(find.byType(AlertDialog));
    final content = tester.getRect(find.byWidget(dialog.content!));
    expect(content.left - surface.left, greaterThanOrEqualTo(24));
    expect(surface.right - content.right, greaterThanOrEqualTo(24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('window close retains a right gutter and Figma-sized controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: musicTimeTheme(Brightness.dark, const Color(0xffff7668)),
        home: const Scaffold(
          body: Align(alignment: Alignment.topRight, child: WindowControls()),
        ),
      ),
    );
    final controls = tester.getRect(find.byType(WindowControls));
    final close = tester.getRect(find.byType(IconButton).last);
    expect(controls.right - close.right, 16);
    expect(close.size, const Size(32, 32));
    final symbol = tester.widget<Icon>(
      find.descendant(
        of: find.byType(MtIcon).last,
        matching: find.byType(Icon),
      ),
    );
    expect(symbol.icon!.fontFamily, 'Material Symbols Rounded');
    expect(symbol.fill, 1);
  });
}
