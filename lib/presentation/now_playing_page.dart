import 'design_icon.dart';

import 'dart:math' as math;

import 'ui_language.dart';

import 'package:flutter/material.dart';

import '../application/player_controller.dart';
import '../settings/app_settings.dart';
import '../lyrics/lyrics_view.dart';
import '../lyrics/lyrics.dart';
import '../domain/track.dart';
import 'now_playing_artwork.dart';

const nowPlayingStyles = {
  'classic': 'Clássico',
  'vinyl': 'Vinil',
  'minimal': 'Minimalista',
  'cover_only': 'Somente capa',
  'lyrics_only': 'Somente letras',
};

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({
    super.key,
    required this.controller,
    required this.settings,
    required this.favorite,
    required this.onFavorite,
    required this.onDetails,
    this.onFullscreen,
    this.showLyrics,
    this.onArtist,
    this.onAlbum,
    this.loadLyrics,
  });
  final Future<LyricsDocument?> Function(Track, bool)? loadLyrics;
  final bool? showLyrics;
  final VoidCallback? onArtist, onAlbum;
  final PlayerController controller;
  final AppSettings settings;
  final bool favorite;
  final VoidCallback onFavorite, onDetails;
  final VoidCallback? onFullscreen;

  Widget information(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        controller.current?.title ?? ui(context, 'Escolha uma música'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      InkWell(
        onTap: onArtist,
        child: Text(
          controller.current?.artist ??
              ui(context, 'Sua coleção aparece na Biblioteca'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (settings.visualBool('additional_info') &&
          controller.current?.album.isNotEmpty == true)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: InkWell(
            onTap: onAlbum,
            child: Text(
              controller.current!.album,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      const SizedBox(height: 12),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: ui(context, favorite ? 'Remover favorito' : 'Favoritar'),
            isSelected: favorite,
            onPressed: controller.current == null ? null : onFavorite,
            icon: MtIcon(Icons.favorite),
          ),
          IconButton(
            tooltip: ui(context, 'Ações da faixa'),
            onPressed: controller.current == null ? null : onDetails,
            icon: const MtIcon(Icons.more_horiz),
          ),
        ],
      ),
    ],
  );

  Widget composition(
    BuildContext context,
    Widget artwork,
    double width,
    double height,
  ) {
    final position = settings.nowPlayingStyle == 'minimal'
        ? 'above'
        : settings.visualChoice('cover_position', 'left');
    final scale = settings.visualNumber('cover_scale', 1).clamp(.7, 2.6);
    final horizontal = width >= 740 && position != 'above';
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final vinyl = settings.nowPlayingStyle == 'vinyl';
    final availableCover = math.max(
      120.0,
      (height - (horizontal ? 0 : 190 * textScale)) * (vinyl ? 1.4 : 1),
    );
    final size = math
        .min(
          ((horizontal ? width * .46 : width - 48) * scale).clamp(
            120.0,
            horizontal
                ? math.min(width * (vinyl ? .82 : .70), width - 204)
                : math.min(width, vinyl ? 960.0 : 640.0),
          ),
          availableCover,
        )
        .toDouble();
    final cover = SizedBox(
      width: size,
      height: vinyl ? size / 1.4 : size,
      child: artwork,
    );
    if (horizontal) {
      final details = Expanded(child: information(context));
      return Row(
        children: position == 'right'
            ? [details, const SizedBox(width: 24), cover]
            : [cover, const SizedBox(width: 24), details],
      );
    }
    return Column(
      children: [
        cover,
        const SizedBox(height: 24),
        SizedBox(width: size, child: information(context)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final selectedStyle =
          nowPlayingStyles.containsKey(settings.nowPlayingStyle)
          ? settings.nowPlayingStyle
          : 'classic';
      final style = selectedStyle == 'lyrics_only'
          ? selectedStyle
          : showLyrics == true
          ? 'lyrics'
          : showLyrics == false && selectedStyle == 'lyrics'
          ? 'classic'
          : selectedStyle;
      final wide = constraints.maxWidth >= 740;
      final artwork = NowPlayingArtwork(
        style: style,
        track: controller.current,
        coverShape: settings.visualChoice('cover_shape', 'rounded'),
        playing:
            controller.playing && !controller.buffering && !controller.opening,
        reduceMotion:
            settings.visualBool('reduce_motion', fallback: false) ||
            !settings.visualBool('animations'),
      );
      return GestureDetector(
        onSecondaryTapDown: controller.current == null
            ? null
            : (_) => onDetails(),
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Spacer(),
                      if (onFullscreen != null)
                        IconButton(
                          tooltip: ui(context, 'Alternar tela cheia'),
                          onPressed: onFullscreen,
                          icon: const MtIcon(Icons.fullscreen),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: style == 'lyrics_only'
                            ? LyricsView(
                                loader: loadLyrics,
                                controller: controller,
                                settings: settings,
                              )
                            : style == 'cover_only'
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: TrackCover(
                                      track: controller.current,
                                    ),
                                  ),
                                ),
                              )
                            : style == 'lyrics'
                            ? wide
                                  ? Row(
                                      children: [
                                        SizedBox(
                                          key: const ValueKey(
                                            'nowPlaying.lyricsInformation',
                                          ),
                                          width: constraints.maxWidth * .25,
                                          child: Center(
                                            child: SingleChildScrollView(
                                              padding: const EdgeInsets.all(24),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  AspectRatio(
                                                    aspectRatio: 1,
                                                    child: TrackCover(
                                                      track: controller.current,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  information(context),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: LyricsView(
                                            loader: loadLyrics,
                                            controller: controller,
                                            settings: settings,
                                          ),
                                        ),
                                      ],
                                    )
                                  : LyricsView(
                                      loader: loadLyrics,
                                      controller: controller,
                                      settings: settings,
                                    )
                            : LayoutBuilder(
                                builder: (context, space) =>
                                    SingleChildScrollView(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: space.maxHeight,
                                        ),
                                        child: Center(
                                          child: ConstrainedBox(
                                            key: const ValueKey(
                                              'nowPlaying.composition',
                                            ),
                                            constraints: const BoxConstraints(
                                              maxWidth: 1200,
                                            ),
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: space.maxWidth < 740
                                                    ? 24
                                                    : 48,
                                                vertical: 24,
                                              ),
                                              child: composition(
                                                context,
                                                artwork,
                                                (space.maxWidth -
                                                        (space.maxWidth < 740
                                                            ? 48
                                                            : 96))
                                                    .clamp(120.0, 1120.0),
                                                math.max(
                                                  120,
                                                  space.maxHeight - 48,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
