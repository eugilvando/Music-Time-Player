import 'design_icon.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'ui_language.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import '../application/player_controller.dart';
import '../domain/queue_navigation.dart';
import '../settings/app_settings.dart';
import '../settings/player_bar_layout.dart';
import 'now_playing_artwork.dart';

String playbackTime(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

({double infoWidth, double rowHeight, int rows}) barMetrics(
  BuildContext context,
  AppSettings settings,
  double width,
) {
  final visible = playerBarVisible(settings);
  final scale = MediaQuery.textScalerOf(context);
  final height = max(
    48.0,
    1.5 *
        (scale.scale(settings.visualNumber('font_secondary', 12)) +
            (visible.contains('info')
                ? scale.scale(settings.visualNumber('font_body', 16))
                : 0)),
  );
  final info = (width * .20).clamp(100.0, 300.0);
  final spacing = settings.visualNumber('bar_icon_spacing', 4).clamp(0.0, 24.0);
  var used = 0.0, rows = 1;
  for (final id in playerBarOrder(settings).where(visible.contains)) {
    final itemWidth = switch (id) {
      'info' => info + 10,
      'cover' => 58.0,
      'play' => 48.0,
      'volume' => 128.0,
      'progress' => 160.0,
      'elapsed' || 'duration' => scale.scale(42.0),
      'lyrics' || 'queue' => 44.0,
      'separator1' || 'separator2' || 'separator3' => 18.0,
      _ => 32.0,
    };
    if (used > 0 && used + spacing + itemWidth > width) {
      rows++;
      used = 0;
    }
    used += (used > 0 ? spacing : 0) + itemWidth;
  }
  return (infoWidth: info, rowHeight: height, rows: rows);
}

double playerBarHeight(BuildContext context, AppSettings settings) {
  final layout = barMetrics(
    context,
    settings,
    max(1, MediaQuery.sizeOf(context).width - 32),
  );
  return min(
    layout.rowHeight * layout.rows + (layout.rows - 1) * 8 + 24,
    max(72, min(240, MediaQuery.sizeOf(context).height * .30)),
  );
}

class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.controller,
    required this.settings,
    required this.favorite,
    required this.onFavorite,
    required this.onDetails,
    required this.onQueue,
    required this.onExpand,
    required this.onSave,
    this.onLyrics,
    this.lyricsActive = false,
    this.lastfmActive = false,
    this.lastfmStatus,
    this.onArtist,
    this.onAlbum,
    this.availability,
  });
  final PlayerController controller;
  final AppSettings settings;
  final bool favorite;
  final VoidCallback onFavorite, onDetails, onQueue, onExpand;
  final Future<void> Function() onSave;
  final VoidCallback? onLyrics;
  final bool lyricsActive;
  final bool lastfmActive;
  final String? lastfmStatus;
  final Widget? availability;
  final VoidCallback? onArtist, onAlbum;

  Widget progress() => Slider(
    value: controller.position.inMilliseconds.toDouble().clamp(
      0.0,
      controller.duration.inMilliseconds > 0
          ? controller.duration.inMilliseconds.toDouble()
          : 1.0,
    ),
    max: controller.duration.inMilliseconds > 0
        ? controller.duration.inMilliseconds.toDouble()
        : 1.0,
    onChanged: controller.duration > Duration.zero && !controller.opening
        ? (value) => controller.seek(Duration(milliseconds: value.toInt()))
        : null,
  );

  Widget item(
    BuildContext context,
    String id,
    double infoWidth,
  ) => switch (id) {
    'cover' => InkWell(
      onTap: onExpand,
      child: SizedBox.square(
        dimension: 48,
        child: TrackCover(track: controller.current),
      ),
    ),
    'info' => SizedBox(
      width: infoWidth,
      child: InkWell(
        onTap: onExpand,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.current?.title ??
                  ui(context, 'Nenhuma faixa selecionada'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: settings.primaryFont,
                fontWeight: FontWeight.w700,
                fontSize: settings.visualNumber('font_body', 16),
              ),
            ),
            if (controller.current != null) secondaryInfo(context),
          ],
        ),
      ),
    ),
    'previous' => IconButton(
      tooltip: ui(context, 'Anterior'),
      icon: const MtIcon(Icons.skip_previous),
      onPressed: controller.canGoPrevious && !controller.opening
          ? () async {
              await controller.previous();
              await onSave();
            }
          : null,
    ),
    'play' => Tooltip(
      message: ui(context, 'Reproduzir / pausar'),
      child: FilledButton(
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(12),
          minimumSize: const Size(44, 44),
        ),
        onPressed: controller.current == null || controller.opening
            ? null
            : controller.toggle,
        child: controller.buffering
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : MtIcon(controller.playing ? Icons.pause : Icons.play_arrow),
      ),
    ),
    'next' => IconButton(
      tooltip: ui(context, 'Próxima'),
      icon: const MtIcon(Icons.skip_next),
      onPressed: controller.nextIndex >= 0 && !controller.opening
          ? () async {
              await controller.next();
              await onSave();
            }
          : null,
    ),
    'shuffle' => IconButton(
      tooltip: ui(context, 'Aleatório'),
      isSelected: controller.shuffle,
      icon: const MtIcon(Icons.shuffle, size: 20),
      onPressed: () {
        controller.toggleShuffle();
        onSave();
      },
    ),
    'repeat' => IconButton(
      tooltip:
          '${ui(context, 'Repetir')}: ${ui(context, switch (controller.repeat) {
            PlaybackRepeat.off => 'desligado',
            PlaybackRepeat.queue => 'fila',
            PlaybackRepeat.track => 'faixa',
          })}',
      isSelected: controller.repeat != PlaybackRepeat.off,
      onPressed: controller.cycleRepeat,
      icon: MtIcon(
        controller.repeat == PlaybackRepeat.track
            ? Icons.repeat_one
            : Icons.repeat,
        size: 20,
      ),
    ),
    'favorite' => IconButton(
      tooltip: ui(context, favorite ? 'Remover favorito' : 'Favoritar'),
      isSelected: favorite,
      onPressed: controller.current == null ? null : onFavorite,
      icon: const MtIcon(Icons.favorite, size: 20),
    ),
    'actions' => IconButton(
      tooltip: ui(context, 'Ações da faixa'),
      onPressed: controller.current == null ? null : onDetails,
      icon: const MtIcon(Icons.more_horiz, size: 20),
    ),
    'lastfm' => lastfmIndicator(context),
    'elapsed' || 'duration' => Text(
      playbackTime(id == 'elapsed' ? controller.position : controller.duration),
      style: TextStyle(fontSize: settings.visualNumber('font_secondary', 11)),
    ),
    'progress' => ConstrainedBox(
      key: const ValueKey('player.seekbar'),
      constraints: const BoxConstraints(minWidth: 140),
      child: progress(),
    ),
    'volume' => volume(context),
    'offline' =>
      availability ??
          IconButton(
            tooltip: ui(context, 'Disponibilidade da faixa'),
            icon: const MtIcon(Icons.offline_pin),
            onPressed: null,
          ),
    'separator1' || 'separator2' || 'separator3' => const SizedBox(
      width: 18,
      child: VerticalDivider(indent: 8, endIndent: 8),
    ),
    'continuous' => IconButton(
      tooltip: ui(context, 'Play contínuo'),
      isSelected: settings.visualBool('smart_play', fallback: false),
      icon: const MtIcon(
        IconData(0xf6b5, fontFamily: 'Material Symbols Rounded'),
      ),
      onPressed: () => settings.updateVisual(
        'smart_play',
        !settings.visualBool('smart_play', fallback: false),
      ),
    ),
    'lyrics' => panelToggle(context, 'lyrics'),
    'queue' => panelToggle(context, 'queue'),
    'expand' => IconButton(
      tooltip: ui(context, 'Tocando agora'),
      onPressed: onExpand,
      icon: const MtIcon(Icons.open_in_full),
    ),
    _ => const SizedBox.shrink(),
  };

  Widget panelToggle(BuildContext context, String id) {
    final lyrics = id == 'lyrics';
    final selected = lyrics
        ? lyricsActive
        : settings.visualBool('show_queue', fallback: false) && !lyricsActive;
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 32),
        maximumSize: const Size(40, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        backgroundColor: selected ? colors.primary : Colors.transparent,
        foregroundColor: selected ? colors.onPrimary : colors.onSurface,
        shape: const StadiumBorder(),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      tooltip: lyrics
          ? ui(context, lyricsActive ? 'Desativar letras' : 'Ativar letras')
          : ui(context, 'Fila'),
      isSelected: selected,
      onPressed: lyrics ? onLyrics : onQueue,
      icon: MtIcon(lyrics ? Icons.lyrics : Icons.queue_music, size: 16),
    );
  }

  List<Widget> barItems(
    BuildContext context,
    List<String> order,
    double width, {
    bool wrap = false,
  }) {
    Widget keyed(String id) => Padding(
      key: ValueKey('player.item.$id'),
      padding: EdgeInsets.only(right: id == 'cover' || id == 'info' ? 10 : 0),
      child: item(context, id, width),
    );
    final result = <Widget>[];
    for (var i = 0; i < order.length; i++) {
      final id = order[i];
      if (id == 'progress') {
        result.add(
          wrap
              ? SizedBox(width: 160, child: item(context, id, width))
              : Expanded(child: item(context, id, width)),
        );
      } else if (i + 1 < order.length &&
          {'lyrics', 'queue'}.contains(id) &&
          {'lyrics', 'queue'}.contains(order[i + 1])) {
        final colors = Theme.of(context).colorScheme;
        result.add(
          DecoratedBox(
            key: const ValueKey('player.panelSelector'),
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: .10),
              border: Border.all(color: colors.outline.withValues(alpha: .1)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [keyed(id), keyed(order[++i])],
              ),
            ),
          ),
        );
      } else {
        result.add(keyed(id));
      }
    }
    final spacing = settings
        .visualNumber('bar_icon_spacing', 4)
        .clamp(0.0, 24.0)
        .toDouble();
    if (wrap) return result;
    return [
      for (var i = 0; i < result.length; i++) ...[
        if (i > 0) SizedBox(width: spacing),
        result[i],
      ],
    ];
  }

  Widget volume(BuildContext context) => SizedBox(
    width: 128,
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('player.mute'),
          tooltip: ui(
            context,
            controller.volume == 0 ? 'Desativar mudo' : 'Ativar mudo',
          ),
          icon: MtIcon(
            controller.volume == 0 ? Icons.volume_off : Icons.volume_up,
            size: 18,
          ),
          onPressed: () async {
            await controller.toggleMute();
            await onSave();
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          key: const ValueKey('player.volume-slider'),
          child: Slider(
            padding: EdgeInsets.zero,
            value: controller.volume,
            max: 100,
            label: '${controller.volume.round()}%',
            onChanged: controller.setVolume,
          ),
        ),
      ],
    ),
  );

  Widget secondaryInfo(BuildContext context) {
    final track = controller.current!;
    final fields = settings.visualList('bar_fields', ['artist', 'album']);
    final values = <String, String>{
      'artist': track.artistNames.join('; '),
      'album': track.album,
      'year': track.year?.toString() ?? '',
      'format': track.format,
      'source': track.provider,
    };
    final shown = fields.where((id) => (values[id] ?? '').isNotEmpty).toList();
    return Row(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const UiText(' • ', style: TextStyle(fontSize: 12)),
          Flexible(
            child: InkWell(
              onTap: shown[i] == 'artist'
                  ? onArtist
                  : shown[i] == 'album'
                  ? onAlbum
                  : null,
              child: Text(
                values[shown[i]]!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: settings.visualNumber('font_secondary', 12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget lastfmIndicator(BuildContext context) => Tooltip(
    message: ui(
      context,
      lastfmStatus ?? (lastfmActive ? 'Last.fm ativo' : 'Last.fm inativo'),
    ),
    child: SizedBox.square(
      key: const ValueKey('player.lastfm'),
      dimension: 32,
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: SvgPicture.asset(
            'assets/design/lastfm-${lastfmActive ? 'active' : 'inactive'}.svg',
            semanticsLabel: 'Last.fm',
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTapDown: controller.current == null ? null : (_) => onDetails(),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .78),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(32, 32),
            visualDensity: VisualDensity.standard,
            maximumSize: const Size(32, 32),
            iconSize: 20,
            padding: const EdgeInsets.all(6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = barMetrics(
                context,
                settings,
                constraints.maxWidth,
              );
              final visible = playerBarVisible(settings);
              final order = playerBarOrder(settings)
                  .where(visible.contains)
                  .toList();
              if (layout.rows > 1) {
                return SizedBox(
                  height: playerBarHeight(context, settings) - 24,
                  child: SingleChildScrollView(
                    key: const ValueKey('player.controls.scroll'),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      heightFactor: 1,
                      child: Wrap(
                        key: const ValueKey('player.wrapped'),
                        spacing: settings
                            .visualNumber('bar_icon_spacing', 4)
                            .clamp(0, 24),
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final child in barItems(
                            context,
                            order,
                            layout.infoWidth,
                            wrap: true,
                          ))
                            SizedBox(
                              height: layout.rowHeight,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                widthFactor: 1,
                                child: child,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return SizedBox(
                height: layout.rowHeight,
                child: Row(
                  key: const ValueKey('player.single-line'),
                  children: barItems(context, order, layout.infoWidth),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
