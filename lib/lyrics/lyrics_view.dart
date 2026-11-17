import 'package:flutter/material.dart';

import '../presentation/design_icon.dart';

import 'package:flutter/rendering.dart';

import '../application/player_controller.dart';
import '../settings/app_settings.dart';
import 'lyrics.dart';
import 'lyrics_loader.dart';
import '../domain/track.dart';
import '../presentation/ui_language.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.controller,
    required this.settings,
    this.loader,
    this.immersive = false,
  });
  final bool immersive;
  final PlayerController controller;
  final AppSettings settings;
  final Future<LyricsDocument?> Function(Track, bool)? loader;
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final scroll = ScrollController();
  Future<LyricsDocument?>? document;
  String? loadedId;
  int lastActive = -2;
  bool exploring = false;
  @override
  void initState() {
    super.initState();
    updateTrack();
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateTrack();
  }

  void updateTrack() {
    final track = widget.controller.current;
    final identity = track == null
        ? null
        : '${track.id}|${track.revision}|${track.localPath}|${widget.controller.duration.inSeconds}';
    if (identity == loadedId) return;
    loadedId = identity;
    document = track == null
        ? null
        : widget.loader?.call(track, false) ?? loadLocalLyrics(track);
    exploring = false;
    lastActive = -2;
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void reload() {
    final track = widget.controller.current;
    if (track != null) {
      setState(
        () => document =
            widget.loader?.call(track, true) ?? loadLocalLyrics(track),
      );
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void reveal(int index, double height, double extent) {
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final target = (index * extent - (widget.immersive ? 0 : height * .30))
          .clamp(0.0, scroll.position.maxScrollExtent);
      if (widget.settings.visualBool('reduce_motion', fallback: false) ||
          MediaQuery.disableAnimationsOf(context)) {
        scroll.jumpTo(target);
      } else {
        scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.controller,
      widget.controller.progress,
    ]),
    builder: (context, _) => buildLyrics(context),
  );

  Widget buildLyrics(BuildContext context) {
    updateTrack();
    if (document == null) {
      return const Center(
        child: UiText('Selecione uma faixa para ver a letra.'),
      );
    }
    return FutureBuilder<LyricsDocument?>(
      future: document,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton.icon(
              onPressed: reload,
              icon: const MtIcon(Icons.refresh),
              label: const Text('Could not load lyrics. Retry'),
            ),
          );
        }
        final lyrics = snapshot.data;
        if (lyrics == null) {
          return Center(
            child: TextButton.icon(
              onPressed: reload,
              icon: const MtIcon(Icons.refresh),
              label: const Text(
                'No lyrics found. Add a matching LRC/TXT beside the audio file, or embed lyrics in its tags. Retry',
              ),
            ),
          );
        }
        final offset = Duration(
          milliseconds: widget.settings.lyricsOffset(
            widget.controller.current!.id,
          ),
        );
        final position = widget.controller.position;
        final active = lyrics.activeIndex(position, adjustment: offset);
        return Column(
          children: [
            if (widget.immersive)
              Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<String>(
                  tooltip: ui(context, 'Opções das letras'),
                  icon: const MtIcon(Icons.more_horiz),
                  onSelected: (action) {
                    if (action == 'refresh') {
                      reload();
                      return;
                    }
                    widget.settings.setLyricsOffset(
                      widget.controller.current!.id,
                      action == 'reset'
                          ? 0
                          : offset.inMilliseconds +
                                (action == 'earlier' ? -250 : 250),
                    );
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'refresh',
                      child: UiText('Atualizar letras'),
                    ),
                    if (lyrics.synchronized) ...[
                      const PopupMenuItem(
                        value: 'earlier',
                        child: UiText('Adiantar letra em 250 ms'),
                      ),
                      const PopupMenuItem(
                        value: 'later',
                        child: UiText('Atrasar letra em 250 ms'),
                      ),
                      const PopupMenuItem(
                        value: 'reset',
                        child: UiText('Zerar ajuste'),
                      ),
                    ],
                  ],
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (lyrics.source != null) Text('Lyrics · ${lyrics.source}'),
                  IconButton(
                    tooltip: ui(context, 'Atualizar letras'),
                    onPressed: reload,
                    icon: const MtIcon(Icons.refresh),
                  ),
                ],
              ),
            if (!widget.immersive && lyrics.synchronized)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: ui(context, 'Adiantar letra em 250 ms'),
                    onPressed: () => widget.settings.setLyricsOffset(
                      widget.controller.current!.id,
                      offset.inMilliseconds - 250,
                    ),
                    icon: const MtIcon(Icons.remove),
                  ),
                  Text('${ui(context, 'Ajuste')}: ${offset.inMilliseconds} ms'),
                  IconButton(
                    tooltip: ui(context, 'Atrasar letra em 250 ms'),
                    onPressed: () => widget.settings.setLyricsOffset(
                      widget.controller.current!.id,
                      offset.inMilliseconds + 250,
                    ),
                    icon: const MtIcon(Icons.add),
                  ),
                  TextButton(
                    onPressed: () => widget.settings.setLyricsOffset(
                      widget.controller.current!.id,
                      0,
                    ),
                    child: const UiText('Zerar ajuste'),
                  ),
                ],
              )
            else if (!widget.immersive)
              const Padding(
                padding: EdgeInsets.all(8),
                child: UiText('Letra sem sincronização'),
              ),
            if (exploring && lyrics.synchronized)
              TextButton(
                onPressed: () {
                  setState(() {
                    exploring = false;
                    lastActive = -2;
                  });
                },
                child: const UiText('Voltar à letra atual'),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final extent =
                      (widget.settings.visualNumber('lyrics_font', 26) *
                              widget.settings.visualNumber(
                                'lyrics_spacing',
                                1.25,
                              ) *
                              (widget.immersive ? 1.5 : 2) +
                          (widget.immersive ? 24 : 48)) *
                      MediaQuery.textScalerOf(context).scale(1);
                  if (active != lastActive &&
                      !exploring &&
                      widget.settings.visualBool('lyrics_auto_scroll')) {
                    lastActive = active;
                    reveal(active, constraints.maxHeight, extent);
                  }
                  return NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (notification.direction != ScrollDirection.idle &&
                          !exploring) {
                        setState(() => exploring = true);
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: scroll,
                      padding: widget.immersive
                          ? EdgeInsets.symmetric(
                              vertical: constraints.maxHeight * .35,
                            )
                          : null,
                      itemExtent: lyrics.synchronized ? extent : null,
                      itemCount: lyrics.lines.length,
                      itemBuilder: (context, index) {
                        final line = lyrics.lines[index];
                        final current = index == active;
                        final textColor = current || !lyrics.synchronized
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: .46);
                        final effective = position - lyrics.offset - offset;
                        return InkWell(
                          onTap: line.at == null
                              ? null
                              : () {
                                  exploring = false;
                                  lastActive = -2;
                                  final target =
                                      line.at! + lyrics.offset + offset;
                                  widget.controller.seek(
                                    target < Duration.zero
                                        ? Duration.zero
                                        : target,
                                  );
                                },
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical:
                                  ((widget.settings.visualNumber(
                                                'lyrics_spacing',
                                                1.25,
                                              ) -
                                              .8) *
                                          24)
                                      .clamp(2.0, 24.0),
                            ),
                            child: Align(
                              alignment: widget.immersive
                                  ? Alignment.center
                                  : Alignment.centerLeft,
                              child: line.words.isEmpty
                                  ? Text(
                                      line.text.isEmpty ? '♪' : line.text,
                                      textAlign: widget.immersive
                                          ? TextAlign.center
                                          : TextAlign.start,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize:
                                            widget.settings.visualNumber(
                                              'lyrics_font',
                                              26,
                                            ) *
                                            (current ? 1 : .85),
                                        height: widget.settings.visualNumber(
                                          'lyrics_spacing',
                                          1.25,
                                        ),
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                      ),
                                    )
                                  : Text.rich(
                                      TextSpan(
                                        children: [
                                          for (
                                            var w = 0;
                                            w < line.words.length;
                                            w++
                                          )
                                            TextSpan(
                                              text: line.words[w].text,
                                              style: TextStyle(
                                                color:
                                                    current &&
                                                        effective >=
                                                            line.words[w].at &&
                                                        (w + 1 ==
                                                                line
                                                                    .words
                                                                    .length ||
                                                            effective <
                                                                line
                                                                    .words[w +
                                                                        1]
                                                                    .at)
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .primary
                                                    : textColor,
                                              ),
                                            ),
                                        ],
                                      ),
                                      textAlign: widget.immersive
                                          ? TextAlign.center
                                          : TextAlign.start,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: widget.settings.visualNumber(
                                          'lyrics_font',
                                          26,
                                        ),
                                        height: widget.settings.visualNumber(
                                          'lyrics_spacing',
                                          1.25,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
