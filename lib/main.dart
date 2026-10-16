import 'dart:io';

import 'presentation/startup_gate.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'presentation/app_shell.dart';
import 'settings/app_settings.dart';
import 'presentation/ui_language.dart';
import 'persistence/library_store.dart';
import 'persistence/app_data.dart';
import 'sources/microsoft_auth.dart';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Select the validation namespace before StartupGate reads the language.
  if (arguments.contains('--validation-profile')) {
    SharedPreferences.setPrefix('flutter.music_time.validation.');
  }
  runApp(
    StartupGate(
      initialize: (progress) => initializeMusicTime(arguments, progress),
    ),
  );
}

Future<Widget> initializeMusicTime(
  List<String> arguments,
  ValueChanged<String> progress,
) async {
  progress('Preparando o motor de áudio…');
  MediaKit.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow();
    await windowManager.setMinimumSize(const Size(480, 600));
  }
  final validation = arguments.contains('--validation-profile');
  progress('Carregando preferências…');
  final preferences = await SharedPreferences.getInstance();
  if (!validation && preferences.getBool('language_v6_migrated') != true) {
    await preferences.setString('visual.language', 'en');
    await preferences.setBool('language_v6_migrated', true);
  }
  final directory = validation
      ? Directory(
          path.join(Directory.systemTemp.path, 'music_time_validation_profile'),
        )
      : await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final startupClock = Stopwatch()..start();
  Future<void> log(String event) async {
    try {
      await File(
        path.join(directory.path, 'startup_diagnostics.log'),
      ).writeAsString(
        '${DateTime.now().toUtc().toIso8601String()} $event ${startupClock.elapsedMilliseconds}ms\n',
        mode: FileMode.append,
      );
    } catch (_) {
      /* Diagnostics must not block opening the app. */
    }
  }

  await log('database_open_start');
  late final LibraryStore store;
  try {
    store = await LibraryStore.open(
      path.join(directory.path, 'music_time.db'),
      onProgress: progress,
    );
    await log('database_open_complete');
  } catch (error) {
    await log('database_open_failed:${error.runtimeType}');
    rethrow;
  }
  if (arguments.contains('--migrate-library-only')) {
    await log('database_migration_complete');
    await store.close();
    exit(0);
  }
  // Explicit, offline maintenance entry point. Never run this automatically on
  // normal startup; the UI provides the same resumable operation in Settings.
  if (arguments.contains('--optimize-artwork-only')) {
    try {
      await log('artwork_optimization_start');
      var lastReported = 0;
      Future<void> maintenanceLog = Future.value();
      await store.artwork.optimize(
        onProgress: (state) {
          progress(
            state.compacting ? 'Compactando banco…' : 'Otimizando capas…',
          );
          if (state.processed - lastReported >= 1000 || state.compacting) {
            lastReported = state.processed;
            // No paths, provider metadata or credentials in maintenance logs.
            final event = state.compacting
                ? 'artwork_compaction_start'
                : 'artwork_converted_${state.processed}';
            maintenanceLog = maintenanceLog.then((_) => log(event));
          }
        },
      );
      await maintenanceLog;
      final bytes = await File(store.database.path).length();
      await log('artwork_optimization_complete_bytes_$bytes');
      await store.close();
      exit(0);
    } catch (error) {
      await log('artwork_optimization_failed:${error.runtimeType}');
      await store.close();
      exit(1);
    }
  }
  String? startupNotice;
  final maintenanceRequested = await AppData.requestFile(directory).exists();
  var maintenanceSucceeded = false;
  try {
    startupNotice = await AppData.applyPending(
      directory,
      store,
      preferences,
      validation
          ? const SystemVault(prefix: 'music_time.validation.')
          : const SystemVault(),
    );
    maintenanceSucceeded = startupNotice != null;
  } catch (_) {
    startupNotice = 'A operação de dados não foi concluída. Confira o backup, espaço em disco e cofre do Windows; tente novamente em Configurações → Dados.';
  }
  if (validation && maintenanceRequested) {
    await File(path.join(directory.path, 'maintenance-validation-result.txt'))
        .writeAsString(maintenanceSucceeded ? 'ok' : 'failed', flush: true);
  }
  if (validation) await preferences.setBool('windows.close_to_tray', false);
  final settings = AppSettings(preferences);
  if (!validation) await settings.migrateHomeLayout();
  progress('Abrindo sua biblioteca…');
  final app = MusicTimeApp(
    settings: settings,
    store: store,
    startupNotice: startupNotice,
    nativeIntegration: Platform.isWindows,
    validation: validation,
    smokeAudio: validation
        ? arguments
              .where((value) => value.startsWith('--smoke-audio='))
              .map((value) => value.substring('--smoke-audio='.length))
              .firstOrNull
        : null,
  );
  if (Platform.isWindows &&
      !validation &&
      arguments.any((value) => value.startsWith('--restart-after='))) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  return app;
}

class MusicTimeApp extends StatelessWidget {
  const MusicTimeApp({
    super.key,
    required this.settings,
    required this.store,
    this.nativeIntegration = false,
    this.validation = false,
    this.smokeAudio,
    this.startupNotice,
  });
  final AppSettings settings;
  final LibraryStore store;
  final bool nativeIntegration, validation;
  final String? smokeAudio, startupNotice;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) => MaterialApp(
      title: 'Music Time',
      locale: settings.language == 'en'
          ? const Locale('en')
          : const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
      localizationsDelegates: const [
        UiLanguageDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      debugShowCheckedModeBanner: false,
      themeMode: settings.mode,
      themeAnimationDuration:
          settings.visualBool('reduce_motion', fallback: false) ||
              !settings.visualBool('animations')
          ? Duration.zero
          : const Duration(milliseconds: 200),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              MediaQuery.disableAnimationsOf(context) ||
              settings.visualBool('reduce_motion', fallback: false) ||
              !settings.visualBool('animations'),
        ),
        child: child!,
      ),
      theme: musicTimeTheme(
        Brightness.light,
        Color(settings.effectiveAccent),
        settings,
      ),
      darkTheme: musicTimeTheme(
        Brightness.dark,
        Color(settings.effectiveAccent),
        settings,
      ),
      home: AppShell(
        settings: settings,
        store: store,
        nativeIntegration: nativeIntegration,
        validation: validation,
        smokeAudio: smokeAudio,
        startupNotice: startupNotice,
      ),
    ),
  );
}

ThemeData musicTimeTheme(
  Brightness brightness,
  Color accent, [
  AppSettings? settings,
]) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? accent : Color.lerp(accent, Colors.black, .24)!;
  final surface = dark ? const Color(0xff111516) : const Color(0xfff7f7f5);
  final card = dark ? const Color(0xff1c2223) : Colors.white;
  final border = dark ? const Color(0xff333b3c) : const Color(0xffd9dedd);
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: primary,
        onPrimary: dark ? const Color(0xff16191a) : Colors.white,
        primaryContainer: primary.withValues(alpha: .16),
        onPrimaryContainer: primary,
        secondaryContainer: primary.withValues(alpha: .14),
        onSecondaryContainer: primary,
        surface: surface,
        surfaceContainer: card,
        surfaceContainerHighest: dark
            ? const Color(0xff292f30)
            : const Color(0xffe5e9e7),
      );
  return ThemeData(
    useMaterial3: true,
    textTheme: TextTheme(
      titleMedium: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: settings?.visualNumber('font_body', 14) ?? 14,
      ),
      titleSmall: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: settings?.visualNumber('font_body', 14) ?? 14,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: settings?.visualNumber('font_title', 22) ?? 22,
      ),
      headlineSmall: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: settings?.visualNumber('font_title', 22) ?? 22,
      ),
      headlineMedium: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: settings?.visualNumber('font_title', 28) ?? 28,
      ),
      bodyLarge: TextStyle(
        fontSize: settings?.visualNumber('font_body', 14) ?? 14,
      ),
      bodyMedium: TextStyle(
        fontSize: settings?.visualNumber('font_body', 14) ?? 14,
      ),
      bodySmall: TextStyle(
        fontSize: settings?.visualNumber('font_secondary', 12) ?? 12,
      ),
    ),
    fontFamily: 'Segoe UI',
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    dividerColor: border,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: primary, width: 2),
      ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: primary,
      selectedTileColor: scheme.secondaryContainer,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: card,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: border),
      shape: const StadiumBorder(),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
