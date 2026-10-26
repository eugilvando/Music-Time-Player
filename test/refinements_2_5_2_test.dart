import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/application/player_controller.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/presentation/about_page.dart';
import 'package:music_time/presentation/settings_dialog.dart';
import 'package:music_time/presentation/ui_language.dart';
import 'package:music_time/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlayerController fixture() {
    MediaKit.ensureInitialized(
      libmpv: Platform.environment['MUSIC_TIME_LIBMPV'],
    );
    final p = PlayerController();
    addTearDown(p.dispose);
    const a = Track(id: 'a', title: 'A', artist: 'Artist');
    const b = Track(id: 'b', title: 'B', artist: 'Artist');
    p.queue.addAll([a, b, a, b]);
    p.queueKeys.addAll([-4, -3, -2, -1]);
    p.queueIndex = 2;
    p.current = a;
    p.position = const Duration(seconds: 31);
    return p;
  }

  test('disabling shuffle restores original occurrences and preserves active playback position', () {
    final p = fixture();
    p.toggleShuffle();
    expect(p.queueKeys.first, -2);
    p.reorderQueue(3, 1);
    p.toggleShuffle();
    expect(p.queueKeys, [-4, -3, -2, -1]);
    expect(p.queueIndex, 2);
    expect(p.current!.id, 'a');
    expect(p.position.inSeconds, 31);
    p.toggleShuffle();
    p.toggleShuffle();
    expect(p.queueKeys, [-4, -3, -2, -1]);
  });
  test('added and removed occurrences survive restoration without resurrecting removed entries', () async {
    final p = fixture();
    p.toggleShuffle();
    await p.enqueue(
      const Track(id: 'next', title: 'Next', artist: 'Artist'),
      asNext: true,
    );
    await p.enqueue(const Track(id: 'last', title: 'Last', artist: 'Artist'));
    await p.removeQueueEntry(p.queueKeys.indexOf(-4));
    p.toggleShuffle();
    expect(p.queue.map((t) => t.id), ['b', 'a', 'next', 'b', 'last']);
    expect(p.queueKeys.where((k) => k < 0), [-3, -2, -1]);
    expect(p.queueIndex, 1);
  });
  test('validated shuffle snapshot restores original order after session recreation', () {
    final p = fixture();
    p.toggleShuffle();
    final tracks = List<Track>.of(p.queue);
    final snapshot = <String, dynamic>{
      'queue': tracks.map((t) => t.id).toList(),
      'order': p.originalQueueOrder,
    };
    final restored = fixture();
    restored.queue
      ..clear()
      ..addAll(tracks);
    restored.queueIndex = 0;
    restored.shuffle = true;
    restored.restoreShuffleSnapshot(snapshot);
    restored.toggleShuffle();
    expect(restored.queue.map((t) => t.id), ['a', 'b', 'a', 'b']);
    expect(restored.queueIndex, 2);
    final wrong = fixture()..shuffle = true;
    wrong.restoreShuffleSnapshot({
      'queue': ['other'],
      'order': [0],
    });
    expect(wrong.originalQueueOrder, [0, 1, 2, 3]);
  });
  test('About version matches the package version', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: $musicTimeVersion'),
    );
  });
  for (final language in ['en', 'pt']) {
    testWidgets(
      'About remains readable in $language at small width and large text',
      (tester) async {
        tester.view.physicalSize = const Size(480, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final settings = AppSettings(await SharedPreferences.getInstance());
        addTearDown(settings.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('pt')],
            localizationsDelegates: const [
              UiLanguageDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SettingsPage(
                settings: settings,
                onAddFiles: () {},
                trackCount: 0,
                initialCategory: SettingsCategory.about,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MusicTimeAbout), findsOneWidget);
        expect(find.byKey(const ValueKey('about.version')), findsOneWidget);
        expect(find.text(language == 'en' ? 'About' : 'Sobre'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
