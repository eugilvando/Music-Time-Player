import 'design_icon.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ui_language.dart';

import 'dart:async';

import 'package:flutter/material.dart';

/// Draw a real first frame before database opening/migrations and report failures.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key, required this.initialize});
  final Future<Widget> Function(ValueChanged<String> progress) initialize;
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  Widget? ready;
  String stage = 'Preparando o Music Time…';
  String language = 'en';
  bool failed = false;
  Timer? timer;
  final elapsed = Stopwatch();
  @override
  void initState() {
    super.initState();
    unawaited(loadLanguage());
    WidgetsBinding.instance.addPostFrameCallback((_) => start());
  }

  Future<void> loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('visual.language') == 'pt' ? 'pt' : 'en';
      if (mounted && saved != language) setState(() => language = saved);
    } catch (_) {
      /* Keep the default language if preferences are unavailable. */
    }
  }

  Future<void> start() async {
    if (!mounted) return;
    setState(() {
      failed = false;
      stage = 'Preparando o Music Time…';
    });
    elapsed
      ..reset()
      ..start();
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    try {
      final app = await widget.initialize((value) {
        if (mounted) setState(() => stage = value);
      });
      if (mounted) setState(() => ready = app);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      timer?.cancel();
      elapsed.stop();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ready ??
      MaterialApp(
        locale: language == 'pt'
            ? const Locale('pt', 'BR')
            : const Locale('en'),
        supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
        localizationsDelegates: const [
          UiLanguageDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true)
            .copyWith(scaffoldBackgroundColor: const Color(0xff111516)),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MtIcon(
                      Icons.album,
                      size: 56,
                      color: Color(0xffff7668),
                    ),
                    const SizedBox(height: 24),
                    UiText(
                      failed
                          ? 'Could not start Music Time'
                          : 'Opening Music Time',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 24),
                    UiText(stage, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    if (!failed) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        language == 'pt'
                            ? '${elapsed.elapsed.inSeconds}s • Preparando sua biblioteca.'
                            : '${elapsed.elapsed.inSeconds}s • Preparing your library.',
                      ),
                    ],
                    if (failed) ...[
                      const UiText(
                        'Check whether another instance is still closing and that disk space is available. Your original files are preserved.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: start,
                        child: const UiText('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
