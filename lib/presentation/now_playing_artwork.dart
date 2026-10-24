import '../library/local_metadata.dart' show albumKey;
import 'media_indicators.dart';
import 'artwork_placeholder.dart';
import 'ui_language.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/track.dart';
import 'cover_scope.dart';

class TrackCover extends StatelessWidget {
  const TrackCover({
    super.key,
    this.track,
    this.circular = false,
    this.rounded = true,
    this.album = false,
    this.indicators = true,
  });
  final Track? track;
  final bool circular, rounded, album, indicators;
  @override
  Widget build(BuildContext context) {
    const fallback = ArtworkPlaceholder();
    final scope = context
        .dependOnInheritedWidgetOfExactType<CatalogCoverScope>();
    final image = track?.cover == null
        ? scope != null && track?.hasArtwork == true
              ? LazyCatalogCover(
                  id: track!.id,
                  cache: scope.cache,
                  revision: scope.revision,
                  fallback: fallback,
                )
              : fallback
        : Image.memory(
            track!.cover!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => fallback,
          );
    final state = indicators ? MediaIndicatorScope.of(context) : null;
    final decorated = MediaBadges(
      favorite:
          state != null &&
          track != null &&
          (album
              ? state.albumFavorite(track!)
              : state.favorites.contains(track!.id)),
      playing:
          state?.playing == true &&
          track != null &&
          (album && state?.currentTrack != null
              ? albumKey(state!.currentTrack!) == albumKey(track!)
              : state?.currentId == track?.id),
      child: image,
    );
    return circular
        ? ClipOval(child: decorated)
        : ClipRRect(
            borderRadius: BorderRadius.circular(rounded ? 8 : 0),
            child: decorated,
          );
  }
}

class NowPlayingArtwork extends StatefulWidget {
  const NowPlayingArtwork({
    super.key,
    required this.style,
    this.track,
    this.playing = false,
    this.reduceMotion = false,
    this.coverShape = 'rounded',
  });
  final String style;
  final Track? track;
  final bool playing, reduceMotion;
  final String coverShape;
  @override
  State<NowPlayingArtwork> createState() => _NowPlayingArtworkState();
}

class _NowPlayingArtworkState extends State<NowPlayingArtwork>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    sync();
  }

  late final AnimationController rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  void sync() {
    final enabled =
        {'vinyl', 'cassette'}.contains(widget.style) &&
        foreground &&
        widget.playing &&
        !widget.reduceMotion &&
        !MediaQuery.disableAnimationsOf(context);
    if (enabled && !rotation.isAnimating) {
      rotation.repeat();
    } else if (!enabled && rotation.isAnimating) {
      rotation.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(covariant NowPlayingArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    rotation.dispose();
    super.dispose();
  }

  Widget disc({required double size, bool label = true}) => SizedBox.square(
    dimension: size,
    child: RotationTransition(
      turns: rotation,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(child: CustomPaint(painter: VinylPainter())),
          if (label)
            SizedBox.square(
              dimension: size * .31,
              child: TrackCover(track: widget.track, circular: true),
            ),
          Container(
            width: size * .035,
            height: size * .035,
            decoration: const BoxDecoration(
              color: Color(0xff111314),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => switch (widget.style) {
    'minimal' => Center(
      child: FractionallySizedBox(
        widthFactor: .78,
        heightFactor: .78,
        child: TrackCover(
          track: widget.track,
          circular: widget.coverShape == 'circle',
        ),
      ),
    ),
    'focus' => AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(32),
        ),
        child: TrackCover(track: widget.track, circular: true),
      ),
    ),
    'gallery' => AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .25),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: TrackCover(
          track: widget.track,
          rounded: widget.coverShape != 'square',
        ),
      ),
    ),
    'vinyl' => AspectRatio(
      aspectRatio: 1.4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = math.min(
            constraints.maxHeight * .94,
            constraints.maxWidth * .69,
          );
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned(right: 0, child: disc(size: size)),
              Positioned(
                left: 0,
                child: SizedBox.square(
                  dimension: size * .86,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(blurRadius: 24, color: Colors.black54),
                      ],
                    ),
                    child: TrackCover(
                      track: widget.track,
                      circular: widget.coverShape == 'circle',
                      rounded: widget.coverShape != 'square',
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
    'cassette' => Center(
      child: AspectRatio(
        aspectRatio: 1.55,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: CassettePainter()),
              ),
              Positioned(
                left: constraints.maxWidth * .12,
                right: constraints.maxWidth * .12,
                top: constraints.maxHeight * .12,
                height: constraints.maxHeight * .23,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: constraints.maxWidth * .76,
                    child: Column(
                      children: [
                        Text(
                          widget.track?.title ?? 'Music Time',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff261914),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.track?.artist ?? 'Sua coleção',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff39251d),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: constraints.maxWidth * .22,
                top: constraints.maxHeight * .40,
                child: disc(size: constraints.maxWidth * .19, label: false),
              ),
              Positioned(
                right: constraints.maxWidth * .22,
                top: constraints.maxHeight * .40,
                child: disc(size: constraints.maxWidth * .19, label: false),
              ),
            ],
          ),
        ),
      ),
    ),
    'lyrics' => const AspectRatio(
      aspectRatio: 1.4,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiText(
                'Linhas anteriores',
                maxLines: 1,
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: UiText(
                  'Letra da faixa',
                  maxLines: 1,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              UiText(
                'Próximas linhas',
                maxLines: 1,
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    ),
    _ => AspectRatio(
      aspectRatio: 1,
      child: TrackCover(
        track: widget.track,
        circular: widget.coverShape == 'circle',
        rounded: widget.coverShape != 'square',
      ),
    ),
  };
}

class VinylPainter extends CustomPainter {
  const VinylPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xff101112),
            Color(0xff444649),
            Color(0xff111213),
            Color(0xff292b2d),
            Color(0xff101112),
          ],
          stops: [0, .19, .45, .73, 1],
        ).createShader(rect),
    );
    for (double r = radius * .38; r < radius * .98; r += radius * .035) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: .5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.drawCircle(
      center,
      radius * .17,
      Paint()..color = const Color(0xffff7668),
    );
  }

  @override
  bool shouldRepaint(VinylPainter oldDelegate) => false;
}

class CassettePainter extends CustomPainter {
  const CassettePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffa5765b), Color(0xff392820), Color(0xffb17a58)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      body.deflate(5),
      Paint()
        ..color = const Color(0xffd7a989)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .08,
          size.height * .07,
          size.width * .84,
          size.height * .28,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xffdfbd99),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .13,
          size.height * .38,
          size.width * .74,
          size.height * .36,
        ),
        const Radius.circular(18),
      ),
      Paint()..color = const Color(0xff201b18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .30,
          size.height * .79,
          size.width * .40,
          size.height * .12,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xff30221c),
    );
    for (final x in [.05, .95]) {
      for (final y in [.08, .92]) {
        canvas.drawCircle(
          Offset(size.width * x, size.height * y),
          3,
          Paint()..color = const Color(0xff211a17),
        );
      }
    }
  }

  @override
  bool shouldRepaint(CassettePainter oldDelegate) => false;
}
