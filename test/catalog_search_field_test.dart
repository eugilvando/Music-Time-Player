import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/presentation/catalog_search_field.dart';

void main() {
  testWidgets('Escape and clear button clear the query and preserve focus', (
    tester,
  ) async {
    final query = ValueNotifier('');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: query,
            builder: (_, value, _) => CatalogSearchField(
              value: value,
              onChanged: (value) => query.value = value,
            ),
          ),
        ),
      ),
    );
    final field = find.byType(TextField);
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.enterText(field, 'Artist');
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(query.value, isEmpty);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.enterText(field, 'Album');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(query.value, isEmpty);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    query.value = 'Playlist';
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'Playlist');
    await tester.pumpWidget(const SizedBox());
    query.dispose();
  });
}
