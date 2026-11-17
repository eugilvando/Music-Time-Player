import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/player_controller.dart';
import '../settings/app_settings.dart';
import '../lyrics/lyrics.dart';
import '../lyrics/lyrics_view.dart';
import '../domain/track.dart';
import 'now_playing_artwork.dart';
import 'player_bar.dart';
import 'design_icon.dart';
import 'ui_language.dart';

class FullscreenNowPlaying extends StatefulWidget {
  const FullscreenNowPlaying({
    super.key,
    required this.controller,
    required this.settings,
    required this.controls,
    required this.loadLyrics,
    required this.onExit,
    required this.onQueue,
  });
  final PlayerController controller;
  final AppSettings settings;
  final PlayerBar Function(VoidCallback) controls;
  final Future<LyricsDocument?> Function(Track, bool) loadLyrics;
  final VoidCallback onExit, onQueue;
  @override
  State<FullscreenNowPlaying> createState() => _FullscreenNowPlayingState();
}

class _FullscreenNowPlayingState extends State<FullscreenNowPlaying> {
  bool get lyrics {
    final content = widget.settings.visualChoice('now_playing_content', '');
    if (content.isNotEmpty) return content == 'lyrics';
    return widget.settings.visualBool('fullscreen_lyrics', fallback: false) ||
        widget.settings.nowPlayingStyle == 'lyrics_only';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.settings]),
    builder: (context, _) {
      final player = widget.controller;
      final track = player.current;
      final bar = widget.controls(() {
        if (mounted) setState(() {});
      });
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onExit,
        },
        child: Focus(
          autofocus: true,
          child: Theme(
            data: ThemeData.dark(useMaterial3: true).copyWith(
              iconTheme: const IconThemeData(color: Colors.white),
              iconButtonTheme: IconButtonThemeData(
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? Colors.white38
                        : states.contains(WidgetState.selected)
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                  ),
                ),
              ),
              brightness: Brightness.dark,
              colorScheme:
                  ColorScheme.fromSeed(
                    seedColor: Theme.of(context).colorScheme.primary,
                    brightness: Brightness.dark,
                  ).copyWith(
                    primary: Theme.of(context).colorScheme.primary,
                    onPrimary: Colors.white,
                  ),
              textTheme: Theme.of(context).textTheme
                  .apply(bodyColor: Colors.white, displayColor: Colors.white),
            ),
            child: Builder(
              builder: (context) => Material(
                color: const Color(0xff121616),
                child: Stack(
                  children: [
                    if (track?.cover != null)
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: 64,
                              sigmaY: 64,
                            ),
                            child: Image.memory(
                              track!.cover!,
                              fit: BoxFit.cover,
                              cacheWidth: 640,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: .65),
                      ),
                    ),
                    SafeArea(
                      child: LayoutBuilder(
                        builder: (context, area) => Padding(
                          padding: EdgeInsets.all(
                            area.maxWidth < 600 ? 16 : 32,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  if (lyrics) ...[
                                    SizedBox.square(
                                      dimension: 52,
                                      child: TrackCover(track: track),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            track?.title ??
                                                ui(
                                                  context,
                                                  'Escolha uma música',
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${track?.artist ?? ''} · ${track?.album ?? ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    Image.asset(
                                      'assets/branding/icon.png',
                                      width: 36,
                                      height: 36,
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Music Time',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 12),
                                  SegmentedButton<bool>(
                                    key: const ValueKey('fullscreen.mode'),
                                    showSelectedIcon: false,
                                    segments: [
                                      ButtonSegment(
                                        value: false,
                                        icon: const MtIcon(Icons.album),
                                        label: area.maxWidth < 700
                                            ? null
                                            : const UiText('Capa'),
                                        tooltip: ui(context, 'Capa'),
                                      ),
                                      ButtonSegment(
                                        value: true,
                                        icon: const MtIcon(Icons.lyrics),
                                        label: area.maxWidth < 700
                                            ? null
                                            : const UiText('Apenas letras'),
                                        tooltip: ui(context, 'Apenas letras'),
                                      ),
                                    ],
                                    selected: {lyrics},
                                    onSelectionChanged: (value) {
                                      widget.settings.updateVisual(
                                        'now_playing_content',
                                        value.single ? 'lyrics' : 'cover',
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    key: const ValueKey('fullscreen.exit'),
                                    tooltip: ui(
                                      context,
                                      'Sair da tela inteira',
                                    ),
                                    onPressed: widget.onExit,
                                    icon: const MtIcon(Icons.fullscreen_exit),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Expanded(
                                child: lyrics
                                    ? LyricsView(
                                        immersive: true,
                                        controller: player,
                                        settings: widget.settings,
                                        loader: widget.loadLyrics,
                                      )
                                    : LayoutBuilder(
                                        builder: (context, space) {
                                          final wide = space.maxWidth >= 740;
                                          final coverSize = math.max(
                                            64.0,
                                            math.min(
                                              wide
                                                  ? space.maxWidth * .42
                                                  : space.maxWidth * .65,
                                              wide
                                                  ? space.maxHeight - 24
                                                  : space.maxHeight * .58,
                                            ),
                                          );
                                          final artwork = SizedBox.square(
                                            dimension: coverSize,
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              child: TrackCover(track: track),
                                            ),
                                          );
                                          final info = Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: wide
                                                ? CrossAxisAlignment.start
                                                : CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                track?.title ??
                                                    ui(
                                                      context,
                                                      'Escolha uma música',
                                                    ),
                                                textAlign: wide
                                                    ? TextAlign.start
                                                    : TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                track?.artist ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                track?.album ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              bar.item(context, 'favorite', 0),
                                            ],
                                          );
                                          return Center(
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 1100,
                                              ),
                                              child: wide
                                                  ? Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        artwork,
                                                        const SizedBox(
                                                          width: 48,
                                                        ),
                                                        Flexible(child: info),
                                                      ],
                                                    )
                                                  : SingleChildScrollView(
                                                      child: Column(
                                                        children: [
                                                          artwork,
                                                          const SizedBox(
                                                            height: 24,
                                                          ),
                                                          info,
                                                        ],
                                                      ),
                                                    ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (final id in [
                                    'shuffle',
                                    'previous',
                                    'play',
                                    'next',
                                    'repeat',
                                  ])
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: bar.item(context, id, 0),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  bar.item(context, 'elapsed', 0),
                                  Expanded(child: bar.progress()),
                                  bar.item(context, 'duration', 0),
                                  if (area.maxWidth >= 700) ...[
                                    const SizedBox(width: 24),
                                    SizedBox(
                                      width: 140,
                                      child: bar.item(context, 'volume', 0),
                                    ),
                                  ],
                                  const SizedBox(width: 12),
                                  IconButton(
                                    tooltip: ui(context, 'Fila de reprodução'),
                                    onPressed: widget.onQueue,
                                    icon: const MtIcon(Icons.queue_music),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
