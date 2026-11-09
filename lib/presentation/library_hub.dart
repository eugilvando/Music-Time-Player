import 'package:flutter/material.dart';

import '../domain/track.dart';
import 'navigation.dart';
import 'design_icon.dart';

class LibraryHub extends StatelessWidget {
  const LibraryHub({
    super.key,
    required this.tracks,
    required this.favorites,
    required this.onNavigate,
  });
  final List<Track> tracks;
  final Set<String> favorites;
  final ValueChanged<AppSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final albums = tracks
        .where((t) => t.album.isNotEmpty)
        .map((t) => '${t.albumArtist}|${t.album}')
        .toSet()
        .length;
    final artists = tracks.expand((t) => t.artistNames).toSet().length;
    final minutes =
        tracks.fold<int>(0, (sum, t) => sum + t.duration.inSeconds) ~/ 60;
    final counts = <AppSection, String>{
      AppSection.songs: '${tracks.length} músicas',
      AppSection.albums: '$albums álbuns',
      AppSection.artists: '$artists artistas',
      AppSection.years:
          '${tracks.map((t) => t.year).whereType<int>().toSet().length} anos',
      AppSection.genres:
          '${tracks.expand((t) => t.genreNames).toSet().length} gêneros',
      AppSection.favorites:
          '${tracks.where((t) => favorites.contains(t.id)).length} músicas favoritas',
      AppSection.playlists: 'Suas seleções e descobertas',
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Sua coleção, em um só lugar',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          '${tracks.length} músicas · $albums álbuns · $artists artistas · ${minutes ~/ 60} h ${minutes % 60} min',
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, size) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final entry in counts.entries)
                SizedBox(
                  width: size.maxWidth < 480
                      ? size.maxWidth
                      : (size.maxWidth -
                                16 * ((size.maxWidth / 240).floor() - 1)) /
                            (size.maxWidth / 240).floor(),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onNavigate(entry.key),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MtIcon(entry.key.icon, size: 32),
                            const SizedBox(height: 20),
                            Text(
                              entry.key.label,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(entry.value),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
