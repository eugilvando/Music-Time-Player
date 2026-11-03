import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/design_icon.dart';
import 'package:music_time/presentation/icon_catalog.dart';
import 'package:music_time/presentation/icon_settings.dart';
import 'package:music_time/presentation/settings_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Icon settings belong to General and keep customization sections intact',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPage(
              settings: settings,
              onAddFiles: () {},
              trackCount: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(IconSettings), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPage(
              key: const ValueKey('custom'),
              settings: settings,
              onAddFiles: () {},
              trackCount: 0,
              initialCategory: SettingsCategory.customization,
              onCustomizeHome: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(IconSettings), findsNothing);
      expect(find.byKey(const ValueKey('style.vinyl')), findsOneWidget);
      expect(find.text('Página inicial · personalizar seções'), findsOneWidget);
      expect(tester.takeException(), isNull);
      settings.dispose();
    },
  );

  test(
    'Existing and invalid preferences retain the current filled default',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      expect(settings.iconPack, 'current');
      expect(settings.iconStyle, 'filled');
      await settings.updateVisual('icon_pack', 'unknown');
      await settings.updateVisual('icon_style', 'unknown');
      expect(settings.iconPack, 'current');
      expect(settings.iconStyle, 'filled');
      settings.dispose();
    },
  );
  test(
    'Icon choice survives reload and general reset restores defaults',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      await settings.updateVisual('icon_pack', 'phosphor');
      await settings.updateVisual('icon_style', 'outlined');
      final restored = AppSettings(prefs);
      expect(restored.iconPack, 'phosphor');
      expect(restored.iconStyle, 'outlined');
      await restored.resetGeneral();
      expect(restored.iconPack, 'current');
      expect(restored.iconStyle, 'filled');
      settings.dispose();
      restored.dispose();
    },
  );
  test('Every application action has bundled equivalents in both styles', () {
    final references = <String>{};
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.dart') &&
                  !f.path.endsWith('icon_catalog.dart'),
            )) {
      references.addAll(
        RegExp(r'Icons\.([a-zA-Z0-9_]+)')
            .allMatches(file.readAsStringSync())
            .map((m) => m[1]!),
      );
    }
    final catalog = File('lib/presentation/icon_catalog.dart')
        .readAsStringSync();
    for (final name in references) {
      expect(catalog, contains('Icons.$name:'), reason: name);
    }
    for (final icon in iconCatalog.keys) {
      for (final pack in ['solar', 'phosphor']) {
        for (final outlined in [false, true]) {
          final asset = MtIcon.assetFor(icon, pack, outlined: outlined)!;
          expect(File(asset).existsSync(), isTrue, reason: asset);
        }
      }
    }
  });
  testWidgets('All bundled SVG variants decode and render', (tester) async {
    for (final pack in ['solar', 'phosphor']) {
      for (final style in ['filled', 'outlined']) {
        await tester.pumpWidget(
          MaterialApp(
            home: MtIconTheme(
              pack: pack,
              style: style,
              child: Scaffold(
                body: Wrap(
                  children: [
                    for (final icon in iconCatalog.keys) MtIcon(icon, size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$pack $style');
        expect(find.byType(SvgPicture), findsNWidgets(iconCatalog.length));
      }
    }
  });
  testWidgets('Const icons react live, including an open dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: settings,
        builder: (context, _) => MaterialApp(
          builder: (context, child) => MtIconTheme(
            pack: settings.iconPack,
            style: settings.iconStyle,
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                    content: MtIcon(Icons.play_arrow, semanticLabel: 'Play'),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNothing);
    await settings.updateVisual('icon_pack', 'solar');
    await tester.pumpAndSettle();
    expect(
      (tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
              as SvgAssetLoader)
          .assetName,
      endsWith('play-bold.svg'),
    );
    await settings.updateVisual('icon_style', 'outlined');
    await tester.pumpAndSettle();
    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      (picture.bytesLoader as SvgAssetLoader).assetName,
      endsWith('play-linear.svg'),
    );
    expect(picture.semanticsLabel, 'Play');
    settings.dispose();
  });
  testWidgets('Settings selects pack and style without restarting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IconSettings(settings: settings)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('icons.pack.current')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phosphor').last);
    await tester.pumpAndSettle();
    expect(settings.iconPack, 'phosphor');
    await tester.tap(find.byKey(const ValueKey('icons.style.filled')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contorno').last);
    await tester.pumpAndSettle();
    expect(settings.iconStyle, 'outlined');
    expect(find.byType(SvgPicture), findsNWidgets(6));
    expect(tester.takeException(), isNull);
    settings.dispose();
  });
  testWidgets(
    'Favourite state remains distinguishable and sizing is preserved',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MtIconTheme(
            pack: 'solar',
            child: Scaffold(
              body: Row(
                children: [
                  MtIcon(Icons.favorite, size: 28, color: Colors.red),
                  MtIcon(Icons.favorite_border, size: 28),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pictures = tester
          .widgetList<SvgPicture>(find.byType(SvgPicture))
          .toList();
      expect(
        (pictures[0].bytesLoader as SvgAssetLoader).assetName,
        endsWith('heart-bold.svg'),
      );
      expect(
        (pictures[1].bytesLoader as SvgAssetLoader).assetName,
        endsWith('heart-linear.svg'),
      );
      expect(tester.getSize(find.byType(SvgPicture).first), const Size(28, 28));
    },
  );
}
