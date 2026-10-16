import '../library/favorite_catalog.dart';
import 'media_card_size.dart';
import 'item_action_region.dart';
import 'compact_media_card.dart';
import 'media_details_table.dart';
import 'view_style_selector.dart';
import '../sources/provider_connections.dart';
import '../library/lastfm_profile.dart';
import 'lastfm_insights.dart';
import 'metadata_editor.dart';
import 'ui_language.dart';
import 'source_visibility_settings.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/track.dart';
import '../library/catalog.dart';
import '../library/home_catalog.dart';
import '../library/catalog_query.dart';
import '../library/local_metadata.dart';
import '../offline/download_manager.dart';
import '../persistence/library_store.dart';
import '../settings/app_settings.dart';
import 'artist_portrait.dart';
import 'artist_biography.dart';
import 'collection_browser.dart';
import 'now_playing_artwork.dart';
import 'home_page.dart';

class CatalogPageSnapshot {
  CatalogPageSnapshot(this.tracks, this.total, this.offset);
  final List<Track> tracks;
  final int total, offset;
}

/// Metadata only; retained by the shell while sections are mounted/unmounted.
class CatalogMemory {
  final pages = <String, CatalogPageSnapshot>{};
  final derived = <String, CatalogResult>{};
  final home = <String, HomeData>{};
  CatalogIndex? index;
  int indexRevision = -1;
  bool ready = false;
  bool dirty = false;
  int catalogRevision = -1;
  int revision = 0;
  Map<String, Map<String, Object?>> stats = {};
  Map<String, List<Map<String, Object?>>> sources = {};
  List<Map<String, Object?>> playlists = [];
  Set<String> offline = {};
  void save(String key, CatalogPageSnapshot page) {
    pages.remove(key);
    pages[key] = page;
    while (pages.length > 8) {
      pages.remove(pages.keys.first);
    }
  }
}

// Database reads produce new maps even when their values have not changed.
bool sameCatalogData(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && sameCatalogData(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length)
            .every((i) => sameCatalogData(a[i], b[i]));
  }
  return a == b;
}

const catalogCategories = {
  'songs': 'Músicas',
  'albums': 'Álbuns',
  'artists': 'Artistas',
  'albumArtists': 'Artistas de álbum',
  'genres': 'Gêneros',
  'years': 'Anos',
  'decades': 'Décadas',
  'folders': 'Pastas',
  'playlists': 'Playlists',
  'favorites': 'Favoritos',
  'offline': 'Disponíveis offline',
};
const catalogColumns = {
  'artist': 'Artista',
  'album': 'Álbum',
  'duration': 'Duração',
  'track': 'Faixa / disco',
  'year': 'Ano',
  'genre': 'Gêneros',
  'format': 'Formato',
  'source': 'Fonte / conta',
  'offline': 'Offline',
  'favorite': 'Favorito',
  'plays': 'Reproduções',
  'last': 'Última reprodução',
  'added': 'Inclusão',
};
String catalogTime(Duration v) => v <= Duration.zero
    ? 'Não informada'
    : '${v.inMinutes}:${(v.inSeconds % 60).toString().padLeft(2, '0')}';
String catalogDate(DateTime? v) => v == null
    ? 'Não informada'
    : '${v.toLocal().day.toString().padLeft(2, '0')}/${v.toLocal().month.toString().padLeft(2, '0')}/${v.toLocal().year}';

class CatalogBrowser extends StatefulWidget {
  const CatalogBrowser({
    super.key,
    required this.tracks,
    required this.favorites,
    required this.store,
    required this.settings,
    required this.downloads,
    required this.query,
    required this.onPlay,
    this.onPlayNamed,
    this.onArtistSelection,
    required this.onAction,
    required this.trackActions,
    required this.onAddSource,
    required this.onPlaylist,
    this.initialCategory = 'songs',
    this.pageTitle,
    this.memory,
    this.home = false,
    this.loading = false,
    this.revision = 0,
    this.onResume,
    this.onNowPlaying,
    this.resumeTitle,
    this.resumeTrack,
  });
  final Future<void> Function(List<Track>, int, String)? onPlayNamed;
  final Future<void> Function(String, bool, List<Track>, String)?
  onArtistSelection;
  final List<Track> tracks;
  final Set<String> favorites;
  final LibraryStore store;
  final AppSettings settings;
  final DownloadManager downloads;
  final int revision;
  final VoidCallback? onResume;
  final VoidCallback? onNowPlaying;
  final String? resumeTitle;
  final Track? resumeTrack;
  final String query, initialCategory;
  final String? pageTitle;
  final CatalogMemory? memory;
  final bool home, loading;
  final Future<void> Function(List<Track>, int) onPlay;
  final Future<void> Function(String, List<Track>) onAction;
  final Widget Function(Track) trackActions;
  final VoidCallback onAddSource;
  final void Function(int) onPlaylist;
  @override
  State<CatalogBrowser> createState() => CatalogBrowserState();
}

class CatalogBrowserState extends State<CatalogBrowser> {
  late final memory = widget.memory ?? CatalogMemory();
  late bool mergeArtists, mergeAlbums;
  late String category;
  late CatalogFilters filters;
  late TextEditingController quickInput;
  String quick = '', sort = 'title', artistTab = 'albums';
  String albumSort = 'track';
  String get activeSort =>
      selectedGroup != null && category == 'albums' ? albumSort : sort;
  bool descending = false, refreshing = true;
  bool showSelection = false;
  bool controlsExpanded = false;
  bool refreshingData = false, refreshAgain = false;
  CatalogIndex? cachedIndex;
  String? filteredSignature;
  List<Track> cachedFiltered = [];
  String? groupsSignature;
  List<CatalogGroup> cachedGroups = [];
  String? pendingCatalogSignature;
  int catalogWorkGeneration = 0;
  bool derivingCatalog = false;
  Future<CatalogResult>? activeCatalogWork;
  String? error, anchor;
  String favoriteTab = 'all';
  String favoriteDataKey = '';
  FavoriteCatalog favoriteData = (tracks: [], artists: [], albums: []);
  bool preparingFavorites = false;
  int favoriteGeneration = 0;
  void prepareFavorites(List<Track> all) {
    final signature = '${identityHashCode(all)}:${identityHashCode(index)}';
    if (favoriteDataKey == signature) return;
    favoriteDataKey = signature;
    final request = ++favoriteGeneration;
    final work = (index: index, tracks: all);
    if (all.length <= 1000) {
      favoriteData = prepareFavoriteCatalog(work);
      preparingFavorites = false;
      return;
    }
    preparingFavorites = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final result = await compute(prepareFavoriteCatalog, work);
        if (mounted && request == favoriteGeneration) {
          setState(() {
            favoriteData = result;
            preparingFavorites = false;
          });
        }
      } catch (_) {
        if (mounted && request == favoriteGeneration) {
          setState(() {
            preparingFavorites = false;
            error =
                'Não foi possível preparar esta visualização. Tente novamente.';
          });
        }
      }
    });
  }

  bool get favoritesPage => widget.initialCategory == 'favorites';
  void setQuickFavorites(bool value) {
    setState(() {
      filters.favorites = value;
      selectedIds.clear();
    });
    saveFilters();
  }

  bool get quickFavorites => filters.favorites;
  CatalogGroup? selectedGroup;
  final groupHistory = <(String, CatalogGroup?, String)>[];
  Set<String> offline = {}, selectedIds = {};
  Map<String, Map<String, Object?>> stats = {};
  Map<String, List<Map<String, Object?>>> sources = {};
  List<Map<String, Object?>> playlists = [];
  int generation = 0;
  List<Track> pageTracks = [];
  int pageOffset = 0, pageTotal = 0, pageRequest = 0, dataRevision = 0;
  int loadedOffset = 0;
  bool pageLoading = true;
  bool pageHasData = false;
  String pageSignature = '';
  String pageCriteria = '';
  String? pageError;
  int get pageSize {
    final value = int.tryParse(
      widget.settings.visualChoice('catalog_page_size', '100'),
    );
    return [50, 100, 200].contains(value) ? value! : 100;
  }

  CatalogSqlQuery get sqlQuery {
    final effective = CatalogFilters.fromJson(filters.toJson());
    if (widget.settings.visualBool('offline_only', fallback: false)) {
      effective.offline = true;
    }
    if (category == 'favorites') effective.favorites = true;
    if (category == 'offline') effective.offline = true;
    return CatalogSqlQuery(
      filters: effective,
      text: widget.query,
      sort: activeSort,
      descending: descending,
      offline: offline,
      collectionFavorites: widget.settings.collectionFavorites,
    );
  }

  Future<void> loadPage() async {
    final request = ++pageRequest;
    if (mounted) {
      setState(() {
        pageLoading = true;
        pageError = null;
      });
    }
    try {
      var result = await widget.store.catalogPage(
        sqlQuery,
        offset: pageOffset,
        limit: pageSize,
        includeCovers: false,
      );
      if (!mounted || request != pageRequest) return;
      if (result.total > 0 && pageOffset >= result.total) {
        pageOffset = ((result.total - 1) ~/ pageSize) * pageSize;
        result = await widget.store.catalogPage(
          sqlQuery,
          offset: pageOffset,
          limit: pageSize,
          includeCovers: false,
        );
      }
      if (!mounted || request != pageRequest) return;
      setState(() {
        pageTracks = result.tracks;
        pageTotal = result.total;
        pageLoading = false;
        pageHasData = true;
        loadedOffset = pageOffset;
        memory.save(
          pageCriteria,
          CatalogPageSnapshot(List.of(result.tracks), result.total, pageOffset),
        );
      });
    } catch (_) {
      if (mounted && request == pageRequest) {
        setState(() {
          pageLoading = false;
          if (pageHasData) pageOffset = loadedOffset;
          pageError = 'Não foi possível carregar esta página. Tente novamente.';
        });
      }
    }
  }

  void ensurePage() {
    final criteria = jsonEncode([
      category,
      widget.query,
      filters.toJson(),
      activeSort,
      descending,
      pageSize,
      widget.settings.visualBool('offline_only', fallback: false),
      widget.settings.collectionFavorites.toList(),
    ]);
    final signature = '$criteria:$dataRevision:${widget.revision}';
    if (signature == pageSignature) return;
    pageSignature = signature;
    if (criteria != pageCriteria) {
      final saved = memory.pages[criteria];
      pageOffset = saved?.offset ?? 0;
      loadedOffset = pageOffset;
      pageHasData = saved != null || pageHasData;
      final visible = saved == null
          ? const <String>{}
          : widget.tracks.map((track) => track.id).toSet();
      if (saved != null) {
        pageTracks = saved.tracks
            .where(
              (track) =>
                  visible.contains(track.id) &&
                  (category != 'favorites' ||
                      widget.favorites.contains(track.id)),
            )
            .toList();
      }
      pageTotal = saved?.total ?? pageTotal;
      selectedIds.clear();
      anchor = null;
    } else {
      selectedIds.retainAll(widget.tracks.map((t) => t.id));
    }
    pageCriteria = criteria;
    pageRequest++;
    pageLoading = true;
    Future.microtask(() {
      if (mounted) loadPage();
    });
  }

  Future<void> selectPaged(Track track, {bool checkbox = false}) async {
    final needsAll =
        HardwareKeyboard.instance.isShiftPressed ||
        (!checkbox &&
            !HardwareKeyboard.instance.isControlPressed &&
            selectedIds.isEmpty);
    final signature = pageSignature;
    final values = needsAll
        ? await widget.store.catalogResult(sqlQuery)
        : pageTracks;
    if (!mounted || signature != pageSignature) return;
    select(track, values, checkbox: checkbox);
  }

  Future<void> selectAllPaged() async {
    final signature = pageSignature;
    final values = await widget.store.catalogResult(sqlQuery);
    if (mounted && signature == pageSignature) {
      setState(() => selectedIds = values.map((t) => t.id).toSet());
    }
  }

  Widget paginatedTracks() {
    ensurePage();
    return Column(
      children: [
        if (pageLoading) const LinearProgressIndicator(),
        if (pageError != null)
          TextButton(onPressed: loadPage, child: UiText(pageError!)),
        Expanded(
          child: pageLoading && !pageHasData
              ? const Center(child: CircularProgressIndicator())
              : IgnorePointer(
                  ignoring: pageLoading,
                  child: trackList(pageTracks, paged: true),
                ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                pageTracks.isEmpty
                    ? (pageLoading ? 'Carregando músicas…' : '0 músicas')
                    : '${loadedOffset + 1}–${loadedOffset + pageTracks.length} de $pageTotal',
              ),
              IconButton(
                tooltip: ui(context, 'Página anterior'),
                onPressed:
                    (pageLoading &&
                            (!pageHasData || pageOffset != loadedOffset)) ||
                        pageOffset == 0
                    ? null
                    : () {
                        pageOffset = (pageOffset - pageSize).clamp(
                          0,
                          pageTotal,
                        );
                        loadPage();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: ui(context, 'Próxima página'),
                onPressed:
                    (pageLoading &&
                            (!pageHasData || pageOffset != loadedOffset)) ||
                        pageOffset + pageSize >= pageTotal
                    ? null
                    : () {
                        pageOffset += pageSize;
                        loadPage();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
              const UiText('Por página: '),
              DropdownButton<int>(
                value: pageSize,
                items: [50, 100, 200]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (n) async {
                  if (n != null) {
                    await widget.settings.updateVisual(
                      'catalog_page_size',
                      '$n',
                    );
                    if (mounted) setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Timer? refreshTimer, inputTimer;
  @override
  void initState() {
    super.initState();
    mergeArtists = widget.settings.visualBool('merge_artists', fallback: true);
    mergeAlbums = widget.settings.visualBool('merge_albums', fallback: true);
    if (memory.ready) {
      stats = memory.stats;
      sources = memory.sources;
      playlists = memory.playlists;
      offline = memory.offline;
      dataRevision = memory.revision;
      refreshing = false;
    }
    category = widget.home
        ? 'songs'
        : widget.initialCategory == 'songs'
        ? 'songs'
        : widget.initialCategory;
    if (!catalogCategories.containsKey(category)) category = 'songs';
    try {
      filters = CatalogFilters.fromJson(
        jsonDecode(
          widget.settings.visualChoice('catalog_filters_$category', '{}'),
        ) as Map<String, dynamic>,
      );
    } catch (_) {
      filters = CatalogFilters();
    }
    quick = widget.settings.visualChoice('quick_$category', '');
    quickInput = TextEditingController(text: quick);
    sort = !widget.home && widget.initialCategory == 'songs'
        ? 'title'
        : widget.settings.visualChoice('songs_sort', 'title');
    descending = !widget.home && widget.initialCategory == 'songs'
        ? false
        : widget.settings.visualBool('songs_descending', fallback: false);
    if (favoritesPage) {
      pageLoading = false;
      pageHasData = true;
    }
    widget.downloads.addListener(scheduleAvailability);
    widget.downloads.cache?.addListener(scheduleAvailability);
    if (!memory.ready ||
        memory.dirty ||
        memory.catalogRevision != widget.revision) {
      refresh();
    }
  }

  @override
  void didUpdateWidget(covariant CatalogBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory ||
        oldWidget.home != widget.home) {
      category = widget.home ? 'songs' : widget.initialCategory;
      selectedGroup = null;
      groupHistory.clear();
      selectedIds.clear();
      controlsExpanded = false;
      try {
        filters = CatalogFilters.fromJson(
          jsonDecode(
            widget.settings.visualChoice('catalog_filters_$category', '{}'),
          ) as Map<String, dynamic>,
        );
      } catch (_) {
        filters = CatalogFilters();
      }
    }
    if (!listEquals(oldWidget.tracks, widget.tracks) ||
        !setEquals(oldWidget.favorites, widget.favorites) ||
        oldWidget.revision != widget.revision ||
        mergeArtists !=
            widget.settings.visualBool('merge_artists', fallback: true) ||
        mergeAlbums !=
            widget.settings.visualBool('merge_albums', fallback: true)) {
      if (!setEquals(oldWidget.favorites, widget.favorites)) {
        dataRevision = ++memory.revision;
      }
      if (category == 'favorites') {
        pageTracks = pageTracks
            .where((track) => widget.favorites.contains(track.id))
            .toList();
      }
      mergeArtists = widget.settings.visualBool(
        'merge_artists',
        fallback: true,
      );
      mergeAlbums = widget.settings.visualBool('merge_albums', fallback: true);
      cachedIndex = null;
      scheduleRefresh();
    }
  }

  @override
  void dispose() {
    catalogWorkGeneration++;
    generation++;
    refreshTimer?.cancel();
    inputTimer?.cancel();
    quickInput.dispose();
    widget.downloads.removeListener(scheduleAvailability);
    widget.downloads.cache?.removeListener(scheduleAvailability);
    super.dispose();
  }

  void scheduleAvailability() {
    refreshTimer?.cancel();
    refreshTimer = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      if (widget.downloads.running || widget.downloads.cache?.current != null) {
        scheduleAvailability();
        return;
      }
      refresh();
    });
  }

  void scheduleRefresh() {
    refreshTimer?.cancel();
    refreshTimer = Timer(const Duration(milliseconds: 250), refresh);
  }

  Future<void> refresh() async {
    if (refreshingData) {
      refreshAgain = true;
      generation++;
      return;
    }
    refreshingData = true;
    if (mounted) setState(() => refreshing = true);
    final request = ++generation;
    try {
      final results = await Future.wait([
        widget.store.listeningStats(),
        widget.store.sourceMemberships(),
        widget.store.playlists(),
        widget.store.downloadTasks(includeCovers: false),
      ]);
      final candidates = <Map<String, Object?>>[
        for (final t in widget.tracks)
          if (t.localPath != null) {'id': t.id, 'path': t.localPath},
      ];
      for (final row in results[3] as List<Map<String, Object?>>) {
        if (row['status'] == 'complete' &&
            row['download_path'] is String &&
            (row['received'] as int) > 0) {
          candidates.add({
            'id': row['id'],
            'path': row['download_path'],
            'bytes': row['received'],
          });
        }
      }
      for (final row
          in await widget.downloads.cache?.rows(validOnly: true) ??
              <Map<String, Object?>>[]) {
        candidates.add({
          'id': row['track_id'],
          'path': row['path'],
          'bytes': row['bytes'],
        });
      }
      final available = await compute(validOfflineFiles, candidates);
      if (!mounted || request != generation) return;
      final nextStats = results[0] as Map<String, Map<String, Object?>>;
      final nextSources = results[1] as Map<String, List<Map<String, Object?>>>;
      final nextPlaylists = results[2] as List<Map<String, Object?>>;
      final changed =
          !memory.ready ||
          memory.catalogRevision != widget.revision ||
          !sameCatalogData(stats, nextStats) ||
          !sameCatalogData(sources, nextSources) ||
          !setEquals(offline, available);
      setState(() {
        if (changed) {
          stats = nextStats;
          sources = nextSources;
          offline = available;
          cachedIndex = null;
          memory.index = null;
          memory.derived.clear();
          memory.home.clear();
          dataRevision = ++memory.revision;
        }
        playlists = nextPlaylists;
        refreshing = false;
        memory
          ..ready = true
          ..dirty = false
          ..catalogRevision = widget.revision
          ..stats = stats
          ..sources = sources
          ..playlists = playlists
          ..offline = offline;
        error = null;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(() {
          refreshing = false;
          error = 'Não foi possível atualizar a biblioteca. Tente novamente.';
        });
      }
    } finally {
      refreshingData = false;
      if (refreshAgain && mounted) {
        refreshAgain = false;
        scheduleRefresh();
      }
    }
  }

  CatalogIndex get index {
    final favorites = widget.settings.collectionFavorites;
    cachedIndex ??= memory.indexRevision == widget.revision
        ? memory.index
        : null;
    if (cachedIndex != null &&
        listEquals(cachedIndex!.tracks, widget.tracks) &&
        setEquals(cachedIndex!.collectionFavorites, favorites) &&
        setEquals(cachedIndex!.favorites, widget.favorites) &&
        cachedIndex!.mergeArtists == mergeArtists &&
        cachedIndex!.mergeAlbums == mergeAlbums) {
      return cachedIndex!;
    }
    memory.derived.clear();
    memory.home.clear();
    memory.indexRevision = widget.revision;
    return memory.index = cachedIndex = CatalogIndex(
      tracks: widget.tracks,
      favorites: widget.favorites,
      offline: offline,
      stats: stats,
      sources: sources,
      collectionFavorites: favorites,
      mergeArtists: widget.settings.visualBool('merge_artists', fallback: true),
      mergeAlbums: widget.settings.visualBool('merge_albums', fallback: true),
    );
  }

  String get viewCategory =>
      selectedGroup != null &&
          artistTab == 'albums' &&
          {'artists', 'albumArtists'}.contains(category)
      ? 'albums'
      : category;
  String get view => widget.settings.visualChoice(
    '${viewCategory}_view',
    widget.settings.visualChoice('songs_view', 'compact'),
  );
  bool get dense =>
      widget.settings.visualBool('catalog_dense', fallback: false);
  List<String> get columns =>
      (widget.settings.preferences.getStringList('visual.songs_columns') ??
              ['artist', 'album', 'duration', 'source', 'offline'])
          .where(catalogColumns.containsKey)
          .toList();
  Future<void> saveFilters() => widget.settings.updateVisual(
    'catalog_filters_$category',
    jsonEncode(filters.toJson()),
  );
  int homeReset = 0;
  void resetRoot(String value) {
    chooseCategory(value);
    setState(() {
      groupHistory.clear();
      homeReset++;
      if (value == 'songs') {
        sort = 'title';
        descending = false;
      }
    });
  }

  void chooseCategory(String value) {
    setState(() {
      category = value;
      try {
        filters = CatalogFilters.fromJson(
          jsonDecode(
            widget.settings.visualChoice('catalog_filters_$value', '{}'),
          ) as Map<String, dynamic>,
        );
      } catch (_) {
        filters = CatalogFilters();
      }
      selectedGroup = null;
      selectedIds.clear();
      anchor = null;
      quick = widget.settings.visualChoice('quick_$value', '');
      quickInput.text = quick;
    });
    widget.settings.updateVisual('library_category', value);
  }

  List<Track> filtered() {
    final offlineOnly = widget.settings.visualBool(
      'offline_only',
      fallback: false,
    );
    final signature =
        '${identityHashCode(index)}|${widget.revision}|$dataRevision|${widget.query}|$category|$activeSort|$descending|$offlineOnly|${jsonEncode(filters.toJson())}';
    if (signature == filteredSignature) return cachedFiltered;
    final saved = memory.derived[signature];
    if (saved != null) {
      catalogWorkGeneration++;
      pendingCatalogSignature = null;
      derivingCatalog = false;
      filteredSignature = signature;
      cachedFiltered = saved.tracks;
      cachedGroups = saved.groups
          .where(
            (g) =>
                !filters.favorites ||
                !{'albums', 'artists', 'albumArtists'}.contains(category) ||
                favoriteCollection(collectionKey(g, category)!, g.tracks),
          )
          .toList();
      groupsSignature = '$category|${identityHashCode(cachedFiltered)}';
      return cachedFiltered;
    }
    final effective = CatalogFilters.fromJson(filters.toJson());
    if (offlineOnly) {
      effective.offline = true;
    }
    if (category == 'favorites') effective.favorites = !favoritesPage;
    if (category == 'offline') effective.offline = true;
    if ({'albums', 'artists', 'albumArtists'}.contains(category)) {
      effective.favorites = false;
    }
    if (widget.tracks.length > 1000) {
      if (pendingCatalogSignature != signature) {
        pendingCatalogSignature = signature;
        derivingCatalog = true;
        final request = ++catalogWorkGeneration;
        final work = (
          index: index,
          filters: effective,
          text: widget.query,
          sort: activeSort,
          descending: descending,
          category: category,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || request != catalogWorkGeneration) return;
          Future<CatalogResult>? job;
          try {
            await Future<void>.delayed(const Duration(milliseconds: 180));
            if (!mounted || request != catalogWorkGeneration) return;
            final active = activeCatalogWork;
            if (active != null) {
              try {
                await active;
              } catch (_) {}
            }
            if (!mounted || request != catalogWorkGeneration) return;
            job = compute(prepareCatalog, work);
            activeCatalogWork = job;
            final result = await job;
            if (!mounted || request != catalogWorkGeneration) return;
            setState(() {
              memory.derived[signature] = result;
              while (memory.derived.length > 8) {
                memory.derived.remove(memory.derived.keys.first);
              }
              filteredSignature = signature;
              cachedFiltered = result.tracks;
              groupsSignature =
                  '${work.category}|${identityHashCode(cachedFiltered)}';
              cachedGroups = result.groups
                  .where(
                    (g) =>
                        !filters.favorites ||
                        !{
                          'albums',
                          'artists',
                          'albumArtists',
                        }.contains(category) ||
                        favoriteCollection(
                          collectionKey(g, category)!,
                          g.tracks,
                        ),
                  )
                  .toList();
              derivingCatalog = false;
              pendingCatalogSignature = null;
            });
          } catch (_) {
            if (mounted && request == catalogWorkGeneration) {
              setState(() {
                error = 'Não foi possível preparar esta visualização. Tente novamente.';
                derivingCatalog = false;
                filteredSignature = signature;
                // Preserve the last successful view after a failed refresh.
                pendingCatalogSignature = null;
              });
            }
          } finally {
            if (identical(activeCatalogWork, job)) activeCatalogWork = null;
          }
        });
      }
      return cachedFiltered;
    }
    filteredSignature = signature;
    return cachedFiltered = index.query(
      effective,
      text: widget.query,
      quick: '',
      sort: activeSort,
      descending: descending,
    );
  }

  List<CatalogGroup> catalogGroups(List<Track> values) {
    if (derivingCatalog) return cachedGroups;
    final signature = '$category|${identityHashCode(values)}';
    if (signature != groupsSignature) {
      groupsSignature = signature;
      cachedGroups = index.sortGroups(
        index
            .groups(category, values)
            .where(
              (g) =>
                  !filters.favorites ||
                  !{'albums', 'artists', 'albumArtists'}.contains(category) ||
                  favoriteCollection(collectionKey(g, category)!, g.tracks),
            )
            .toList(),
        sort,
        descending,
      );
    }
    return cachedGroups;
  }

  void select(Track track, List<Track> visible, {bool checkbox = false}) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final control = HardwareKeyboard.instance.isControlPressed;
    if (shift && anchor != null) {
      final start = visible.indexWhere((t) => t.id == anchor),
          end = visible.indexWhere((t) => t.id == track.id);
      if (start >= 0 && end >= 0) {
        setState(
          () => selectedIds.addAll(
            visible
                .sublist(
                  start < end ? start : end,
                  (start > end ? start : end) + 1,
                )
                .map((t) => t.id),
          ),
        );
      }
    } else if (checkbox || control || selectedIds.isNotEmpty) {
      setState(() {
        if (!selectedIds.remove(track.id)) selectedIds.add(track.id);
        anchor = track.id;
      });
    } else {
      widget.onPlay(visible, visible.indexWhere((t) => t.id == track.id));
    }
  }

  Future<void> batch(String action, List<Track> values) async {
    await widget.onAction(action, List.of(values));
    if ({
      'favorite',
      'unfavorite',
      'playlist',
      'save',
      'edit',
      'merge',
    }.contains(action)) {
      await refresh();
    }
  }

  Iterable<String> collectionAliases(String collection, List<Track> values) =>
      collection.startsWith('album:') && values.isNotEmpty
      ? [
          'album:${legacyAlbumKey(values.first)}',
          if (values.first.albumId.isNotEmpty)
            'album:id:${values.first.albumId}',
        ]
      : collection.startsWith('artist:')
      ? widget.settings.collectionFavorites.where(
          (key) =>
              key.startsWith('artist:') &&
              artistNameKey(key.substring(7)) ==
                  artistNameKey(collection.substring(7)),
        )
      : const [];

  bool favoriteCollection(String collection, List<Track> values) =>
      widget.settings.collectionFavorites.contains(collection) ||
      collectionAliases(
        collection,
        values,
      ).any(widget.settings.collectionFavorites.contains);

  Widget actions(
    List<Track> values, {
    String? collection,
  }) => PopupMenuButton<String>(
    tooltip: ui(context, 'Ações da coleção'),
    onSelected: (action) async {
      if ((action == 'artist_mix' || action == 'artist_radio') &&
          collection != null) {
        await widget.onArtistSelection?.call(
          collection.substring(7),
          action == 'artist_radio',
          filtered(),
          'preview',
        );
      } else if (action == 'collection' && collection != null) {
        await widget.settings.favoriteCollection(
          collection,
          aliases: collectionAliases(collection, values),
        );
      } else {
        await batch(action, values);
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'play', child: UiText('Reproduzir')),
      if (collection?.startsWith('artist:') == true &&
          widget.onArtistSelection != null) ...[
        const PopupMenuItem(value: 'artist_mix', child: UiText('Artist mix')),
        const PopupMenuItem(
          value: 'artist_radio',
          child: UiText('Artist radio'),
        ),
      ],
      if (collection?.startsWith('artist:') != true)
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
      const PopupMenuItem(value: 'favorite', child: UiText('Favoritar faixas')),
      const PopupMenuItem(
        value: 'unfavorite',
        child: UiText('Remover favoritos das faixas'),
      ),
      if (collection != null)
        PopupMenuItem(
          value: 'collection',
          child: UiText(
            favoriteCollection(collection, values)
                ? 'Remover favorito da coleção'
                : 'Favoritar coleção',
          ),
        ),
      const PopupMenuItem(
        value: 'playlist',
        child: UiText('Adicionar à playlist'),
      ),
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
  String cell(Track t, String column) => switch (column) {
    'artist' => t.artistNames.join('; '),
    'album' => t.album.isEmpty ? 'Sem álbum' : t.album,
    'duration' => catalogTime(t.duration),
    'track' => '${t.trackNumber ?? '—'} / ${t.discNumber ?? '—'}',
    'year' => t.year?.toString() ?? 'Não informado',
    'genre' => t.genreNames.isEmpty ? 'Não informado' : t.genreNames.join('; '),
    'format' => trackFormat(t).isEmpty ? 'Não informado' : trackFormat(t),
    'source' =>
      '${t.provider == 'local' ? 'Local' : t.provider} · ${t.account}',
    'offline' => offline.contains(t.id) ? 'Disponível' : 'Indisponível',
    'favorite' => index.isFavorite(t) ? 'Sim' : 'Não',
    'plays' => index.plays(t).toString(),
    'last' => catalogDate(index.lastPlayed(t)),
    'added' => catalogDate(t.addedAt),
    _ => '',
  };
  Widget trackDetails(List<Track> values, {bool paged = false}) =>
      MediaDetailsTable(
        headers: [
          if (category == 'albums') '#',
          ui(context, 'Título'),
          ...columns.map((c) => ui(context, catalogColumns[c] ?? c)),
          '',
        ],
        widths: [
          if (category == 'albums') 64,
          340,
          ...columns.map((_) => 175.0),
          72,
        ],
        itemCount: values.length,
        rowBuilder: (i) {
          final t = values[i];
          return [
            if (category == 'albums')
              Text(t.trackNumber?.toString() ?? (i + 1).toString()),
            InkWell(
              onTap: () => paged ? selectPaged(t) : select(t, values),
              child: Row(
                children: [
                  if (showSelection || selectedIds.isNotEmpty)
                    Checkbox(
                      value: selectedIds.contains(t.id),
                      onChanged: (_) => paged
                          ? selectPaged(t, checkbox: true)
                          : select(t, values, checkbox: true),
                    ),
                  SizedBox.square(dimension: 32, child: TrackCover(track: t)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t.title)),
                ],
              ),
            ),
            ...columns.map(
              (c) => Text(
                {'duration', 'offline', 'favorite'}.contains(c) ||
                        {'Sem álbum', 'Não informado'}.contains(cell(t, c))
                    ? ui(context, cell(t, c))
                    : cell(t, c),
              ),
            ),
            widget.trackActions(t),
          ];
        },
      );
  Widget trackList(List<Track> values, {bool paged = false}) {
    if (values.isEmpty) return empty();
    if (view == 'compact_card') {
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320 * MediaCardSizeScope.scale(context),
          mainAxisExtent:
              100 *
              MediaQuery.textScalerOf(context).scale(1) *
              MediaCardSizeScope.scale(context).clamp(1, 1.7),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: values.length,
        itemBuilder: (_, i) => compactTrack(values, i, paged: paged),
      );
    }
    final selection = (paged ? widget.tracks : values)
        .where((t) => selectedIds.contains(t.id))
        .toList();
    Widget check(Track t) => !showSelection && selectedIds.isEmpty
        ? const SizedBox.shrink()
        : Checkbox(
            value: selectedIds.contains(t.id),
            onChanged: (_) => paged
                ? selectPaged(t, checkbox: true)
                : select(t, values, checkbox: true),
          );
    final rows = view == 'detailed'
        ? trackDetails(values, paged: paged)
        : ListView.builder(
            itemCount: values.length,
            itemBuilder: (context, i) {
              final t = values[i];
              return ItemActionRegion(
                child: ListTile(
                  dense: dense,
                  selected: selectedIds.contains(t.id),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      check(t),
                      SizedBox.square(
                        dimension: dense ? 32 : 44,
                        child: TrackCover(track: t),
                      ),
                    ],
                  ),
                  title: Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${t.artistNames.join('; ')}${t.album.isEmpty ? '' : ' · ${t.album}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: widget.trackActions(t),
                  onTap: () => paged ? selectPaged(t) : select(t, values),
                ),
              );
            },
          );
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                IconButton(
                  tooltip: ui(context, 'Selecionar faixas'),
                  isSelected: showSelection,
                  onPressed: () =>
                      setState(() => showSelection = !showSelection),
                  icon: const Icon(Icons.checklist),
                ),
                Text(
                  uiFormat(
                    context,
                    '${paged ? pageTotal : values.length} músicas · ${selection.length} selecionadas',
                    '${paged ? pageTotal : values.length} tracks · ${selection.length} selected',
                  ),
                ),
                TextButton(
                  onPressed: paged
                      ? selectAllPaged
                      : () => setState(
                          () => selectedIds = values.map((t) => t.id).toSet(),
                        ),
                  child: const UiText('Selecionar todas'),
                ),
                if (selection.isNotEmpty) ...[
                  TextButton(
                    onPressed: () => setState(selectedIds.clear),
                    child: const UiText('Limpar seleção'),
                  ),
                  actions(selection),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(paged ? '$pageSignature:$pageOffset' : 'collection'),
            child: rows,
          ),
        ),
      ],
    );
  }

  void openTrackCollection(Track track, bool album) {
    chooseCategory(album ? 'albums' : 'artists');
    final groups = index.groups(category, widget.tracks);
    final group = groups
        .where(
          (g) => album
              ? g.tracks.any((t) => albumKey(t) == albumKey(track))
              : g.tracks.any(
                  (t) => t.artistNames.any(track.artistNames.contains),
                ),
        )
        .firstOrNull;
    if (group != null) setState(() => selectedGroup = group);
  }

  Widget empty() => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.library_music, size: 48),
          const SizedBox(height: 16),
          Text(
            widget.tracks.isEmpty
                ? 'Adicione uma fonte para começar sua biblioteca.'
                : 'Nenhum resultado. Ajuste a busca e os filtros.',
            textAlign: TextAlign.center,
          ),
          if (widget.tracks.isEmpty)
            TextButton(
              onPressed: widget.onAddSource,
              child: const UiText('Adicionar fonte'),
            ),
        ],
      ),
    ),
  );
  void openGroup(CatalogGroup g, {String? type}) => setState(() {
    if (selectedGroup != null) {
      groupHistory.add((category, selectedGroup, artistTab));
    }
    if (type != null) category = type;
    selectedGroup = g;
    selectedIds.clear();
    artistTab = 'albums';
  });
  Widget groupImage(CatalogGroup g, String type) =>
      {'artists', 'albumArtists'}.contains(type)
      ? ArtistPortrait(
          artist: g.name,
          enabled: widget.settings.visualBool('artist_photos'),
          fallbackTrack: g.tracks.where((t) => t.hasArtwork).firstOrNull,
          cachedOnly: widget.settings.visualBool(
            'offline_only',
            fallback: false,
          ),
        )
      : type == 'albums'
      ? TrackCover(
          album: true,
          track:
              g.tracks.where((t) => t.hasArtwork).firstOrNull ?? g.tracks.first,
        )
      : Icon(switch (type) {
          'genres' => Icons.piano,
          'years' || 'decades' => Icons.calendar_month,
          _ => Icons.folder,
        }, size: 44);
  String? collectionKey(CatalogGroup g, String type) => type == 'albums'
      ? 'album:${g.id}'
      : {'artists', 'albumArtists'}.contains(type)
      ? 'artist:${g.name}'
      : null;
  Widget groupActions(CatalogGroup group, String type) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (type == 'albums')
        IconButton(
          tooltip: ui(context, 'Reproduzir'),
          onPressed: () => batch('play', ordered(group.tracks)),
          icon: const Icon(Icons.play_arrow),
        ),
      actions(group.tracks, collection: collectionKey(group, type)),
    ],
  );
  Widget compactGroup(CatalogGroup group, String type) => CompactMediaCard(
    key: ValueKey('collection.${group.id}'),
    artwork: groupImage(group, type),
    title: group.name,
    subtitle: '${group.tracks.length} ${ui(context, 'faixas')}',
    actions: groupActions(group, type),
    onTap: () => openGroup(group, type: type),
  );
  Widget groupDetails(List<CatalogGroup> values, String type) =>
      MediaDetailsTable(
        headers: [
          ui(context, 'Título'),
          ui(context, 'Artista'),
          ui(context, 'Músicas'),
          ui(context, 'Duração'),
          '',
        ],
        widths: const [300, 220, 110, 130, 128],
        itemCount: values.length,
        rowBuilder: (i) {
          final g = values[i];
          return [
            InkWell(
              onTap: () => openGroup(g, type: type),
              child: Row(
                children: [
                  SizedBox.square(dimension: 32, child: groupImage(g, type)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(g.name)),
                ],
              ),
            ),
            Text(g.tracks.first.albumArtistNames.join('; ')),
            Text(g.tracks.length.toString()),
            Text(
              catalogTime(
                g.tracks.fold(Duration.zero, (sum, t) => sum + t.duration),
              ),
            ),
            groupActions(g, type),
          ];
        },
      );
  Widget groups(List<CatalogGroup> values, String type) {
    if (values.isEmpty) return empty();
    final smallCards =
        widget.settings.visualChoice('${type}_view', '') == 'compact_card';
    if (!smallCards &&
        !widget.settings.visualBool('${type}_grid') &&
        view == 'detailed') {
      return groupDetails(values, type);
    }
    if (smallCards) {
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 360 * MediaCardSizeScope.scale(context),
          mainAxisExtent:
              100 *
              MediaQuery.textScalerOf(context).scale(1) *
              MediaCardSizeScope.scale(context).clamp(1, 1.7),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: values.length,
        itemBuilder: (_, i) => compactGroup(values[i], type),
      );
    }
    final grid = widget.settings.visualBool('${type}_grid');
    final size = smallCards
        ? 120.0
        : widget.settings.visualNumber('catalog_cover_size', 180) *
              MediaCardSizeScope.scale(context).toDouble();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (!grid) {
      return ListView.builder(
        itemCount: values.length,
        itemBuilder: (context, i) {
          final g = values[i];
          return ItemActionRegion(
            child: ListTile(
              dense: dense,
              leading: SizedBox.square(
                dimension: view == 'detailed' ? 64 : 40,
                child: groupImage(g, type),
              ),
              title: Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                view == 'detailed'
                    ? '${g.tracks.length} ${ui(context, 'Músicas')} · ${index.groups('albums', g.tracks).length} ${ui(context, 'Álbuns')} · ${catalogTime(g.tracks.fold(Duration.zero, (sum, t) => sum + t.duration))}'
                    : '${g.tracks.length} ${ui(context, 'Músicas')}',
              ),
              trailing: actions(g.tracks, collection: collectionKey(g, type)),
              onTap: () => openGroup(g, type: type),
            ),
          );
        },
      );
    }
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: size + 50,
        mainAxisExtent: size + 90 * scale,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: values.length,
      itemBuilder: (context, i) {
        final g = values[i];
        return ItemActionRegion(
          child: InkWell(
            onTap: () => openGroup(g, type: type),
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: groupImage(g, type)),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: actions(
                          g.tracks,
                          collection: collectionKey(g, type),
                        ),
                      ),
                      if (g.tracks.every((t) => offline.contains(t.id)))
                        const Positioned(
                          right: 8,
                          bottom: 8,
                          child: Icon(
                            Icons.offline_pin,
                            color: Color(0xff54cf9b),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  g.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  type == 'albums'
                      ? g.tracks.first.albumArtistNames.join('; ')
                      : '${g.tracks.length} ${ui(context, 'músicas')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Track> ordered(List<Track> values) => List.of(values)
    ..sort((a, b) {
      final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1),
          track = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      return disc != 0
          ? disc
          : track != 0
          ? track
          : searchKey(a.title).compareTo(searchKey(b.title));
    });
  void openArtist(String name) {
    final values = widget.tracks
        .where(
          (t) => [
            ...t.artistNames,
            ...t.albumArtistNames,
          ].any((a) => searchKey(a) == searchKey(name)),
        )
        .toList();
    if (values.isEmpty) return;
    openGroup(CatalogGroup(name, name, values), type: 'albumArtists');
  }

  Widget detailToolbar(bool artist) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            spacing: 24,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  if (artist) ...[
                    for (final item in {
                      'albums': 'Discography',
                      'tracks': 'Tracks',
                    }.entries)
                      ChoiceChip(
                        label: UiText(item.value),
                        selected: artistTab == item.key,
                        onSelected: (_) => setState(() => artistTab = item.key),
                      ),
                  ] else ...[
                    Text(
                      [
                        selectedGroup!.tracks.length,
                        ui(context, 'Músicas'),
                      ].join(' '),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => showSelection = !showSelection),
                      icon: const Icon(Icons.checklist),
                      label: const UiText('Select'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        showSelection = true;
                        selectedIds = selectedGroup!.tracks
                            .map((t) => t.id)
                            .toSet();
                      }),
                      child: const UiText('Select all'),
                    ),
                  ],
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  if (artist)
                    for (final entry in {
                      'all': 'All',
                      'favorites': 'Favorites',
                    }.entries)
                      ChoiceChip(
                        label: UiText(entry.value),
                        selected:
                            quick == entry.key ||
                            (quick.isEmpty && entry.key == 'all'),
                        onSelected: (_) => setState(() {
                          quick = entry.key;
                          filters.favorites = quick == 'favorites';
                          filters.offline = quick == 'offline';
                          filters.heard = quick == 'unheard'
                              ? 'unheard'
                              : 'all';
                        }),
                      ),
                  toolbar(detail: true),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget collectionSliver(
    List<CatalogGroup> values,
    String type, {
    bool compact = false,
    bool releaseOrder = false,
  }) {
    values = index.sortGroups(values, sort, descending);
    if (releaseOrder) values = chronologicalAlbums(values);
    final smallCards =
        widget.settings.visualChoice('${type}_view', '') == 'compact_card';
    final grid =
        compact || smallCards || widget.settings.visualBool('${type}_grid');
    final size = compact || smallCards
        ? 140.0
        : widget.settings.visualNumber('catalog_cover_size', 180) *
              MediaCardSizeScope.scale(context);
    Widget tile(int i) {
      final group = values[i];
      if (smallCards) return compactGroup(group, type);
      if (!grid) {
        return ItemActionRegion(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: SizedBox.square(
              dimension: view == 'detailed' ? 64 : 40,
              child: groupImage(group, type),
            ),
            title: Text(
              group.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              view == 'detailed'
                  ? '${group.tracks.length} ${ui(context, 'Músicas')} · ${group.tracks.first.albumArtistNames.join('; ')} · ${catalogTime(group.tracks.fold(Duration.zero, (sum, t) => sum + t.duration))}'
                  : '${group.tracks.length} ${ui(context, 'Músicas')}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: ui(context, 'Reproduzir'),
                  onPressed: () => batch('play', ordered(group.tracks)),
                  icon: const Icon(Icons.play_arrow),
                ),
                actions(group.tracks, collection: collectionKey(group, type)),
              ],
            ),
            onTap: () => openGroup(group, type: type),
          ),
        );
      }
      return ItemActionRegion(
        child: InkWell(
          key: ValueKey('collection.${group.id}'),
          onTap: () => openGroup(group, type: type),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Positioned.fill(child: groupImage(group, type)),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: IconButton.filled(
                          tooltip: ui(context, 'Reproduzir'),
                          onPressed: () => batch('play', ordered(group.tracks)),
                          icon: const Icon(Icons.play_arrow),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: actions(
                          group.tracks,
                          collection: collectionKey(group, type),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                group.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (group.tracks.first.year != null)
                Text(
                  '${group.tracks.first.year}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      );
    }

    if (!grid && view == 'detailed') {
      return SliverToBoxAdapter(child: groupDetails(values, type));
    }
    return grid
        ? SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: smallCards
                  ? 360 * MediaCardSizeScope.scale(context)
                  : size + 40,
              mainAxisExtent: smallCards
                  ? 100 *
                        MediaQuery.textScalerOf(context).scale(1) *
                        MediaCardSizeScope.scale(context).clamp(1, 1.7)
                  : size + 90 * MediaQuery.textScalerOf(context).scale(1),
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
            ),
            itemCount: values.length,
            itemBuilder: (_, i) => tile(i),
          )
        : SliverList.builder(
            itemCount: values.length,
            itemBuilder: (_, i) => tile(i),
          );
  }

  Widget compactTrack(List<Track> values, int i, {bool paged = false}) {
    final t = values[i];
    return ItemActionRegion(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (showSelection || selectedIds.isNotEmpty) {
              if (paged) {
                selectPaged(t);
              } else {
                select(t, values);
              }
            } else {
              widget.onPlay(values, i);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (showSelection || selectedIds.isNotEmpty)
                  Checkbox(
                    value: selectedIds.contains(t.id),
                    onChanged: (_) => setState(() {
                      if (!selectedIds.remove(t.id)) {
                        selectedIds.add(t.id);
                      }
                    }),
                  ),
                if (category == 'albums')
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      t.trackNumber?.toString() ?? (i + 1).toString(),
                    ),
                  ),
                SizedBox.square(
                  dimension: 52 * MediaCardSizeScope.scale(context),
                  child: TrackCover(track: t),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                widget.trackActions(t),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> detailTracks(List<Track> values) => [
    if (category != 'albums' || selectedIds.isNotEmpty)
      SliverToBoxAdapter(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              IconButton(
                tooltip: ui(context, 'Selecionar faixas'),
                isSelected: showSelection,
                onPressed: () => setState(() => showSelection = !showSelection),
                icon: const Icon(Icons.checklist),
              ),
              Text('${values.length} ${ui(context, 'músicas')}'),
              TextButton(
                onPressed: () => setState(
                  () => selectedIds = values.map((t) => t.id).toSet(),
                ),
                child: const UiText('Selecionar todas'),
              ),
              if (selectedIds.isNotEmpty) ...[
                TextButton(
                  onPressed: () => setState(selectedIds.clear),
                  child: const UiText('Limpar seleção'),
                ),
                actions(
                  values.where((t) => selectedIds.contains(t.id)).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    if (view == 'detailed')
      SliverToBoxAdapter(child: trackDetails(values))
    else if (view == 'compact_card')
      SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320 * MediaCardSizeScope.scale(context),
          mainAxisExtent:
              100 *
              MediaQuery.textScalerOf(context).scale(1) *
              MediaCardSizeScope.scale(context).clamp(1, 1.7),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: values.length,
        itemBuilder: (_, i) => compactTrack(values, i),
      )
    else
      SliverList.builder(
        itemCount: values.length,
        itemBuilder: (context, i) {
          final track = values[i];
          return ItemActionRegion(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: category == 'albums'
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.trackNumber?.toString() ?? (i + 1).toString(),
                        ),
                        const SizedBox(width: 12),
                        if (showSelection || selectedIds.isNotEmpty)
                          Checkbox(
                            value: selectedIds.contains(track.id),
                            onChanged: (_) =>
                                select(track, values, checkbox: true),
                          )
                        else
                          SizedBox.square(
                            dimension: 44,
                            child: TrackCover(track: track),
                          ),
                      ],
                    )
                  : showSelection || selectedIds.isNotEmpty
                  ? Checkbox(
                      value: selectedIds.contains(track.id),
                      onChanged: (_) => select(track, values, checkbox: true),
                    )
                  : SizedBox.square(
                      dimension: 44,
                      child: TrackCover(track: track),
                    ),
              title: Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                view == 'detailed'
                    ? columns
                          .map(
                            (c) =>
                                '${ui(context, catalogColumns[c] ?? c)}: ${cell(track, c)}',
                          )
                          .join(' · ')
                    : track.artistNames.join('; '),
              ),
              selected: selectedIds.contains(track.id),
              trailing: widget.trackActions(track),
              onTap: () => select(track, values),
            ),
          );
        },
      ),
  ];

  Widget detail(List<Track> visible) {
    final original = selectedGroup!;
    final ids = original.tracks.map((t) => t.id).toSet();
    final values = visible.where((t) => ids.contains(t.id)).toList();
    final artist = {'artists', 'albumArtists'}.contains(category);
    final album = category == 'albums';
    final collection = collectionKey(original, category);
    final artists = values.isEmpty
        ? const <String>[]
        : values.first.albumArtistNames;
    final releaseYear = albumReleaseYear(original);
    final genres = original.tracks
        .expand((t) => t.genreNames)
        .where((v) => v.trim().isNotEmpty)
        .toSet()
        .toList();
    final headers = <Widget>[
      LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: ui(context, 'Voltar'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  if (groupHistory.isNotEmpty) {
                    final previous = groupHistory.removeLast();
                    category = previous.$1;
                    selectedGroup = previous.$2;
                    artistTab = previous.$3;
                  } else {
                    selectedGroup = null;
                  }
                  selectedIds.clear();
                }),
              ),
              SizedBox.square(
                dimension:
                    (constraints.maxWidth < 650 ? 112.0 : 220.0) *
                    (artist
                        ? 1.2
                        : widget.settings
                              .visualNumber('cover_scale', 1)
                              .clamp(.7, 1.8)),
                child: groupImage(original, category),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      original.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.w800, fontSize: 36),
                    ),
                    if (album)
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          for (final name in artists)
                            TextButton(
                              onPressed: () => openArtist(name),
                              child: Text(name),
                            ),
                          if (releaseYear != null)
                            Text(
                              releaseYear.toString(),
                              key: const ValueKey('album.releaseYear'),
                            ),
                          if (genres.isNotEmpty)
                            Text(
                              genres.join(' • '),
                              key: const ValueKey('album.genres'),
                            ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: values.isEmpty
                              ? null
                              : () => batch(
                                  'play',
                                  album ? ordered(values) : values,
                                ),
                          icon: const Icon(Icons.play_arrow),
                          label: const UiText('Reproduzir'),
                        ),
                        OutlinedButton.icon(
                          onPressed: values.isEmpty
                              ? null
                              : () => batch('shuffle', values),
                          icon: const Icon(Icons.shuffle),
                          label: const UiText('Aleatório'),
                        ),
                        if (collection != null)
                          IconButton(
                            tooltip: ui(
                              context,
                              favoriteCollection(collection, values)
                                  ? 'Remover favorito da coleção'
                                  : 'Favoritar coleção',
                            ),
                            icon: Icon(
                              favoriteCollection(collection, values)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                            ),
                            onPressed: () => widget.settings.favoriteCollection(
                              collection,
                              aliases: collectionAliases(collection, values),
                            ),
                          ),
                        PopupMenuButton<String>(
                          tooltip: ui(context, 'Ações da coleção'),
                          onSelected: (action) async {
                            if (action == 'image') {
                              if (await customizeArtistImage(
                                    context,
                                    original.name,
                                  ) &&
                                  mounted) {
                                setState(() {});
                              }
                            } else if (action == 'merge') {
                              if (await mergeCatalogCollection(
                                    context,
                                    widget.store,
                                    values,
                                    album: album,
                                    albumArtistRole: category == 'albumArtists',
                                    originName: original.name,
                                  ) &&
                                  mounted) {
                                await widget.onAction('refresh', []);
                                await refresh();
                              }
                            } else if (action == 'artist_mix' ||
                                action == 'artist_radio') {
                              await widget.onArtistSelection?.call(
                                original.name,
                                action == 'artist_radio',
                                filtered(),
                                'preview',
                              );
                            } else {
                              await batch(action, values);
                            }
                          },
                          itemBuilder: (_) => [
                            if (artist && widget.onArtistSelection != null) ...[
                              const PopupMenuItem(
                                value: 'artist_mix',
                                child: UiText('Artist mix'),
                              ),
                              const PopupMenuItem(
                                value: 'artist_radio',
                                child: UiText('Artist radio'),
                              ),
                            ],
                            if (!artist)
                              const PopupMenuItem(
                                value: 'mix',
                                child: UiText(
                                  'Iniciar mix a partir deste item',
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'queue',
                              child: UiText('Adicionar à fila'),
                            ),
                            const PopupMenuItem(
                              value: 'playlist',
                              child: UiText('Adicionar à playlist'),
                            ),
                            const PopupMenuItem(
                              value: 'offline',
                              child: UiText('Disponibilizar offline'),
                            ),
                            if (artist)
                              const PopupMenuItem(
                                value: 'image',
                                child: UiText('Personalizar imagem do artista'),
                              ),
                            if (artist || album)
                              const PopupMenuItem(
                                value: 'merge',
                                child: UiText('Mesclar no catálogo'),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (artist)
                      ArtistBiography(
                        key: ValueKey('bio:${original.name}'),
                        artist: original.name,
                        offline: widget.settings.visualBool(
                          'offline_only',
                          fallback: false,
                        ),
                        enabled: widget.settings.visualBool(
                          'artist_biographies',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 48),
      detailToolbar(artist),
    ];
    final content = <Widget>[];
    if (artist && artistTab == 'albums') {
      final albums = index
          .groups('albums', values)
          .where(
            (g) =>
                !filters.favorites ||
                favoriteCollection('album:${g.id}', g.tracks),
          )
          .toList();
      content.add(collectionSliver(albums, 'albums', releaseOrder: true));
    } else if ({'genres', 'years', 'decades'}.contains(category)) {
      headers.add(
        Wrap(
          spacing: 8,
          children: [
            for (final type in ['tracks', 'albums', 'artists'])
              ChoiceChip(
                label: Text(
                  ui(
                    context,
                    {
                      'tracks': 'Músicas',
                      'albums': 'Álbuns',
                      'artists': 'Artistas',
                    }[type]!,
                  ),
                ),
                selected: artistTab == type,
                onSelected: (_) => setState(() => artistTab = type),
              ),
          ],
        ),
      );
      if (artistTab == 'tracks') {
        content.addAll(detailTracks(values));
      } else {
        content.add(
          collectionSliver(
            index.groups(artistTab == 'albums' ? 'albums' : 'artists', values),
            artistTab == 'albums' ? 'albums' : 'artists',
          ),
        );
      }
    } else {
      content.addAll(
        detailTracks(
          album
              ? values
              : artistTab == 'participations'
              ? values
                    .where(
                      (t) =>
                          (t.albumArtist.isNotEmpty ||
                              t.albumArtists.isNotEmpty) &&
                          !t.albumArtistNames.any(
                            (n) => searchKey(n) == searchKey(original.name),
                          ),
                    )
                    .toList()
              : values,
        ),
      );
    }
    if (album && artists.isNotEmpty) {
      final names = artists.map(searchKey).toSet();
      final other = widget.tracks
          .where(
            (t) => t.albumArtistNames.any((n) => names.contains(searchKey(n))),
          )
          .toList();
      final albums = index
          .groups('albums', other)
          .where((g) => g.id != original.id)
          .toList();
      if (albums.isNotEmpty) {
        content.add(
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 48, bottom: 48),
              child: UiText(
                'More by this artist',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );
        content.add(collectionSliver(albums, 'albums', compact: true));
      }
    }
    if ((artist || album) && widget.downloads.remote is ProviderConnections) {
      content.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 48),
            child: LastFmInsights(
              key: ValueKey('insights:${original.id}:$category'),
              providers: widget.downloads.remote as ProviderConnections,
              artist: artist
                  ? original.name
                  : artists.firstOrNull ?? values.firstOrNull?.artist ?? '',
              album: album ? original.name : null,
              catalog: artist ? widget.tracks : values,
              onArtist: openArtist,
            ),
          ),
        ),
      );
    }
    content.add(const SliverToBoxAdapter(child: SizedBox(height: 48)));
    return CustomScrollView(
      key: ValueKey('detail:$category:${original.id}'),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ItemActionRegion(child: headers.first),
              ...headers.skip(1),
            ],
          ),
        ),
        ...content,
      ],
    );
  }

  Widget folders(List<Track> values) {
    final providers = values.map((t) => t.provider).toSet().toList()..sort();
    return ListView(
      children: [
        for (final provider in providers)
          ExpansionTile(
            leading: Icon(provider == 'local' ? Icons.computer : Icons.cloud),
            title: Text(provider == 'local' ? 'Arquivos locais' : provider),
            children: [
              for (final account
                  in values
                      .where((t) => t.provider == provider)
                      .map((t) => t.account)
                      .toSet())
                ExpansionTile(
                  title: Text(
                    account,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: [
                    for (final g in index.groups(
                      'folders',
                      values
                          .where(
                            (t) =>
                                t.provider == provider && t.account == account,
                          )
                          .toList(),
                    ))
                      ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(
                          trackFolder(g.tracks.first),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${g.tracks.length} ${ui(context, 'arquivos')}',
                        ),
                        trailing: actions(g.tracks),
                        onTap: () => openGroup(g, type: 'folders'),
                      ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  Future<void> chooseColumns() async {
    final selected = columns.toSet();
    final value = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const UiText('Colunas da lista detalhada'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView(
              children: [
                const UiText('Capa e título sempre visíveis.'),
                for (final e in catalogColumns.entries)
                  CheckboxListTile(
                    title: Text(e.value),
                    value: selected.contains(e.key),
                    onChanged: (v) => update(() {
                      if (v == true) {
                        selected.add(e.key);
                      } else {
                        selected.remove(e.key);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const UiText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: const UiText('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (value != null) {
      await widget.settings.updateVisual('songs_columns', value);
    }
  }

  Future<void> editFilters() async {
    final draft = CatalogFilters.fromJson(filters.toJson()),
        all = widget.tracks;
    Widget pick(
      String label,
      String value,
      Map<String, String> options,
      void Function(String) changed,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: options.containsKey(value) ? value : '',
        decoration: InputDecoration(labelText: ui(context, label)),
        items: [
          const DropdownMenuItem(value: '', child: UiText('Tudo')),
          for (final e in options.entries)
            DropdownMenuItem(
              value: e.key,
              child: Text(
                label == 'Escuta' ? ui(context, e.value) : e.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) => changed(v ?? ''),
      ),
    );
    Map<String, String> options(Iterable<String> values) {
      final sorted = values.where((v) => v.isNotEmpty).toSet().toList()
        ..sort((a, b) => searchKey(a).compareTo(searchKey(b)));
      return {for (final v in sorted) v: v};
    }

    final result = await showDialog<CatalogFilters>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            '${ui(context, 'Filtros')} · ${ui(context, catalogCategories[category]!)}',
          ),
          content: SizedBox(
            width: 520,
            height: 420,
            child: ListView(
              children: [
                pick(
                  'Fonte',
                  draft.source,
                  index.sourceOptions,
                  (v) => draft.source = v,
                ),
                pick(
                  'Conta',
                  draft.account,
                  options(all.map((t) => t.account)),
                  (v) => draft.account = v,
                ),
                pick(
                  'Pasta (inclui subpastas)',
                  draft.folder,
                  options(all.map(trackFolder)),
                  (v) => draft.folder = v,
                ),
                pick(
                  'Artista',
                  draft.artist,
                  options(all.expand((t) => t.artistNames)),
                  (v) => draft.artist = v,
                ),
                if ({
                  'songs',
                  'favorites',
                  'offline',
                  'folders',
                }.contains(category))
                  pick('Álbum', draft.album, {
                    for (final g in index.groups('albums', all))
                      g.id:
                          '${g.name} · ${g.tracks.first.albumArtistNames.join('; ')}',
                  }, (v) => draft.album = v),
                pick(
                  'Gênero',
                  draft.genre,
                  options(all.expand((t) => t.genreNames)),
                  (v) => draft.genre = v,
                ),
                pick(
                  'Ano de lançamento',
                  draft.year,
                  options(
                    all
                        .where((t) => t.year != null)
                        .map((t) => t.year.toString()),
                  ),
                  (v) => draft.year = v,
                ),
                if ({'songs', 'favorites', 'offline'}.contains(category))
                  pick(
                    'Formato',
                    draft.format,
                    options(all.map(trackFormat)),
                    (v) => draft.format = v,
                  ),
                pick('Escuta', draft.heard == 'all' ? '' : draft.heard, {
                  'heard': 'Ouvidas',
                  'unheard': 'Não ouvidas',
                }, (v) => draft.heard = v.isEmpty ? 'all' : v),
                CheckboxListTile(
                  title: const UiText('Somente favoritos'),
                  value: draft.favorites,
                  onChanged: (v) => update(() => draft.favorites = v ?? false),
                ),
                CheckboxListTile(
                  title: const UiText('Somente disponíveis offline'),
                  value: draft.offline,
                  onChanged: (v) => update(() => draft.offline = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const UiText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft),
              child: const UiText('Aplicar filtros'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        filters = result;
        selectedIds.clear();
      });
      await saveFilters();
    }
  }

  Widget toolbar({bool detail = false}) {
    final sorts = {
      if (detail && category == 'albums') 'track': 'Track number',
      'title': 'Título',
      'artist': 'Artista',
      'album': 'Álbum',
      if (widget.tracks.any((t) => t.addedAt != null)) 'added': 'Inclusão',
      if (stats.isNotEmpty) 'last': 'Última reprodução',
      if (stats.isNotEmpty) 'plays': 'Reproduções',
      if (widget.tracks.any((t) => t.duration > Duration.zero))
        'duration': 'Duração',
    };
    final collections = selectedGroup == null
        ? !{'songs', 'favorites', 'offline'}.contains(category)
        : {'artists', 'albumArtists'}.contains(category) &&
              artistTab == 'albums';
    final cover = widget.settings.visualNumber('catalog_cover_size', 180);
    final selectedView = view == 'compact_card'
        ? view
        : collections && widget.settings.visualBool('${viewCategory}_grid')
        ? 'grid:${[140, 180, 220, 320, 360].reduce((a, b) => (a - cover).abs() < (b - cover).abs() ? a : b)}'
        : view == 'detailed'
        ? 'detailed'
        : 'compact';
    return SingleChildScrollView(
      key: const ValueKey('catalog.controls'),
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          if (!detail && !favoritesPage)
            SizedBox(
              width: 220,
              child: DropdownButton<String>(
                isExpanded: true,
                value: category,
                items: [
                  for (final e in catalogCategories.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: UiText(e.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) chooseCategory(v);
                },
              ),
            ),
          SizedBox(
            width: detail ? 160 : 220,
            child: DropdownButton<String>(
              isExpanded: true,
              key: const ValueKey('catalog.sort'),
              value: sorts.containsKey(activeSort) ? activeSort : 'title',
              items: [
                for (final e in sorts.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: UiText(e.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    if (selectedGroup != null && category == 'albums') {
                      albumSort = v;
                    } else {
                      sort = v;
                    }
                  });
                  if (!(selectedGroup != null && category == 'albums')) {
                    widget.settings.updateVisual('songs_sort', v);
                  }
                }
              },
            ),
          ),
          IconButton(
            tooltip: ui(
              context,
              descending ? 'Ordem decrescente' : 'Ordem crescente',
            ),
            icon: Icon(descending ? Icons.arrow_downward : Icons.arrow_upward),
            onPressed: () {
              setState(() => descending = !descending);
              widget.settings.updateVisual('songs_descending', descending);
            },
          ),
          ViewStyleButton(
            key: const ValueKey('catalog.view'),
            value: selectedView,
            actions: {
              'columns': 'Escolher colunas',
              'dense': dense ? 'Densidade confortável' : 'Densidade compacta',
            },
            families: {
              'list': const {
                'compact': 'Lista compacta',
                'detailed': 'Lista detalhada',
              },
              if (collections)
                'grid': const {
                  'grid:140': 'Small',
                  'grid:180': 'Medium',
                  'grid:220': 'Large',
                  'grid:320': 'Extra Large',
                  'grid:360': 'Larger',
                },
              'cards': const {'compact_card': 'Compact cards'},
            },
            onChanged: (value) {
              if (value == 'columns') {
                chooseColumns();
                return;
              }
              if (value == 'dense') {
                widget.settings.updateVisual('catalog_dense', !dense);
                return;
              }
              final grid = value.startsWith('grid:');
              widget.settings.updateVisual(
                '${viewCategory}_view',
                grid ? 'grid' : value,
              );
              widget.settings.updateVisual(
                '${viewCategory}_grid',
                grid || value == 'compact_card',
              );
              if (grid) {
                widget.settings.updateVisual(
                  'catalog_cover_size',
                  double.parse(value.split(':').last),
                );
              }
            },
          ),

          IconButton(
            tooltip: ui(context, 'Atualizar biblioteca e offline'),
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget filtersBar() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      spacing: 8,
      children: [
        FilterChip(
          label: const UiText('Favoritos'),
          selected: filters.favorites,
          onSelected: (v) {
            setState(() {
              filters.favorites = v;
              selectedIds.clear();
            });
            saveFilters();
          },
        ),
        if (!{'artists', 'albumArtists'}.contains(category))
          FilterChip(
            label: const UiText('Offline'),
            selected: filters.offline,
            onSelected: (v) {
              setState(() {
                filters.offline = v;
                selectedIds.clear();
              });
              saveFilters();
            },
          ),
        for (final e in filters.toJson().entries.where(
          (e) =>
              e.value is String &&
              (e.value as String).isNotEmpty &&
              e.value != 'all',
        ))
          InputChip(
            label: Text(
              switch (e.key) {
                'source' => index.sourceOptions[e.value] ?? e.value.toString(),
                'album' =>
                  index
                          .groups('albums', widget.tracks)
                          .where((g) => g.id == e.value)
                          .firstOrNull
                          ?.name ??
                      'Álbum',
                'heard' => ui(
                  context,
                  e.value == 'heard' ? 'Ouvidas' : 'Não ouvidas',
                ),
                _ => e.value.toString(),
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onDeleted: () {
              final data = filters.toJson();
              data[e.key] = e.key == 'heard' ? 'all' : '';
              setState(() {
                filters = CatalogFilters.fromJson(data);
                selectedIds.clear();
              });
              saveFilters();
            },
          ),
        if (filters.active || quick.isNotEmpty)
          TextButton(
            onPressed: () async {
              setState(() {
                filters = CatalogFilters();
                quick = '';
                quickInput.clear();
                selectedIds.clear();
              });
              await saveFilters();
              await widget.settings.updateVisual('quick_$category', '');
            },
            child: const UiText('Limpar filtros'),
          ),
      ],
    ),
  );
  Widget favoriteResults() {
    final all = filtered();
    prepareFavorites(all);
    final songs = favoriteData.tracks,
        albums = favoriteData.albums,
        artists = favoriteData.artists;
    if (favoriteTab == 'songs') return trackList(songs);
    if (favoriteTab == 'albums') return groups(albums, 'albums');
    if (favoriteTab == 'artists') return groups(artists, 'artists');
    final songCount = songs.isEmpty ? 0 : songs.length + 1;
    final artistCount = artists.isEmpty ? 0 : artists.length + 1;
    final albumCount = albums.isEmpty ? 0 : albums.length + 1;
    if (songCount + artistCount + albumCount == 0) return empty();
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: UiText(
        text,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
    return ListView.builder(
      itemCount: songCount + artistCount + albumCount,
      itemBuilder: (_, i) {
        if (i < songCount) {
          if (i == 0) return heading('Músicas');
          final t = songs[i - 1];
          return ItemActionRegion(
            child: ListTile(
              leading: SizedBox.square(
                dimension: 48,
                child: TrackCover(track: t),
              ),
              title: Text(t.title),
              subtitle: Text(t.artist),
              trailing: actions([t]),
              onTap: () => widget.onPlay(songs, i - 1),
            ),
          );
        }
        i -= songCount;
        if (i < artistCount) {
          if (i == 0) return heading('Artistas');
          return SizedBox(
            height: 100 * MediaCardSizeScope.scale(context).clamp(1, 1.7),
            child: compactGroup(artists[i - 1], 'artists'),
          );
        }
        i -= artistCount;
        if (i == 0) return heading('Álbuns');
        return SizedBox(
          height: 100 * MediaCardSizeScope.scale(context).clamp(1, 1.7),
          child: compactGroup(albums[i - 1], 'albums'),
        );
      },
    );
  }

  Widget playlistResults() {
    final q = searchKey(widget.query).trim();
    final lists = playlists
        .where((p) => q.isEmpty || searchKey(p['name'] as String).contains(q))
        .toList();
    return lists.isEmpty
        ? const Center(
            child: UiText(
              'Nenhuma playlist encontrada. Crie ou importe na página Playlists.',
            ),
          )
        : ListView(
            children: [
              for (final list in lists)
                ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: Text(list['name'] as String),
                  onTap: () => widget.onPlaylist(list['id'] as int),
                ),
            ],
          );
  }

  @override
  Widget build(BuildContext context) {
    final paged =
        !favoritesPage &&
        !widget.home &&
        selectedGroup == null &&
        {'songs', 'favorites', 'offline'}.contains(category);
    final values = paged ? <Track>[] : filtered();
    final body = favoritesPage && selectedGroup == null
        ? favoriteResults()
        : derivingCatalog && values.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : selectedGroup != null
        ? detail(values)
        : category == 'playlists'
        ? playlistResults()
        : {'songs', 'favorites', 'offline'}.contains(category)
        ? (paged ? paginatedTracks() : trackList(values))
        : category == 'folders'
        ? folders(values)
        : groups(catalogGroups(values), category);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.loading ||
              refreshing ||
              derivingCatalog ||
              preparingFavorites)
            const LinearProgressIndicator(),
          if (error != null)
            TextButton(onPressed: refresh, child: UiText(error!)),
          if (!widget.home && selectedGroup == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: UiText(
                      widget.pageTitle ?? catalogCategories[category]!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (favoritesPage)
                    Flexible(
                      flex: 4,
                      fit: FlexFit.tight,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 8,
                            children: [
                              for (final e in const {
                                'all': 'All',
                                'songs': 'Musics',
                                'artists': 'Artists',
                                'albums': 'Albums',
                              }.entries)
                                ChoiceChip(
                                  key: ValueKey('favorites.${e.key}'),
                                  label: UiText(e.value),
                                  selected: favoriteTab == e.key,
                                  onSelected: (_) =>
                                      setState(() => favoriteTab = e.key),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (!favoritesPage)
                    PopupMenuButton<bool>(
                      key: const ValueKey('catalog.quickFavorites'),
                      tooltip: ui(context, 'All / Favorites'),
                      icon: Icon(
                        quickFavorites ? Icons.favorite : Icons.filter_list,
                      ),
                      onSelected: setQuickFavorites,
                      itemBuilder: (_) => [
                        for (final entry in const {
                          false: 'All',
                          true: 'Favorites',
                        }.entries)
                          CheckedPopupMenuItem(
                            value: entry.key,
                            checked: quickFavorites == entry.key,
                            child: UiText(entry.value),
                          ),
                      ],
                    ),
                  if (controlsExpanded)
                    Flexible(flex: 3, fit: FlexFit.tight, child: toolbar()),
                  IconButton.filledTonal(
                    key: const ValueKey('catalog.controls.toggle'),
                    tooltip: ui(context, 'Visualização e ordenação'),
                    isSelected: controlsExpanded,
                    onPressed: () =>
                        setState(() => controlsExpanded = !controlsExpanded),
                    icon: Icon(
                      controlsExpanded ? Icons.chevron_right : Icons.tune,
                    ),
                  ),
                ],
              ),
            ),
            if (filters.active && !favoritesPage) filtersBar(),
            const SizedBox(height: 48),
          ],
          if (widget.home)
            Expanded(
              child: HomePage(
                key: ValueKey('home.$homeReset'),
                onArtistSelection: widget.onArtistSelection,
                onSources: widget.downloads.remote is ProviderConnections
                    ? () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const UiText('Fontes'),
                          content: SizedBox(
                            width: 520,
                            child: SingleChildScrollView(
                              child: SourceVisibilitySettings(
                                providers:
                                    widget.downloads.remote
                                        as ProviderConnections,
                                onChanged: () async {
                                  await widget.onAction('refresh', []);
                                  await refresh();
                                },
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const UiText('Fechar'),
                            ),
                          ],
                        ),
                      )
                    : null,
                memory: memory.home,
                cacheKey: filteredSignature,
                index: index,
                tracks: values,
                settings: widget.settings,
                lastfmMix: widget.downloads.remote is ProviderConnections
                    ? (period) async {
                        final p =
                            widget.downloads.remote as ProviderConnections;
                        final result = await p.profileIndex.tracks(period);
                        final report = await compute(matchLastFmProfile, (
                          result,
                          widget.tracks,
                        ));
                        final byId = {for (final t in widget.tracks) t.id: t};
                        final used = <String>{};
                        return report.ids
                            .where(used.add)
                            .map((id) => byId[id]!)
                            .toList();
                      }
                    : null,
                onFilters: editFilters,
                activeFilters: filters.active ? filtersBar() : null,
                onAction: batch,
                onPlay: widget.onPlay,
                onPlayNamed: widget.onPlayNamed,
                trackActions: widget.trackActions,
                onExplore: (type, g) {
                  setState(() {
                    category = type;
                    selectedGroup = g;
                  });
                },
                onAddSource: widget.onAddSource,
                onResume:
                    values.any(
                      (t) => widget.resumeTrack != null
                          ? t.id == widget.resumeTrack!.id
                          : t.title == widget.resumeTitle,
                    )
                    ? widget.onResume
                    : null,
                resumeTitle: widget.resumeTitle,
                resumeTrack: widget.resumeTrack,
                onNowPlaying: widget.onNowPlaying,
                store: widget.store,
                playlists: playlists,
                onPlaylist: widget.onPlaylist,
                library: body,
              ),
            )
          else
            Expanded(child: body),
        ],
      ),
    );
  }
}
