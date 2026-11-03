import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../library/artist_ranking.dart';
import 'compact_media_card.dart';
import 'design_icon.dart';
import 'media_card_size.dart';
import 'now_playing_artwork.dart';
import 'ui_language.dart';

class ArtistFeaturedTracks extends StatefulWidget {
  const ArtistFeaturedTracks({
    super.key,
    required this.artist,
    required this.tracks,
    required this.stats,
    required this.load,
    required this.offline,
    required this.actions,
    required this.onPlay,
    required this.onShuffle,
  });
  final String artist;
  final List<Track> tracks;
  final Map<String, Map<String, Object?>> stats;
  final ArtistRankingLoader load;
  final bool offline;
  final Widget Function(Track) actions;
  final Future<void> Function(List<Track>, int) onPlay;
  final Future<void> Function(List<Track>) onShuffle;
  @override
  State<ArtistFeaturedTracks> createState() => _ArtistFeaturedTracksState();
}

class _ArtistFeaturedTracksState extends State<ArtistFeaturedTracks> {
  List<Track> tracks = [];
  int generation = 0, remoteMatches = 0;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(ArtistFeaturedTracks old) {
    super.didUpdateWidget(old);
    if (old.artist != widget.artist ||
        old.offline != widget.offline ||
        old.stats != widget.stats ||
        !listEquals(old.tracks, widget.tracks)) {
      reload();
    }
  }

  Future<void> reload() async {
    final request = ++generation;
    tracks = rankArtistTracks(
      artist: widget.artist,
      eligible: widget.tracks,
      stats: widget.stats,
    ).tracks;
    remoteMatches = 0;
    loading = true;
    try {
      final result = await widget.load(widget.artist, widget.tracks, 20, false);
      if (!mounted || generation != request) return;
      setState(() {
        tracks = result.tracks.take(20).toList();
        remoteMatches = result.remoteMatches;
        loading = false;
      });
    } catch (_) {
      if (mounted && generation == request) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 48, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: UiText(
                  'Faixas em destaque',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                key: const ValueKey('artist.featured.play'),
                tooltip: ui(context, 'Reproduzir'),
                onPressed: () => widget.onPlay(List.of(tracks), 0),
                icon: const MtIcon(Icons.play_arrow),
              ),
              IconButton(
                key: const ValueKey('artist.featured.shuffle'),
                tooltip: ui(context, 'Aleatório'),
                onPressed: () => widget.onShuffle(List.of(tracks)),
                icon: const MtIcon(Icons.shuffle),
              ),
            ],
          ),
          UiText(
            loading
                ? 'Consultando ranking do Last.fm…'
                : remoteMatches > 0
                ? 'Ranking do Last.fm, complementado pelas reproduções locais.'
                : 'Ordenadas pelas reproduções na sua biblioteca.',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: ((constraints.maxWidth + 12) / 208)
                    .floor()
                    .clamp(1, 6),
                mainAxisExtent: 53 * MediaQuery.textScalerOf(context).scale(1),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: tracks.length,
              itemBuilder: (context, i) => MediaCardSizeScope(
                value: 'Small',
                onChanged: (_) {},
                child: CompactMediaCard(
                  key: ValueKey('artist.featured.${tracks[i].id}'),
                  artwork: TrackCover(track: tracks[i]),
                  title: tracks[i].title,
                  subtitle: tracks[i].artist,
                  actions: widget.actions(tracks[i]),
                  dragTracks: [tracks[i]],
                  onTap: () => widget.onPlay(List.of(tracks), i),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
