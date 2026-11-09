import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../settings/app_settings.dart';
import 'navigation.dart';
import 'design_icon.dart';
import 'media_card_size.dart';
import 'ui_language.dart';

class LibraryHub extends StatelessWidget {
  const LibraryHub({
    super.key,
    required this.tracks,
    required this.favorites,
    required this.onNavigate,
    required this.settings,
  });
  final List<Track> tracks;
  final Set<String> favorites;
  final ValueChanged<AppSection> onNavigate;
  final AppSettings settings;

  static const widths = {
    'Extra Small': 160.0,
    'Small': 200.0,
    'Medium': 240.0,
    'Large': 300.0,
    'Extra Large': 360.0,
  };
  static const colors = {
    AppSection.songs: Color(0xFFEB7766),
    AppSection.albums: Color(0xFF9C82E8),
    AppSection.artists: Color(0xFF46BBA2),
    AppSection.years: Color(0xFF64A8E5),
    AppSection.genres: Color(0xFFD8A646),
    AppSection.favorites: Color(0xFFE376A1),
    AppSection.playlists: Color(0xFF838DE5),
    AppSection.history: Color(0xFF54B8C4),
  };

  List<String> get visibleItems => settings.visualList(
    'library_hub_items',
    colors.keys.map((section) => section.name).toList(),
  );

  Future<void> organize(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AnimatedBuilder(
      animation: settings,
      builder: (context, _) => AlertDialog(
        title: Text(
          uiFormat(context, 'Organizar biblioteca', 'Organize library'),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                MediaCardSizePicker(
                  scope: MediaCardSizeScope(
                    value:
                        widths.containsKey(
                          settings.visualChoice(
                            'library_hub_card_size',
                            'Medium',
                          ),
                        )
                        ? settings.visualChoice(
                            'library_hub_card_size',
                            'Medium',
                          )
                        : 'Medium',
                    onChanged: (value) =>
                        settings.updateVisual('library_hub_card_size', value),
                    child: const SizedBox(),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  uiFormat(context, 'Cards visíveis', 'Visible cards'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  uiFormat(
                    context,
                    'Estas escolhas não alteram a sidebar.',
                    'These choices do not change the sidebar.',
                  ),
                ),
                const SizedBox(height: 8),
                for (final section in colors.keys)
                  CheckboxListTile(
                    key: ValueKey('library.visibility.${section.name}'),
                    contentPadding: EdgeInsets.zero,
                    title: UiText(section.label),
                    secondary: MtIcon(section.icon),
                    value: visibleItems.contains(section.name),
                    onChanged: (enabled) {
                      final selected = visibleItems.toSet();
                      if (enabled == true) {
                        selected.add(section.name);
                      } else {
                        selected.remove(section.name);
                      }
                      settings.updateVisual(
                        'library_hub_items',
                        colors.keys
                            .map((s) => s.name)
                            .where(selected.contains)
                            .toList(),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('library.organize.close'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(uiFormat(context, 'Concluir', 'Done')),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) {
      final choice = settings.visualChoice('library_hub_card_size', 'Medium');
      final width = widths[choice] ?? 240;
      final compact = width <= 200;
      final padding = compact ? 16.0 : 24.0;
      final theme = Theme.of(context);
      final dark = theme.brightness == Brightness.dark;
      final albums = tracks
          .where((t) => t.album.isNotEmpty)
          .map((t) => '${t.albumArtist}|${t.album}')
          .toSet()
          .length;
      final artists = tracks.expand((t) => t.artistNames).toSet().length;
      final minutes =
          tracks.fold<int>(0, (sum, t) => sum + t.duration.inSeconds) ~/ 60;
      final counts = <AppSection, String>{
        AppSection.history: uiFormat(
          context,
          'Suas últimas reproduções',
          'Your recent listening',
        ),
        AppSection.songs: uiFormat(
          context,
          '${tracks.length} músicas',
          '${tracks.length} songs',
        ),
        AppSection.albums: uiFormat(
          context,
          '$albums álbuns',
          '$albums albums',
        ),
        AppSection.artists: uiFormat(
          context,
          '$artists artistas',
          '$artists artists',
        ),
        AppSection.years: uiFormat(
          context,
          '${tracks.map((t) => t.year).whereType<int>().toSet().length} anos',
          '${tracks.map((t) => t.year).whereType<int>().toSet().length} years',
        ),
        AppSection.genres: uiFormat(
          context,
          '${tracks.expand((t) => t.genreNames).toSet().length} gêneros',
          '${tracks.expand((t) => t.genreNames).toSet().length} genres',
        ),
        AppSection.favorites: uiFormat(
          context,
          '${tracks.where((t) => favorites.contains(t.id)).length} músicas favoritas',
          '${tracks.where((t) => favorites.contains(t.id)).length} favorite songs',
        ),
        AppSection.playlists: uiFormat(
          context,
          'Suas seleções e descobertas',
          'Your selections and discoveries',
        ),
      };
      return ListView(
        key: const PageStorageKey('library.overview'),
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: UiText(
                  'Biblioteca',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton.filledTonal(
                key: const ValueKey('library.organize'),
                tooltip: uiFormat(
                  context,
                  'Organizar biblioteca',
                  'Organize library',
                ),
                onPressed: () => organize(context),
                icon: const MtIcon(Icons.tune),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: .24),
              ),
              gradient: LinearGradient(
                colors: [
                  Color.alphaBlend(
                    theme.colorScheme.primary.withValues(
                      alpha: dark ? .22 : .12,
                    ),
                    theme.colorScheme.surface,
                  ),
                  Color.alphaBlend(
                    colors[AppSection.albums]!.withValues(
                      alpha: dark ? .14 : .08,
                    ),
                    theme.colorScheme.surface,
                  ),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  uiFormat(
                    context,
                    'Sua coleção, em um só lugar',
                    'Your collection, all together',
                  ),
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  uiFormat(
                    context,
                    '${tracks.length} músicas · $albums álbuns · $artists artistas · ${minutes ~/ 60} h ${minutes % 60} min',
                    '${tracks.length} songs · $albums albums · $artists artists · ${minutes ~/ 60} h ${minutes % 60} min',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (!colors.keys.any(
            (section) => visibleItems.contains(section.name),
          ))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                uiFormat(
                  context,
                  'Nenhum card selecionado. Use Organizar biblioteca para escolher os atalhos.',
                  'No cards selected. Use Organize library to choose your shortcuts.',
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, size) {
              final columns = math.max(
                1,
                ((size.maxWidth + 16) / (width + 16)).floor(),
              );
              final cardWidth = (size.maxWidth - 16 * (columns - 1)) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final section in colors.keys.where(
                    (s) => visibleItems.contains(s.name),
                  ))
                    for (final entry in [MapEntry(section, counts[section]!)])
                      SizedBox(
                        key: ValueKey('library.card.${entry.key.name}'),
                        width: cardWidth,
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colors[entry.key]!.withValues(
                                  alpha: dark ? .32 : .28,
                                ),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color.alphaBlend(
                                    colors[entry.key]!.withValues(
                                      alpha: dark ? .30 : .18,
                                    ),
                                    theme.colorScheme.surface,
                                  ),
                                  Color.alphaBlend(
                                    colors[entry.key]!.withValues(
                                      alpha: dark ? .12 : .07,
                                    ),
                                    theme.colorScheme.surface,
                                  ),
                                ],
                              ),
                            ),
                            child: InkWell(
                              onTap: () => onNavigate(entry.key),
                              child: Stack(
                                children: [
                                  Positioned(
                                    right: -12,
                                    top: -12,
                                    child: ExcludeSemantics(
                                      child: MtIcon(
                                        entry.key.icon,
                                        size: compact ? 88 : 112,
                                        color: colors[entry.key]!.withValues(
                                          alpha: dark ? .10 : .12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(padding),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: colors[entry.key]!
                                                .withValues(alpha: .16),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: MtIcon(
                                            entry.key.icon,
                                            size: compact ? 24 : 32,
                                            color: Color.lerp(
                                              colors[entry.key],
                                              dark
                                                  ? Colors.white
                                                  : Colors.black,
                                              dark ? .25 : .30,
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: compact ? 16 : 22),
                                        UiText(
                                          entry.key.label,
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                fontSize: compact ? 19 : 22,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          entry.value,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        ],
      );
    },
  );
}
