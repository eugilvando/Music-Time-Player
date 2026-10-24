import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/presentation/resizable_side_panel.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('panel drag resizes, persists and respects available width', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    addTearDown(settings.dispose);
    Widget page(double maxWidth) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: ResizableSidePanel(
            settings: settings,
            preference: 'queue_panel_width',
            defaultWidth: 360,
            maxWidth: maxWidth,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pumpWidget(page(600));
    final panel = find.byType(ResizableSidePanel);
    final handle = find.byKey(const ValueKey('queue_panel_width.resize'));
    expect(tester.getSize(panel).width, 360);
    await tester.drag(handle, const Offset(-120, 0));
    await tester.pumpAndSettle();
    final width = tester.getSize(panel).width;
    expect(width, greaterThan(440));
    expect(settings.visualNumber('queue_panel_width', 0), width);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page(400));
    expect(tester.getSize(panel).width, 400);
    await tester.drag(handle, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).width, 280);
    expect(tester.takeException(), isNull);
  });
}
