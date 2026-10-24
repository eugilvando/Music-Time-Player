import 'dart:io';
import 'dart:ui' as image_ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/main.dart';
import 'package:music_time/persistence/app_data.dart';
import 'package:music_time/presentation/settings_card.dart';
import 'package:music_time/presentation/settings_dialog.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/flutter_sdk.dart';

void main() {
  test('font roles persist, enter backups and reset independently of general settings', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(prefs);
    addTearDown(settings.dispose);
    await settings.updateVisual('primary_font_family', 'Georgia');
    await settings.updateVisual('secondary_font_family', 'Verdana');
    final restored = AppSettings(prefs);
    addTearDown(restored.dispose);
    expect(restored.primaryFont, 'Georgia');
    expect(restored.secondaryFont, 'Verdana');
    final theme = musicTimeTheme(Brightness.dark, Colors.red, restored);
    expect(theme.textTheme.headlineLarge!.fontFamily, 'Georgia');
    expect(theme.textTheme.bodyMedium!.fontFamily, 'Verdana');
    expect(
      theme.filledButtonTheme.style!.textStyle!.resolve({})!.fontFamily,
      'Verdana',
    );
    final light = musicTimeTheme(Brightness.light, Colors.red, restored);
    expect(light.textTheme.titleMedium!.fontFamily, 'Georgia');
    expect(light.textTheme.bodySmall!.fontFamily, 'Verdana');
    expect(AppData.preferences(prefs)['visual.primary_font_family'], 'Georgia');
    expect(
      AppData.validPreferenceType('visual.primary_font_family', 'Georgia'),
      isTrue,
    );
    await restored.resetGeneral();
    expect(restored.primaryFont, 'Georgia');
    await restored.resetInterface();
    expect(restored.primaryFont, 'Bricolage Grotesque');
    expect(restored.secondaryFont, 'Inter');
  });

  test('unavailable stored font names fall back to bundled fonts', () async {
    SharedPreferences.setMockInitialValues({
      'visual.primary_font_family': 'Missing family',
      'visual.secondary_font_family': 'Missing family',
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    addTearDown(settings.dispose);
    expect(settings.primaryFont, 'Bricolage Grotesque');
    expect(settings.secondaryFont, 'Inter');
  });

  for (final width in [480.0, 1440.0]) {
    testWidgets(
      'font controls and settings card gutters remain usable at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final settings = AppSettings(await SharedPreferences.getInstance());
        addTearDown(settings.dispose);
        if (width == 1440) {
          await tester.runAsync(() async {
            for (final family in {
              'Inter': 'Inter',
              'Bricolage Grotesque': 'BricolageGrotesque',
              'Material Symbols Rounded': 'MaterialSymbolsRounded',
            }.entries) {
              await (FontLoader(family.key)..addFont(
                    rootBundle.load('assets/fonts/${family.value}.ttf'),
                  ))
                  .load();
            }
            await (FontLoader('MaterialIcons')..addFont(
                  Future.value(
                    ByteData.sublistView(
                      await File(materialIconFontPath()).readAsBytes(),
                    ),
                  ),
                ))
                .load();
          });
        }
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: AnimatedBuilder(
              animation: settings,
              builder: (context, _) => MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: musicTimeTheme(
                  Brightness.dark,
                  const Color(0xffff7668),
                  settings,
                ),
                home: Scaffold(
                  body: SettingsPage(
                    settings: settings,
                    trackCount: 0,
                    onAddFiles: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('settings.customization')));
        await tester.pumpAndSettle();
        final primary = find.byKey(
          const ValueKey('primary_font_family:Bricolage Grotesque'),
        );
        await tester.ensureVisible(primary);
        await tester.pumpAndSettle();
        final card = find
            .ancestor(of: primary, matching: find.byType(Card))
            .first;
        final fieldBounds = tester.getRect(primary),
            cardBounds = tester.getRect(card);
        expect(
          fieldBounds.left - cardBounds.left,
          greaterThanOrEqualTo(width == 480 ? 16 : 20),
        );
        expect(
          cardBounds.right - fieldBounds.right,
          greaterThanOrEqualTo(width == 480 ? 16 : 20),
        );
        if (width == 1440) {
          await tester.ensureVisible(card);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: image_ui.ImageByteFormat.png,
            );
            final file = File(
              'build/figma-review/settings-typography-2.0.1.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(primary);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Georgia').last);
        await tester.pumpAndSettle();
        expect(settings.primaryFont, 'Georgia');
        expect(settings.secondaryFont, 'Inter');
        expect(
          Theme.of(tester.element(find.byType(SettingsPage)))
              .textTheme
              .titleMedium!
              .fontFamily,
          'Georgia',
        );
        expect(find.byType(SettingsCard), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
