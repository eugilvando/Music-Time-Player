import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:music_time/presentation/settings_dialog.dart';

void main() {
  test('restaurar aparência preserva equalizador de reprodução', () async {
    SharedPreferences.setMockInitialValues({
      'visual.eq_enabled': true,
      'visual.eq_60': 3.0,
      'visual.font_body': 20.0,
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    await settings.resetVisual();
    expect(settings.visualBool('eq_enabled', fallback: false), isTrue);
    expect(settings.visualNumber('eq_60', 0), 3);
    expect(settings.visualNumber('font_body', 14), 14);
    settings.dispose();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'favorito de álbum legado pode ser removido pela nova identidade',
    () async {
      final settings = AppSettings(await SharedPreferences.getInstance());
      addTearDown(settings.dispose);
      await settings.persist('collections.favorites', [
        'album:old',
        'artist:Preservado',
      ]);
      await settings.favoriteCollection('album:new', aliases: ['album:old']);
      expect(settings.collectionFavorites, {'artist:Preservado'});
      await settings.favoriteCollection('album:new', aliases: ['album:old']);
      expect(settings.collectionFavorites, {'artist:Preservado', 'album:new'});
    },
  );

  test('tema e cor são restaurados ao recriar configurações', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(prefs);
    addTearDown(settings.dispose);
    expect(settings.mode, ThemeMode.dark);
    await settings.update(theme: ThemeMode.system);
    await settings.update(color: 0xFF448AFF);
    final restored = AppSettings(prefs);
    addTearDown(restored.dispose);
    expect(restored.mode, ThemeMode.system);
    expect(restored.accent, 0xFF448AFF);
    expect(settings.error, isNull);
  });

  test('preferências inválidas usam padrão escuro e coral', () async {
    SharedPreferences.setMockInitialValues({'theme': 'inválido', 'accent': 1});
    final settings = AppSettings(await SharedPreferences.getInstance());
    addTearDown(settings.dispose);
    expect(settings.mode, ThemeMode.dark);
    expect(settings.accent, 0xFFFF7668);
  });

  testWidgets('Configurações reúne biblioteca e aparência em tela pequena', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(await SharedPreferences.getInstance());
    addTearDown(settings.dispose);
    var additions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            settings: settings,
            trackCount: 3,
            onAddFiles: () => additions++,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('settings.general')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings.general')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Escuro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claro').last);
    await tester.pumpAndSettle();
    expect(settings.mode, ThemeMode.light);
    await tester.ensureVisible(find.byKey(const ValueKey('settings.library')));
    await tester.tap(find.byKey(const ValueKey('settings.library')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('3 músicas na biblioteca'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('3 músicas na biblioteca'), findsOneWidget);
    expect(find.text('Adicionar músicas locais'), findsNothing);
    expect(find.text('Adicionar pasta de músicas'), findsNothing);
    expect(additions, 0);
    expect(tester.takeException(), isNull);
  });
}
