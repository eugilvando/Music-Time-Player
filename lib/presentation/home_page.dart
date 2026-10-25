import 'rounded_select.dart';
import 'design_icon.dart';
import 'mix_artist_picker.dart';
import 'media_card_size.dart';
import 'item_action_region.dart';
import '../persistence/library_store.dart';
import 'artist_portrait.dart';
import 'home_favorite_playlists.dart';
import 'media_details_table.dart';
import 'compact_media_card.dart';
import 'view_style_selector.dart';

import 'dart:async';

import 'ui_language.dart';
import 'home_mix_picker.dart';

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../library/home_catalog.dart';
import '../library/artist_selection.dart';

import '../domain/track.dart';
import '../library/catalog.dart';
import '../settings/app_settings.dart';
import 'catalog_browser.dart';
import 'now_playing_artwork.dart';

const legacyHomeSections = {
  'continue': 'Ouvindo agora',
  'again': 'Ouça novamente',
  'recent': 'Adicionados recentemente',
  'favorite_tracks': 'Faixas favoritas',
  'favorite_albums': 'Álbuns favoritos',
  'popular': 'Mais ouvidos',
  'history': 'Últimas reproduções',
  'mixes': 'Feito para você',
  'offline': 'Disponíveis offline',
  'explore': 'Explore sua biblioteca',
};

const homeSections = {
  'mixes': 'Feito para você',
  'continue': 'Ouvindo agora',
  'favorite_playlists': 'Playlists favoritas',
  'favorite_tracks': 'Faixas favoritas',
  'favorite_albums': 'Álbuns favoritos',
  'favorite_artists': 'Artistas favoritos',
  'discover_albums': 'Descobrir álbuns',
  'discover_artists': 'Descobrir artistas',
  'recent_artists': 'Artistas adicionados recentemente',
  'recent_albums': 'Álbuns adicionados recentemente',
  'most_played_artists': 'Artistas mais ouvidos',
  'history': 'Últimas reproduções',
};
final allHomeSections = {...legacyHomeSections, ...homeSections};

List<String> selectedHomeSections(AppSettings settings) => settings
    .visualList('home_sections', homeSections.keys.toList())
    .expand(
      (key) =>
          key == 'favorites' ? ['favorite_tracks', 'favorite_albums'] : [key],
    )
    .where(allHomeSections.containsKey)
    .toSet()
    .toList();

const homeViewStyles = {
  'grid': {
    'grid': 'Card Grid',
    'compact_grid': 'Compact Card Grid',
    'compact_cards_grid': 'Compact cards',
  },
  'list': {
    'detailed': 'Detailed',
    'compact': 'Compact List',
    'compact_cards_list': 'Compact cards',
  },
  'carousel': {
    'carousel': 'Cards',
    'carousel_compact': 'Compact cards',
    'carousel_3': '3 lines',
    'carousel_5': '5 lines',
    'carousel_small': 'Small cards',
  },
};
bool homeCompactItem(String mode) =>
    mode.startsWith('compact_cards') ||
    {'carousel_compact', 'carousel_3', 'carousel_5'}.contains(mode);
bool homeListMode(String mode) =>
    {'compact', 'detailed', 'compact_cards_list'}.contains(mode);

class HomeCardGrid extends StatelessWidget {
  const HomeCardGrid({
    super.key,
    required this.children,
    this.covers = false,
    this.compact = false,
  });
  final List<Widget> children;
  final bool covers;
  final bool compact;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = compact ? 12.0 : 16.0;
      final preferred =
          MediaCardSizeScope.cardWidth(context) * (compact ? .75 : 1);
      final columns = max(
        1,
        ((constraints.maxWidth + gap) / (preferred + gap)).floor(),
      );
      final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final scaledFont = MediaQuery.textScalerOf(context)
          .scale(Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14);
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children)
            SizedBox(
              width: width,
              height: covers
                  ? width + 12 * scale + scaledFont * 3.2
                  : 120 + scaledFont * 2.8,
              child: ItemActionRegion(child: child),
            ),
        ],
      );
    },
  );
}

String homeSectionMode(AppSettings settings, String key) {
  if (key == 'mixes') return 'grid';
  try {
    final modes = jsonDecode(
      settings.visualChoice('home_modes', '{}'),
    ) as Map<String, dynamic>;
    return modes[key] as String? ??
        (key.startsWith('favorite_') ? modes['favorites'] as String? : null) ??
        (key == 'history' ? 'compact' : 'grid');
  } catch (_) {
    return key == 'history' ? 'compact' : 'grid';
  }
}

class HomeCardLayout extends StatelessWidget {
  const HomeCardLayout({
    super.key,
    required this.mode,
    required this.children,
    this.covers = false,
    this.carouselKey,
  });
  final GlobalKey<HomeCarouselState>? carouselKey;
  final String mode;
  final List<Widget> children;
  final bool covers;
  @override
  Widget build(BuildContext context) {
    if (mode == 'detailed' && children.every((c) => c is CompactMediaCard)) {
      final cards = children.cast<CompactMediaCard>();
      return MediaDetailsTable(
        headers: [ui(context, 'Título'), ui(context, 'Informações'), ''],
        widths: const [320, 300, 64],
        itemCount: cards.length,
        rowBuilder: (i) {
          final card = cards.elementAt(i);
          return [
            InkWell(
              onTap: card.onTap,
              child: Row(
                children: [
                  SizedBox.square(dimension: 32, child: card.artwork),
                  const SizedBox(width: 8),
                  Expanded(child: Text(card.title)),
                ],
              ),
            ),
            Text(card.subtitle),
            card.actions,
          ];
        },
      );
    }
    if (homeListMode(mode)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    if (mode.startsWith('carousel')) {
      return HomeCarousel(
        key: carouselKey,
        showControls: carouselKey == null,
        mode: mode,
        covers: covers,
        children: children,
      );
    }
    if (homeCompactItem(mode)) {
      return LayoutBuilder(
        builder: (context, size) {
          final columns = max(
            1,
            ((size.maxWidth + 12) /
                    (MediaCardSizeScope.horizontalWidth(context) + 12))
                .floor(),
          );
          final width = (size.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final child in children)
                SizedBox(
                  width: width,
                  height: MediaCardSizeScope.horizontalHeight(context),
                  child: child,
                ),
            ],
          );
        },
      );
    }
    return HomeCardGrid(
      covers: covers,
      compact: mode == 'compact_grid',
      children: children,
    );
  }
}

List<Widget> homeCarouselButtons(
  BuildContext context,
  GlobalKey<HomeCarouselState> key,
) => [
  IconButton(
    tooltip: ui(context, 'Anterior'),
    onPressed: () => key.currentState?.move(-1),
    icon: const MtIcon(Icons.chevron_left),
  ),
  IconButton(
    tooltip: ui(context, 'Próxima'),
    onPressed: () => key.currentState?.move(1),
    icon: const MtIcon(Icons.chevron_right),
  ),
];

class HomeCarousel extends StatefulWidget {
  final String mode;
  const HomeCarousel({
    super.key,
    required this.children,
    this.covers = false,
    this.mode = 'carousel',
    this.showControls = true,
  });
  final bool showControls;
  final List<Widget> children;
  final bool covers;
  @override
  State<HomeCarousel> createState() => HomeCarouselState();
}

class HomeCarouselState extends State<HomeCarousel> {
  final controller = ScrollController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void move(int direction) {
    if (!controller.hasClients) return;
    controller.animateTo(
      (controller.offset +
              direction * controller.position.viewportDimension * .8)
          .clamp(0.0, controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final font = scale.scale(
      Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14,
    );
    final requestedRows = widget.mode == 'carousel_3'
        ? 3
        : widget.mode == 'carousel_5'
        ? 5
        : 1;
    final rows = min(requestedRows, max(1, widget.children.length));
    final compact = homeCompactItem(widget.mode);
    final small = widget.mode == 'carousel_small';
    final factor = MediaCardSizeScope.scale(context);
    final itemHeight = compact
        ? MediaCardSizeScope.horizontalHeight(context)
        : (widget.covers
                  ? (small ? 120 : 180) + 24 * scale.scale(1) + font * 3.2
                  : (small ? 96 : 120) + font * 5.6) *
              factor.clamp(1, 1.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showControls)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: ui(context, 'Anterior'),
                onPressed: () => move(-1),
                icon: const MtIcon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: ui(context, 'Próxima'),
                onPressed: () => move(1),
                icon: const MtIcon(Icons.chevron_right),
              ),
            ],
          ),
        SizedBox(
          height: rows * itemHeight + (rows - 1) * 12 + 12,
          child: Scrollbar(
            controller: controller,
            thumbVisibility: true,
            child: GridView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: rows,
                mainAxisExtent: compact
                    ? MediaCardSizeScope.horizontalWidth(context)
                    : (widget.covers
                              ? (small ? 120 : 180)
                              : (small ? 180 : 264)) *
                          factor,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
              ),
              itemCount: widget.children.length,
              itemBuilder: (_, index) => SizedBox(
                width: compact
                    ? 320
                    : widget.covers
                    ? (small ? 120 : 180)
                    : 264,
                child: ItemActionRegion(child: widget.children[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Completer<void>? _homeEditor;
Future<void> customizeHome(BuildContext context, AppSettings settings) {
  if (_homeEditor != null) return _homeEditor!.future;
  final closed = Completer<void>();
  _homeEditor = closed;
  late OverlayEntry entry;
  void close() {
    entry.remove();
    entry.dispose();
    _homeEditor = null;
    closed.complete();
  }

  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: min(420, MediaQuery.sizeOf(context).width * .8),
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Material(
                elevation: 16,
                child: SafeArea(
                  child: MediaCardSizeScope.wrap(
                    settings,
                    AnimatedBuilder(
                      animation: settings,
                      builder: (context, _) {
                        final selected = selectedHomeSections(settings);
                        final order = [
                          ...selected,
                          ...homeSections.keys.where(
                            (k) => !selected.contains(k),
                          ),
                        ];
                        Map<String, dynamic> modes;
                        try {
                          modes = jsonDecode(
                            settings.visualChoice('home_modes', '{}'),
                          ) as Map<String, dynamic>;
                        } catch (_) {
                          modes = {};
                        }
                        return Column(
                          children: [
                            ListTile(
                              title: const UiText('Personalizar início'),
                              subtitle: const UiText(
                                'Alterações aplicadas em tempo real',
                              ),
                              trailing: IconButton(
                                tooltip: ui(context, 'Fechar'),
                                icon: const MtIcon(Icons.close),
                                onPressed: close,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${ui(context, 'Espaçamento entre seções')}: ${settings.visualNumber('home_section_spacing', 24).round()} px",
                                  ),
                                  Slider(
                                    key: const ValueKey('home.sectionSpacing'),
                                    value: settings
                                        .visualNumber(
                                          'home_section_spacing',
                                          24,
                                        )
                                        .clamp(0, 96)
                                        .toDouble(),
                                    min: 0,
                                    max: 96,
                                    divisions: 24,
                                    onChanged: (v) => settings.updateVisual(
                                      'home_section_spacing',
                                      v,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ReorderableListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: order.length,
                                onReorderItem: (oldIndex, newIndex) {
                                  order.insert(
                                    newIndex,
                                    order.removeAt(oldIndex),
                                  );
                                  settings.updateVisual(
                                    'home_sections',
                                    order.where(selected.contains).toList(),
                                  );
                                },
                                itemBuilder: (context, i) {
                                  final key = order[i];
                                  final count = settings
                                      .visualNumber(
                                        'home_count_$key',
                                        settings.visualNumber(
                                          key.startsWith('favorite_')
                                              ? 'home_count_favorites'
                                              : 'home_count',
                                          12,
                                        ),
                                      )
                                      .clamp(1, 100);
                                  return Card(
                                    key: ValueKey(key),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        children: [
                                          SwitchListTile(
                                            title: UiText(
                                              allHomeSections[key]!,
                                            ),
                                            value: selected.contains(key),
                                            onChanged: (v) {
                                              final next = List<String>.of(
                                                selected,
                                              );
                                              if (v) {
                                                next.add(key);
                                              } else {
                                                next.remove(key);
                                              }
                                              settings.updateVisual(
                                                'home_sections',
                                                order
                                                    .where(next.contains)
                                                    .toList(),
                                              );
                                            },
                                          ),
                                          if (key != 'continue') ...[
                                            UiText(
                                              'Quantidade de itens: ${count.round()}',
                                            ),
                                            Slider(
                                              value: count.toDouble(),
                                              min: 1,
                                              max: 100,
                                              divisions: 99,
                                              onChanged: (v) =>
                                                  settings.updateVisual(
                                                    'home_count_$key',
                                                    v,
                                                  ),
                                            ),
                                          ],
                                          if (key != 'continue' &&
                                              key != 'mixes')
                                            MediaCardSizeScope.homeSection(
                                              settings,
                                              key,
                                              ViewStyleSelector(
                                                key: ValueKey(
                                                  'home.style.$key',
                                                ),
                                                value: homeSectionMode(
                                                  settings,
                                                  key,
                                                ),
                                                families: homeViewStyles,
                                                onChanged: (v) {
                                                  modes[key] = v;
                                                  settings.updateVisual(
                                                    'home_modes',
                                                    jsonEncode(modes),
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Overlay.of(context).insert(entry);
  return closed.future;
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.index,
    required this.tracks,
    required this.settings,
    required this.onAction,
    required this.onPlay,
    this.onPlayNamed,
    this.onArtistSelection,
    required this.trackActions,
    required this.onExplore,
    required this.onAddSource,
    required this.library,
    this.onResume,
    this.onNowPlaying,
    this.resumeTitle,
    this.onFilters,
    this.activeFilters,
    this.lastfmMix,
    this.memory,
    this.cacheKey,
    this.onSources,
    this.resumeTrack,
    this.resumePlaying = false,
    this.store,
    this.playlists = const [],
    this.onPlaylist,
  });
  final Future<void> Function(List<Track>, int, String)? onPlayNamed;
  final Future<void> Function(String, bool, List<Track>, String)?
  onArtistSelection;
  final Track? resumeTrack;
  final bool resumePlaying;
  final LibraryStore? store;
  final List<Map<String, Object?>> playlists;
  final void Function(int)? onPlaylist;
  final CatalogIndex index;
  final VoidCallback? onSources;
  final Map<String, HomeData>? memory;
  final String? cacheKey;
  final List<Track> tracks;
  final AppSettings settings;
  final Future<void> Function(String, List<Track>) onAction;
  final Future<void> Function(List<Track>, int) onPlay;
  final Widget Function(Track) trackActions;
  final void Function(String, CatalogGroup?) onExplore;
  final VoidCallback onAddSource;
  final Widget library;
  final VoidCallback? onResume;
  final VoidCallback? onNowPlaying;
  final String? resumeTitle;
  final VoidCallback? onFilters;
  final Widget? activeFilters;
  final Future<List<Track>> Function(String)? lastfmMix;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final carouselKeys = <String, GlobalKey<HomeCarouselState>>{};
  GlobalKey<HomeCarouselState> carouselKey(String section) =>
      carouselKeys.putIfAbsent(section, () => GlobalKey<HomeCarouselState>());
  bool exploring = false;
  String quickFilter = 'all';
  String signature = '';
  double get sectionSpacing => widget.settings
      .visualNumber('home_section_spacing', 24)
      .clamp(0, 96)
      .toDouble();
  Map<String, List<Track>> mixes = {};
  String get dataSignature =>
      '${identityHashCode(widget.index)}:${widget.cacheKey ?? identityHashCode(widget.tracks)}:${widget.settings.visualNumber('home_mix_size', 20)}';
  String derivedSignature = '';
  Map<String, List<Track>> derivedLists = {};
  List<(String, CatalogGroup)> exploreGroups = [];
  Map<String, List<CatalogGroup>> preparedCollections = {};
  String? pendingHomeSignature, homeError;
  int homeGeneration = 0;
  Future<HomeData>? activeHomeWork;
  @override
  void dispose() {
    homeGeneration++;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    regenerate(refresh: false);
  }

  @override
  void didUpdateWidget(covariant HomePage old) {
    super.didUpdateWidget(old);
    if (dataSignature != signature) regenerate(refresh: false);
  }

  void regenerate({bool refresh = true}) {
    if (refresh) widget.memory?.remove('$dataSignature:$quickFilter');
    signature = dataSignature;
    derivedSignature = '';
    pendingHomeSignature = null;
    homeGeneration++;
  }

  void all(String title, List<Track> values) {
    widget.onExplore('songs', CatalogGroup('home:$title', title, values));
    setState(() => exploring = true);
  }

  Future<void> configureMixSize() async {
    var count = widget.settings
        .visualNumber('home_mix_size', 20)
        .clamp(1, 100)
        .toDouble();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          title: const UiText('Tamanho dos mixes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiText('Faixas: ${count.round()}'),
              Slider(
                value: count,
                min: 1,
                max: 100,
                divisions: 99,
                onChanged: (value) => update(() => count = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const UiText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const UiText('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    await widget.settings.updateVisual('home_mix_size', count);
    if (mounted) setState(regenerate);
  }

  bool choosingMix = false;
  Future<void> configureMix(
    String name,
    List<Track> initial, {
    String action = 'play',
  }) async {
    if (choosingMix) return;
    choosingMix = true;
    try {
      await selectAndPlayMix(name, initial, action: action);
    } finally {
      choosingMix = false;
    }
  }

  Future<void> selectAndPlayMix(
    String name,
    List<Track> initial, {
    required String action,
  }) async {
    final values = derivedLists['values'] ?? widget.tracks;
    if (homeMixType(name) == 'artists' || homeMixType(name) == 'artist_radio') {
      final artists = suggestedMixArtists(widget.index, values);
      if (artists.isEmpty) return;
      final artist = await pickMixArtist(context, artists);
      if (artist != null && mounted) {
        if (widget.onArtistSelection != null) {
          await widget.onArtistSelection!(
            artist,
            homeMixType(name) == 'artist_radio',
            values,
            action,
          );
        } else if (homeMixType(name) == 'artists') {
          final result = artistSelection(
            values,
            artist,
            count: widget.settings.artistSelectionSize(),
          );
          if (result.isEmpty) return;
          if (widget.onPlayNamed != null) {
            await widget.onPlayNamed!(
              result,
              0,
              '${ui(context, 'Artist mix')} - $artist',
            );
          } else {
            await widget.onPlay(result, 0);
          }
        }
      }
      return;
    }
    final selector = {
      'artists',
      'genres',
      'decades',
    }.contains(homeMixType(name));
    final artists = values.expand((t) => t.artistNames).toSet().toList()
      ..sort();
    String? artist = name.startsWith('Artista · ')
        ? name.substring(10)
        : artists.firstOrNull;
    final genres = values.expand((t) => t.genreNames).toSet().toList()..sort();
    final chosen = <String>{};
    if (name.startsWith('Mix · ')) chosen.add(name.substring(6));
    final years = values.map((t) => t.year).whereType<int>().toList()..sort();
    final useYears = homeMixType(name) == 'decades';
    var range = RangeValues(
      years.isEmpty ? 1900 : years.first.toDouble(),
      years.isEmpty ? 2030 : years.last.toDouble(),
    );
    if (useYears) {
      final decade = int.tryParse(
        RegExp(r'\d{4}').firstMatch(name)?.group(0) ?? '',
      );
      if (decade != null && years.isNotEmpty) {
        range = RangeValues(
          decade.toDouble().clamp(range.start, range.end),
          (decade + 9).toDouble().clamp(range.start, range.end),
        );
      }
    }
    final count = widget.settings
        .visualNumber('home_mix_size', 20)
        .clamp(1, 100);
    final accepted =
        !selector ||
        (await showDialog<bool>(
              context: context,
              builder: (context) => StatefulBuilder(
                builder: (context, update) => AlertDialog(
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  title: UiText(name),
                  scrollable: true,
                  content: SizedBox(
                    width: 480,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (homeMixType(name) == 'artists')
                          DropdownMenu<String>(
                            label: const UiText('Artista'),
                            initialSelection: artist,
                            enableFilter: true,
                            enableSearch: true,
                            menuHeight: 250,
                            dropdownMenuEntries: [
                              for (final a in artists)
                                DropdownMenuEntry(value: a, label: a),
                            ],
                            onSelected: (value) => update(() => artist = value),
                          ),
                        if (name.startsWith('Mix · ')) ...[
                          const UiText(
                            'Gêneros · nenhum selecionado usa todos',
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final genre in genres)
                                FilterChip(
                                  label: Text(genre),
                                  selected: chosen.contains(genre),
                                  onSelected: (v) => update(
                                    () => v
                                        ? chosen.add(genre)
                                        : chosen.remove(genre),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (useYears && years.isNotEmpty) ...[
                          Text('${range.start.round()} – ${range.end.round()}'),
                          if (years.first != years.last)
                            RangeSlider(
                              values: range,
                              min: years.first.toDouble(),
                              max: years.last.toDouble(),
                              divisions: years.last - years.first,
                              onChanged: (v) => update(() => range = v),
                            ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const UiText('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const UiText('Criar e reproduzir mix'),
                    ),
                  ],
                ),
              ),
            ) ==
            true);
    if (accepted != true || !mounted) return;
    try {
      List<Track> pool;
      if (name.startsWith('Last.fm')) {
        pool = await widget.lastfmMix!(
          name.contains('mês') ? '1month' : 'overall',
        );
        final ids = values.map((t) => t.id).toSet();
        pool = pool.where((t) => ids.contains(t.id)).toList();
      } else if (selector) {
        pool = values
            .where(
              (t) =>
                  (!name.contains('favoritos') || widget.index.isFavorite(t)) &&
                  (!name.contains('offline') ||
                      widget.index.offline.contains(t.id)) &&
                  (!name.contains('Descobertas') ||
                      widget.index.plays(t) == 0) &&
                  (!name.contains('Redescobertas') ||
                      widget.index.plays(t) > 0) &&
                  (homeMixType(name) != 'artists' ||
                      t.artistNames.contains(artist)) &&
                  (chosen.isEmpty || t.genreNames.any(chosen.contains)) &&
                  (!useYears ||
                      (t.year != null &&
                          t.year! >= range.start &&
                          t.year! <= range.end)),
            )
            .toList();
        pool = widget.index.mix(pool, count.round(), Random());
      } else {
        pool = initial;
      }
      final result = pool.take(count.round()).toList();
      if (!mounted) return;
      if (result.isEmpty) throw StateError('Sem faixas correspondentes');
      if (action == 'play' ||
          (action == 'shuffle' && widget.onPlayNamed != null)) {
        if (action == 'shuffle') result.shuffle();
        final label = [
          ui(context, name),
          if (homeMixType(name) == 'artists' && artist != null) artist!,
          if (useYears) '${range.start.round()} – ${range.end.round()}',
          if (chosen.isNotEmpty) chosen.join(', '),
        ].join(' · ');
        if (widget.onPlayNamed != null) {
          await widget.onPlayNamed!(result, 0, label);
        } else {
          await widget.onPlay(result, 0);
        }
      } else {
        await widget.onAction(action, result);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: UiText(
              'Não foi possível criar o mix. Confira os filtros e a configuração Last.fm.',
            ),
          ),
        );
      }
    }
  }

  Widget menu(List<Track> values, {String? mixName, String? artistName}) {
    if (mixName != null &&
        {'artists', 'artist_radio'}.contains(homeMixType(mixName))) {
      return PopupMenuButton<String>(
        tooltip: ui(context, 'Selection actions'),
        onSelected: (action) => configureMix(mixName, values, action: action),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'play', child: UiText('Play')),
          PopupMenuItem(value: 'preview', child: UiText('Preview selection')),
          PopupMenuItem(value: 'regenerate', child: UiText('Regenerate')),
          PopupMenuItem(value: 'save', child: UiText('Save as playlist')),
        ],
      );
    }
    return PopupMenuButton<String>(
      tooltip: ui(context, 'Ações da seleção'),
      onSelected: (v) =>
          artistName != null && (v == 'artist_mix' || v == 'artist_radio')
          ? widget.onArtistSelection?.call(
              artistName,
              v == 'artist_radio',
              derivedLists['values'] ?? widget.tracks,
              'preview',
            )
          : v == 'mix_size'
          ? configureMixSize()
          : mixName != null
          ? configureMix(mixName, values, action: v)
          : widget.onAction(v, List.of(values)),
      itemBuilder: (_) => [
        if (artistName != null && widget.onArtistSelection != null) ...[
          const PopupMenuItem(value: 'artist_mix', child: UiText('Artist mix')),
          const PopupMenuItem(
            value: 'artist_radio',
            child: UiText('Artist radio'),
          ),
        ],
        if (mixName != null)
          const PopupMenuItem(
            value: 'mix_size',
            child: UiText('Tamanho dos mixes'),
          ),
        const PopupMenuItem(value: 'play', child: UiText('Reproduzir')),
        if (mixName == null && artistName == null)
          const PopupMenuItem(
            value: 'mix',
            child: UiText('Iniciar mix a partir deste item'),
          ),
        const PopupMenuItem(
          value: 'shuffle',
          child: UiText('Reproduzir aleatoriamente'),
        ),
        const PopupMenuItem(value: 'next', child: UiText('Tocar a seguir')),
        const PopupMenuItem(value: 'queue', child: UiText('Adicionar à fila')),
        const PopupMenuItem(
          value: 'save',
          child: UiText('Salvar seleção como playlist'),
        ),
        const PopupMenuItem(
          value: 'offline',
          child: UiText('Disponibilizar offline'),
        ),
      ],
    );
  }

  Widget section(String key, List<Track> values) {
    if (values.isEmpty) {
      if (!homeSections.containsKey(key)) return const SizedBox.shrink();
      return Padding(
        key: ValueKey('home.section.$key'),
        padding: EdgeInsets.only(top: sectionSpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UiText(
              allHomeSections[key]!,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const UiText('No items available for this section yet.'),
          ],
        ),
      );
    }
    final limit = widget.settings
        .visualNumber(
          'home_count_$key',
          widget.settings.visualNumber(
            key.startsWith('favorite_') ? 'home_count_favorites' : 'home_count',
            12,
          ),
        )
        .round();
    final tracks = values.take(limit).toList();
    final mode = homeSectionMode(widget.settings, key);
    Widget tile(Track t) => ItemActionRegion(
      child: ListTile(
        dense:
            mode == 'compact' ||
            widget.settings.visualBool('catalog_dense', fallback: false),
        leading: SizedBox.square(dimension: 44, child: TrackCover(track: t)),
        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          mode == 'detailed'
              ? '${t.artistNames.join('; ')} · ${t.album.isEmpty ? ui(context, 'Sem álbum') : t.album} · ${catalogTime(t.duration)} · ${widget.index.plays(t)} ${ui(context, 'reproduções')}'
              : t.artistNames.join('; '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: widget.trackActions(t),
        onTap: () => widget.onPlay(values, values.indexOf(t)),
      ),
    );

    Widget card(Track t) => homeCompactItem(mode)
        ? CompactMediaCard(
            artwork: TrackCover(track: t),
            title: t.title,
            subtitle: t.artist,
            actions: widget.trackActions(t),
            onTap: () => widget.onPlay(values, values.indexOf(t)),
          )
        : SizedBox(
            width: mode == 'wide' ? 310 : 180,
            child: InkWell(
              onTap: () => widget.onPlay(values, values.indexOf(t)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      children: [
                        Positioned.fill(child: TrackCover(track: t)),
                        Positioned(
                          top: 0,
                          left: 0,
                          child: IconButton(
                            tooltip: ui(context, 'Reproduzir'),
                            onPressed: () =>
                                widget.onPlay(values, values.indexOf(t)),
                            icon: const MtIcon(Icons.play_arrow),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: widget.trackActions(t),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    t.artistNames.join('; '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
    return Padding(
      key: ValueKey('home.section.$key'),
      padding: EdgeInsets.only(top: sectionSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: UiText(
                  allHomeSections[key]!,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () => all(homeSections[key]!, values),
                child: const UiText('Ver tudo'),
              ),
              if (mode.startsWith('carousel'))
                ...homeCarouselButtons(context, carouselKey(key)),
            ],
          ),
          const SizedBox(height: 24),
          if (mode == 'detailed')
            MediaDetailsTable(
              headers: [
                ui(context, 'Título'),
                ui(context, 'Artista'),
                ui(context, 'Álbum'),
                ui(context, 'Duração'),
                ui(context, 'Reproduções'),
                '',
              ],
              widths: const [300, 200, 220, 120, 100, 64],
              itemCount: tracks.length,
              rowBuilder: (i) {
                final t = tracks[i];
                return [
                  InkWell(
                    onTap: () => widget.onPlay(values, values.indexOf(t)),
                    child: Text(t.title),
                  ),
                  Text(t.artist),
                  Text(t.album),
                  Text(ui(context, catalogTime(t.duration))),
                  Text(widget.index.plays(t).toString()),
                  widget.trackActions(t),
                ];
              },
            )
          else if (mode == 'compact')
            ...tracks.map(tile)
          else
            HomeCardLayout(
              carouselKey: carouselKey(key),
              mode: mode,
              covers: true,
              children: tracks.map(card).toList(),
            ),
        ],
      ),
    );
  }

  Widget collectionSection(String key, List<CatalogGroup> groups, String type) {
    final mode = homeSectionMode(widget.settings, key);
    final count = widget.settings.visualNumber('home_count_$key', 12).round();
    void open(CatalogGroup group) {
      widget.onExplore(type, group);
      setState(() => exploring = true);
    }

    Widget artwork(CatalogGroup group) => type == 'albums'
        ? TrackCover(
            album: true,
            track: group.tracks.firstWhere(
              (t) => t.hasArtwork,
              orElse: () => group.tracks.first,
            ),
          )
        : ArtistPortrait(
            artist: group.name,
            fallbackTrack: group.tracks.where((t) => t.hasArtwork).firstOrNull,
            enabled: widget.settings.visualBool('artist_photos'),
            cachedOnly: widget.settings.visualBool(
              'offline_only',
              fallback: false,
            ),
          );
    final items = groups.take(count).map((group) {
      final subtitle = type == 'albums'
          ? group.tracks.first.albumArtistNames.join('; ')
          : '${group.tracks.length} ${ui(context, 'faixas')}';
      if (homeCompactItem(mode) || mode == 'detailed') {
        return CompactMediaCard(
          artwork: artwork(group),
          title: group.name,
          subtitle: subtitle,
          actions: menu(
            group.tracks,
            artistName: type == 'albums' ? null : group.name,
          ),
          onTap: () => open(group),
        );
      }
      if (mode == 'compact') {
        return ItemActionRegion(
          child: ListTile(
            dense: true,
            leading: SizedBox.square(dimension: 44, child: artwork(group)),
            title: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: menu(
              group.tracks,
              artistName: type == 'albums' ? null : group.name,
            ),
            onTap: () => open(group),
          ),
        );
      }
      return InkWell(
        onTap: () => open(group),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(child: artwork(group)),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: IconButton(
                      tooltip: ui(context, 'Reproduzir'),
                      onPressed: () => widget.onPlay(group.tracks, 0),
                      icon: const MtIcon(Icons.play_arrow),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: menu(
                      group.tracks,
                      artistName: type == 'albums' ? null : group.name,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
    }).toList();
    return Padding(
      key: ValueKey('home.section.$key'),
      padding: EdgeInsets.only(top: sectionSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: UiText(
                  allHomeSections[key]!,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (key == 'favorite_artists')
                RoundedSelect(
                  child: DropdownButton<String>(
                    value: type,
                    items: const [
                      DropdownMenuItem(
                        value: 'artists',
                        child: UiText('Artists'),
                      ),
                      DropdownMenuItem(
                        value: 'albumArtists',
                        child: UiText('Album artists'),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value != null) {
                        await widget.settings.updateVisual(
                          'home_artist_role',
                          value,
                        );
                        if (mounted) setState(() {});
                      }
                    },
                  ),
                ),
              if (groups.isNotEmpty)
                TextButton(
                  onPressed: () => open(
                    CatalogGroup(
                      'home:$key',
                      ui(context, allHomeSections[key]!),
                      groups.expand((g) => g.tracks).toList(),
                    ),
                  ),
                  child: const UiText('Ver tudo'),
                ),
              if (mode.startsWith('carousel') && groups.isNotEmpty)
                ...homeCarouselButtons(context, carouselKey(key)),
            ],
          ),
          const SizedBox(height: 24),
          if (groups.isEmpty)
            const UiText('No items available for this section yet.')
          else
            HomeCardLayout(
              carouselKey: carouselKey(key),
              mode: mode,
              covers: true,
              children: items,
            ),
        ],
      ),
    );
  }

  Widget keepListening(List<Track> visible) {
    final track = widget.resumeTrack;
    final available =
        widget.onResume != null &&
        (track == null || visible.any((t) => t.id == track.id));
    return Card(
      key: const ValueKey('home.section.continue'),
      margin: EdgeInsets.only(top: sectionSpacing),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: InkWell(
        onTap: widget.onNowPlaying,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, space) {
              final cover = SizedBox.square(
                dimension: space.maxWidth < 460 ? 72 : 96,
                child: TrackCover(track: track),
              );
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  UiText(
                    'Ouvindo agora',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    track?.title ??
                        widget.resumeTitle ??
                        ui(context, 'Sessão atual'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (track != null)
                    Text(
                      track.artist +
                          (track.album.isEmpty ? '' : ' · ${track.album}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (!available)
                    const UiText('Start a track to keep listening here.'),
                ],
              );
              final play = FilledButton.icon(
                onPressed: available ? widget.onResume : null,
                icon: MtIcon(
                  widget.resumePlaying ? Icons.pause : Icons.play_arrow,
                  size: 20,
                ),
                label: UiText(widget.resumePlaying ? 'Pausar' : 'Reproduzir'),
              );
              return Row(
                children: [
                  cover,
                  const SizedBox(width: 24),
                  Expanded(child: details),
                  const SizedBox(width: 12),
                  if (space.maxWidth >= 460)
                    play
                  else
                    IconButton.filled(
                      tooltip: ui(
                        context,
                        widget.resumePlaying ? 'Pausar' : 'Reproduzir',
                      ),
                      onPressed: available ? widget.onResume : null,
                      icon: MtIcon(
                        widget.resumePlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (exploring) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                widget.onExplore('songs', null);
                setState(() => exploring = false);
              },
              icon: const MtIcon(Icons.arrow_back),
              label: const UiText('Voltar ao início'),
            ),
          ),
          Expanded(child: widget.library),
        ],
      );
    }
    if (widget.tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const UiText(
              'Sua biblioteca reunida em um só lugar',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: widget.onAddSource,
              icon: const MtIcon(Icons.add),
              label: const UiText('Adicionar fonte'),
            ),
          ],
        ),
      );
    }
    final currentSignature = '$dataSignature:$quickFilter';
    final saved = widget.memory?[currentSignature];
    if (derivedSignature != currentSignature && saved != null) {
      homeGeneration++;
      derivedSignature = currentSignature;
      derivedLists = saved.lists;
      mixes = saved.mixes;
      exploreGroups = saved.explore;
      preparedCollections = saved.collections;
    }
    // Reuse only snapshots with the same eligible IDs: hidden sources and
    // offline filters must never leak tracks from a previous view.
    if (derivedLists.isEmpty && widget.memory?.isNotEmpty == true) {
      final previous = widget.memory!.values.last;
      final oldIds = previous.lists['values']!.map((t) => t.id).toSet();
      final newIds = widget.tracks.map((t) => t.id).toSet();
      if (setEquals(oldIds, newIds)) {
        derivedLists = previous.lists;
        mixes = previous.mixes;
        exploreGroups = previous.explore;
        preparedCollections = previous.collections;
      }
    }
    if (widget.tracks.length > 1000 && derivedSignature != currentSignature) {
      if (pendingHomeSignature != currentSignature) {
        pendingHomeSignature = currentSignature;
        homeError = null;
        final request = ++homeGeneration;
        final work = (
          index: widget.index,
          tracks: widget.tracks,
          quick: quickFilter,
          limit: widget.settings.visualNumber('home_mix_size', 20).round(),
          lastfm: widget.lastfmMix != null,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || request != homeGeneration) return;
          Future<HomeData>? job;
          try {
            await Future<void>.delayed(const Duration(milliseconds: 180));
            if (!mounted || request != homeGeneration) return;
            final active = activeHomeWork;
            if (active != null) {
              try {
                await active;
              } catch (_) {}
            }
            if (!mounted || request != homeGeneration) return;
            job = compute(prepareHome, work);
            activeHomeWork = job;
            final result = await job;
            if (!mounted || request != homeGeneration) return;
            setState(() {
              final memory = widget.memory;
              if (memory != null) {
                memory[currentSignature] = result;
                while (memory.length > 2) {
                  memory.remove(memory.keys.first);
                }
              }
              derivedSignature = currentSignature;
              derivedLists = result.lists;
              mixes = result.mixes;
              exploreGroups = result.explore;
              preparedCollections = result.collections;
            });
          } catch (_) {
            if (mounted && request == homeGeneration) {
              setState(
                () => homeError =
                    'Não foi possível preparar o início. Tente novamente.',
              );
            }
          } finally {
            if (identical(activeHomeWork, job)) activeHomeWork = null;
          }
        });
      }
      if (derivedLists.isEmpty) {
        return homeError == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    pendingHomeSignature = null;
                  }),
                  child: UiText(homeError!),
                ),
              );
      }
    }
    if (widget.tracks.length <= 1000 && derivedSignature != currentSignature) {
      final result = prepareHome((
        index: widget.index,
        tracks: widget.tracks,
        quick: quickFilter,
        limit: widget.settings.visualNumber('home_mix_size', 20).round(),
        lastfm: widget.lastfmMix != null,
      ));
      derivedSignature = currentSignature;
      derivedLists = result.lists;
      mixes = result.mixes;
      exploreGroups = result.explore;
      preparedCollections = result.collections;
      final memory = widget.memory;
      if (memory != null) {
        memory[currentSignature] = result;
        while (memory.length > 2) {
          memory.remove(memory.keys.first);
        }
      }
    }
    final values = derivedLists['values']!,
        recent = derivedLists['recent']!,
        history = derivedLists['history']!,
        popular = derivedLists['popular']!;
    final visibleIds = values.map((t) => t.id).toSet();
    final sections = selectedHomeSections(widget.settings);
    return ListView(
      key: const PageStorageKey('home.content'),
      children: [
        if (widget.tracks.length > 1000 && derivedSignature != currentSignature)
          const LinearProgressIndicator(),
        LayoutBuilder(
          builder: (context, constraints) {
            final heading = UiText(
              'Sua música, em todo lugar',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700, fontSize: 32),
            );
            final actions = <Widget>[
              FilterChip(
                key: const ValueKey('home.offline'),
                label: UiText(
                  quickFilter == 'offline' ? 'Offline only' : 'All music',
                ),
                selected: quickFilter == 'offline',
                onSelected: (value) =>
                    setState(() => quickFilter = value ? 'offline' : 'all'),
              ),
              IconButton(
                key: const ValueKey('home.sources'),
                tooltip: ui(context, 'Fontes'),
                onPressed: widget.onSources,
                icon: const MtIcon(Icons.storage),
              ),
              IconButton(
                key: const ValueKey('home.customize'),
                tooltip: ui(context, 'Personalizar início'),
                onPressed: () => customizeHome(context, widget.settings),
                icon: const MtIcon(Icons.tune),
              ),
            ];
            if (constraints.maxWidth <
                700 * MediaQuery.textScalerOf(context).scale(1)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                ...actions,
              ],
            );
          },
        ),
        const UiText('Sua biblioteca reunida em um só lugar'),
        const SizedBox(height: 12),
        if (widget.activeFilters != null) widget.activeFilters!,
        for (final key in sections)
          MediaCardSizeScope.homeSection(
            widget.settings,
            key,
            key == 'continue'
                ? keepListening(values)
                : (key == 'mixes')
                ? Padding(
                    key: ValueKey('home.section.$key'),
                    padding: EdgeInsets.only(top: sectionSpacing),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: UiText(
                                'Feito para você',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              tooltip: ui(context, 'Escolher modelos'),
                              onPressed: () async {
                                await customizeHomeMixes(
                                  context,
                                  widget.settings,
                                );
                                if (mounted) setState(() {});
                              },
                              icon: const MtIcon(Icons.dashboard_customize),
                            ),
                            IconButton(
                              tooltip: ui(context, 'Regenerar mixes'),
                              onPressed: () => setState(regenerate),
                              icon: const MtIcon(Icons.refresh),
                            ),
                          ],
                        ),
                        const UiText(
                          'Seleções da sua coleção; diversidade de artistas, sem análise sonora.',
                        ),
                        const SizedBox(height: 24),
                        HomeCardLayout(
                          mode: homeSectionMode(widget.settings, 'mixes'),
                          children: [
                            for (final mix
                                in orderedHomeMixes(mixes, widget.settings)
                                    .entries
                                    .map(
                                      (entry) => MapEntry(
                                        entry.key,
                                        entry.value
                                            .where(
                                              (track) =>
                                                  visibleIds.contains(track.id),
                                            )
                                            .toList(),
                                      ),
                                    )
                                    .where(
                                      (e) =>
                                          e.value.isNotEmpty ||
                                          e.key.startsWith('Last.fm') ||
                                          homeMixType(e.key) == 'artist_radio',
                                    )
                                    .take(
                                      widget.settings
                                          .visualNumber('home_count_mixes', 12)
                                          .round(),
                                    ))
                              if (homeCompactItem(
                                    homeSectionMode(widget.settings, 'mixes'),
                                  ) ||
                                  homeListMode(
                                    homeSectionMode(widget.settings, 'mixes'),
                                  ))
                                CompactMediaCard(
                                  artwork: const MtIcon(Icons.auto_awesome),
                                  title: homeMixLabel(context, mix.key),
                                  subtitle: homeMixReference(mix.key).isNotEmpty
                                      ? homeMixReference(mix.key)
                                      : '${mix.value.length} ${ui(context, 'faixas')}',
                                  actions: menu(mix.value, mixName: mix.key),
                                  onTap: () => configureMix(mix.key, mix.value),
                                )
                              else
                                Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Theme.of(context)
                                              .colorScheme
                                              .surfaceContainer,
                                          homeMixColor(mix.key)
                                              .withValues(alpha: .32),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: InkWell(
                                      onTap: () =>
                                          configureMix(mix.key, mix.value),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                MtIcon(
                                                  mix.key.contains('favoritos')
                                                      ? Icons.favorite
                                                      : homeMixType(mix.key) ==
                                                            'decades'
                                                      ? Icons.history
                                                      : mix.key.contains(
                                                          'offline',
                                                        )
                                                      ? Icons.offline_pin
                                                      : homeMixType(mix.key) ==
                                                            'artists'
                                                      ? Icons.person
                                                      : mix.key.contains(
                                                          'Descobertas',
                                                        )
                                                      ? Icons.explore
                                                      : Icons.auto_awesome,
                                                  size: 32,
                                                ),
                                                const Spacer(),
                                                menu(
                                                  mix.value,
                                                  mixName: mix.key,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              homeMixLabel(context, mix.key),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              homeMixReference(mix.key)
                                                      .isNotEmpty
                                                  ? homeMixReference(mix.key)
                                                  : mix.key.startsWith(
                                                      'Last.fm',
                                                    )
                                                  ? ui(
                                                      context,
                                                      'Consultar seu perfil',
                                                    )
                                                  : homeMixType(mix.key) ==
                                                        'artists'
                                                  ? 'Choose an artist'
                                                  : homeMixType(mix.key) ==
                                                        'decades'
                                                  ? 'Choose a period'
                                                  : '${mix.value.length} ${ui(context, 'faixas da biblioteca')}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
                  )
                : (key == 'explore')
                ? Padding(
                    padding: EdgeInsets.only(top: sectionSpacing),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UiText(
                          'Explore sua biblioteca',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 24),
                        HomeCardLayout(
                          mode: homeSectionMode(widget.settings, 'explore'),
                          children: [
                            for (final item in exploreGroups.take(
                              widget.settings
                                  .visualNumber('home_count_explore', 12)
                                  .round(),
                            ))
                              if (homeCompactItem(
                                    homeSectionMode(widget.settings, 'explore'),
                                  ) ||
                                  homeListMode(
                                    homeSectionMode(widget.settings, 'explore'),
                                  ))
                                CompactMediaCard(
                                  artwork: const MtIcon(Icons.explore),
                                  title: item.$2.name,
                                  subtitle:
                                      '${item.$2.tracks.length} ${ui(context, 'faixas')}',
                                  actions: menu(item.$2.tracks),
                                  onTap: () {
                                    widget.onExplore(item.$1, item.$2);
                                    setState(() => exploring = true);
                                  },
                                )
                              else
                                Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () {
                                      widget.onExplore(item.$1, item.$2);
                                      setState(() => exploring = true);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Row(
                                            children: [
                                              const MtIcon(Icons.explore),
                                              const Spacer(),
                                              menu(item.$2.tracks),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            item.$2.name,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
                  )
                : (key == 'favorite_playlists')
                ? HomeFavoritePlaylists(
                    settings: widget.settings,
                    store: widget.store,
                    playlists: widget.playlists,
                    tracks: values,
                    mode: homeSectionMode(widget.settings, key),
                    onOpen: widget.onPlaylist,
                    onPlay: widget.onPlay,
                    onPlayNamed: widget.onPlayNamed,
                    onAction: widget.onAction,
                  )
                : (preparedCollections.containsKey(key))
                ? collectionSection(
                    key,
                    key == 'favorite_artists' &&
                            widget.settings.visualChoice(
                                  'home_artist_role',
                                  'albumArtists',
                                ) ==
                                'albumArtists'
                        ? preparedCollections['favorite_album_artists']!
                        : preparedCollections[key]!,
                    key.endsWith('albums')
                        ? 'albums'
                        : key == 'favorite_artists'
                        ? widget.settings.visualChoice(
                            'home_artist_role',
                            'albumArtists',
                          )
                        : 'artists',
                  )
                : section(key, switch (key) {
                    'again' || 'history' => history,
                    'recent' => recent,
                    'favorite_tracks' =>
                      values
                          .where((t) => widget.index.favorites.contains(t.id))
                          .toList(),
                    'popular' => popular,
                    'offline' =>
                      values
                          .where((t) => widget.index.offline.contains(t.id))
                          .toList(),
                    _ => [],
                  }),
          ),
        if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: UiText(
              'Ouça músicas para preencher o histórico e as seções Mais ouvidos e Ouça novamente.',
            ),
          ),
      ],
    );
  }
}

Color homeMixColor(String name) {
  if (name.startsWith('Last.fm')) {
    return name.contains('mês')
        ? const Color(0xffff3dbb)
        : const Color(0xffed3838);
  }
  return switch (homeMixType(name)) {
    'artists' => const Color(0xff2584a5),
    'artist_radio' => const Color(0xffb5a929),
    'decades' => const Color(0xff79ff12),
    _ =>
      name.contains('favoritos')
          ? const Color(0xff8953ff)
          : name.contains('Descobertas')
          ? const Color(0xffff9f04)
          : const Color(0xff27cf80),
  };
}
