import 'listening_insights_page.dart';
import '../library/listening_insights.dart';
import 'resizable_side_panel.dart';
import 'design_icon.dart';
import 'backup_options.dart';
import '../persistence/backup_archive.dart';
import 'design_tokens.dart';
import '../lyrics/lyrics_view.dart';
import 'now_playing_artwork.dart';
import 'exit_confirmation.dart';
import '../library/catalog.dart' show CatalogGroup;
import 'global_library_search.dart';
import 'media_indicators.dart';
import 'track_availability_button.dart';

import 'dart:ui' as ui_effects;

import 'metadata_editor.dart';
import '../offline/media_cache.dart';
import '../lyrics/library_lyrics.dart';
import '../library/smart_play.dart';
import '../library/artist_similarity.dart';
import '../library/artist_selection.dart';
import 'artist_selection_dialog.dart';
import 'ui_language.dart';

import 'dart:math';

import 'catalog_browser.dart';
import 'catalog_search_field.dart';
import 'home_page.dart';
import 'window_controls.dart';
import 'cover_scope.dart';
import '../persistence/app_data.dart';
import '../sources/microsoft_auth.dart';

import 'package:path/path.dart' as path;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../library/local_metadata.dart';
import '../library/local_source_sync.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../application/player_controller.dart';
import '../application/playback_save_coordinator.dart';
import '../domain/track.dart';
import '../domain/queue_navigation.dart';
import '../domain/scrobble_policy.dart';
import '../domain/history_policy.dart';
import '../persistence/library_store.dart';
import '../settings/app_settings.dart';
import 'settings_dialog.dart';
import 'local_sources_panel.dart';
import 'playlists_dialog.dart';
import 'navigation.dart';
import 'player_bar.dart';
import 'collection_browser.dart';
import 'now_playing_page.dart';

import 'package:window_manager/window_manager.dart';

import '../sources/provider_connections.dart';
import '../offline/download_manager.dart';
import 'downloads_dialog.dart';
import 'history_page.dart';
import '../platform/windows_integration.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.section = AppSection.home,
    this.onMenu,
    this.menuTooltip = 'Menu',
    required this.onNavigate,
    required this.settings,
    required this.store,
    this.nativeIntegration = false,
    this.validation = false,
    this.designPreview = false,
    this.sidebar,
    this.smokeAudio,
    this.navigationReset = 0,
  });
  final AppSettings settings;
  final LibraryStore store;
  final bool nativeIntegration, validation;
  final bool designPreview;
  final Widget? sidebar;
  final int navigationReset;
  final String? smokeAudio;
  final AppSection section;
  final VoidCallback? onMenu;
  final String menuTooltip;
  final ValueChanged<AppSection> onNavigate;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final PlayerController controller;
  late final LocalSourceSync localSync;
  late final CatalogCoverCache coverCache;
  late final ProviderConnections providers;
  late final DownloadManager downloads;
  WindowsIntegration? windows;
  final historyClaims = <String>{};
  final tracks = <Track>[];
  String query = '';
  SettingsCategory? settingsDestination;
  int catalogRevision = 0;
  int indicatorRevision = -1;
  Set<String> indicatorFavorites = {}, indicatorAlbumCollections = {};
  Set<String> get indicatorCollections {
    final current = widget.settings.collectionFavorites;
    if (indicatorRevision != catalogRevision ||
        !setEquals(current, indicatorFavorites)) {
      indicatorRevision = catalogRevision;
      indicatorFavorites = current;
      indicatorAlbumCollections = {
        ...current,
        ...canonicalAlbumFavorites(tracks, current),
      };
    }
    return indicatorAlbumCollections;
  }

  int? selectedPlaylist;
  bool? lyricsOpen;
  bool get lyricsActive =>
      lyricsOpen ?? widget.settings.nowPlayingStyle == 'lyrics';
  Set<String> favorites = {};
  bool favoritesOnly = false;
  String? storageError;
  bool loading = true, saving = false;
  String lastSaved = '';
  late final MediaCache mediaCache;
  late final libraryLyrics = LibraryLyrics(
    downloads,
    durationFor: (track) => controller.current?.id == track.id
        ? controller.duration
        : Duration.zero,
  );
  Timer? cacheTimer;
  String cacheSignature = '';
  String playbackConfiguration = '';
  bool shutdownRequested = false;
  bool importingBackup = false;
  late final playbackSaves = PlaybackSaveCoordinator(_writePlayback);
  Timer? saveTimer;
  final catalogKey = GlobalKey<CatalogBrowserState>();
  final catalogMemory = CatalogMemory();
  late final listeningInsights = ListeningInsightsRepository(
    widget.store,
    providers.lastfm,
  );
  Widget? cachedLibraryPage;
  String cachedLibraryPageKey = '';
  final queueScaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    localSync = LocalSourceSync(widget.store);
    coverCache = CatalogCoverCache(widget.store);
    providers = ProviderConnections(
      widget.settings.preferences,
      widget.store,
      vault: widget.designPreview
          ? const SystemVault(prefix: 'music_time.design_review.')
          : widget.validation
          ? const SystemVault(prefix: 'music_time.validation.')
          : const SystemVault(),
    );
    mediaCache = MediaCache(
      widget.store,
      providers,
      directory: (widget.validation || widget.designPreview)
          ? () => Future.value(
              Directory(
                path.join(
                  path.dirname(widget.store.database.path),
                  'media-cache',
                ),
              ),
            )
          : null,
    );
    downloads = DownloadManager(
      widget.store,
      providers,
      cache: mediaCache,
      directory: widget.designPreview
          ? () async => Directory(
              path.join(path.dirname(widget.store.database.path), 'offline'),
            )
          : null,
    );
    widget.store.beforeSourceRemoval = (ids) async {
      if (ids.any((id) => controller.queue.any((t) => t.id == id))) {
        if (controller.opening || controller.playing) {
          throw StateError('Pause playback before removing this source.');
        }
        await controller.removeSourceTracks(ids.toSet());
        await playbackSaves.flush();
      }
      await downloads.removeSourceTracks(ids);
    };
    downloads.addListener(scheduleAvailability);
    mediaCache.addListener(scheduleAvailability);
    widget.settings.addListener(configurePlayback);
    cacheTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (!shutdownRequested) {
        unawaited(mediaCache.cleanup().catchError((Object _) {}));
      }
    });
    controller = PlayerController(
      onListening: remember,
      resolver: downloads,
      coverLoader: coverCache.load,
    );
    controller.addListener(cachePlayback);
    configurePlayback();
    unawaited(mediaCache.cleanup().catchError((Object _) {}));
    if (widget.nativeIntegration) {
      windows = WindowsIntegration(
        controller,
        widget.settings,
        save: playbackSaves.flush,
        confirmExit: confirmExit,
        prepareExit: prepareExit,
        resumeAfterExit: resumeAfterExit,
        validation: widget.validation,
        onError: (message) {
          if (mounted) setState(() => storageError = message);
        },
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(windows!.initialize());
      });
    }
    unawaited(load());
    unawaited(widget.store.recoverScrobbles());
    unawaited(widget.store.recoverDownloads());
    saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!shutdownRequested) unawaited(save());
    });
  }

  Timer? availabilityTimer;
  void scheduleAvailability() {
    availabilityTimer?.cancel();
    availabilityTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      if (downloads.running || mediaCache.current != null) {
        scheduleAvailability();
        return;
      }
      catalogMemory.dirty = true;
    });
  }

  void markCatalogDirty() {
    catalogMemory.dirty = true;
    cachedLibraryPage = null;
  }

  void configurePlayback() {
    if (shutdownRequested) return;
    cachedLibraryPage = null;
    final configuration = [
      widget.settings.visualBool('offline_only', fallback: false),
      widget.settings.visualBool('cache_enabled', fallback: true),
      widget.settings.visualNumber('cache_gb', 10),
      widget.settings.visualNumber('prefetch_count', 5),
      widget.settings.visualBool('smart_play', fallback: false),
      widget.settings.visualNumber('continuous_count', 5),
    ].join('|');
    if (configuration == playbackConfiguration) return;
    playbackConfiguration = configuration;
    final offline = widget.settings.visualBool('offline_only', fallback: false);
    downloads.offlineOnly = offline;
    mediaCache.configure(
      enabled:
          widget.settings.visualBool('cache_enabled', fallback: true) &&
          !widget.validation,
      offlineOnly: offline,
      maxBytes:
          (widget.settings.visualNumber('cache_gb', 10) * 1000 * 1000 * 1000)
              .round(),
      prefetchCount: widget.settings.visualNumber('prefetch_count', 5).round(),
    );
    controller.continuous =
        widget.settings.visualBool('smart_play', fallback: false)
        ? (current, recent) async {
            final available = await availableOffline();
            return smartTracks(
              tracks,
              current,
              recent,
              offlineOnly: offline,
              offline: available,
              count: widget.settings
                  .visualNumber('continuous_count', 5)
                  .round()
                  .clamp(1, 100),
            );
          }
        : null;
    cacheSignature = '';
    cachePlayback();
  }

  Future<Set<String>> availableOffline() async {
    final candidates = <Map<String, Object?>>[
      for (final t in tracks)
        if (t.localPath != null) {'id': t.id, 'path': t.localPath},
    ];
    for (final row in await widget.store.downloadTasks(includeCovers: false)) {
      if (row['status'] == 'complete' && row['download_path'] is String) {
        candidates.add({
          'id': row['id'],
          'path': row['download_path'],
          'bytes': row['received'],
        });
      }
    }
    for (final row in await mediaCache.rows(validOnly: true)) {
      candidates.add({
        'id': row['track_id'],
        'path': row['path'],
        'bytes': row['bytes'],
      });
    }
    return compute(validOfflineFiles, candidates);
  }

  void cachePlayback() {
    final track = controller.current;
    if (track == null) {
      mediaCache.pinned = null;
      cacheSignature = '';
      return;
    }
    if (!controller.playing || controller.opening) return;
    final next = controller.upcoming(mediaCache.prefetchCount);
    final signature =
        '${track.id}:${track.revision}|${next.map((t) => '${t.id}:${t.revision}').join('|')}';
    if (signature == cacheSignature) return;
    cacheSignature = signature;
    unawaited(mediaCache.markPlayed(track).catchError((Object _) {}));
    for (final item in next) {
      mediaCache.request(item);
    }
  }

  void openCollection(
    Track track,
    bool album, {
    bool preferAlbumArtist = false,
  }) {
    final name = album
        ? track.album
        : preferAlbumArtist
        ? navigationArtistName(track)
        : track.artistNames.first;
    if (name.isEmpty) return;
    widget.onNavigate(album ? AppSection.albums : AppSection.artists);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = catalogKey.currentState;
      state?.openTrackCollection(
        track,
        album,
        preferAlbumArtist: preferAlbumArtist,
      );
    });
  }

  Future<void> load({bool registerSources = true}) async {
    try {
      coverCache.clear();
      catalogRevision++;
      if (registerSources) {
        for (final source in providers.microsoftSources) {
          await source.registerMicrosoftFolder();
        }
      }
      final values = await widget.store.loadTracks(includeCovers: false);
      final favoriteIds = await widget.store.favoriteIds();
      final playback = await widget.store.loadPlayback(includeCovers: false);
      if (!mounted) return;
      setState(() {
        favorites = favoriteIds;
        tracks
          ..clear()
          ..addAll(values);
      });
      controller.shuffle = playback.shuffle;
      controller.repeat = PlaybackRepeat.values.firstWhere(
        (mode) => mode.name == playback.repeat,
        orElse: () => PlaybackRepeat.off,
      );
      await controller.setVolume(playback.volume);
      try {
        await controller.setEqualizer(
          widget.settings.visualBool('eq_enabled', fallback: false),
          [
            for (final f in PlayerController.equalizerFrequencies)
              widget.settings.visualNumber('eq_$f', 0),
          ],
        );
      } catch (_) {
        if (mounted) {
          setState(
            () => storageError = 'Não foi possível restaurar o equalizador.',
          );
        }
      }
      await controller.restore(
        playback.queue,
        playback.index,
        playback.position,
        title: playback.title,
      );
      try {
        final saved = widget.settings.preferences.getString(
          'playback.shuffle_restore',
        );
        if (saved != null) {
          controller.restoreShuffleSnapshot(
            jsonDecode(saved) as Map<String, dynamic>,
          );
        }
      } catch (_) {
        // Older or mismatched snapshots leave the restored visible order intact.
      }
      if (widget.smokeAudio != null) {
        final fixture = await compute(readLocalTracks, [widget.smokeAudio!]);
        await widget.store.addTracks(fixture);
        if (values.isEmpty) tracks.addAll(fixture);
        await controller.playQueue(fixture, 0);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => storageError = 'Não foi possível restaurar a biblioteca.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
      if (mounted) providers.profileIndex.schedule();
    }
  }

  Future<void> save() async {
    if (shutdownRequested || importingBackup) return;
    try {
      await playbackSaves.save();
    } catch (_) {
      // The error is shown by _writePlayback. Exit uses flush to observe failure.
    }
  }

  Future<void> _writePlayback() async {
    if (importingBackup) return;
    if (loading || controller.opening) {
      if (shutdownRequested) throw StateError('Playback is still opening');
      return;
    }
    final queue = List<Track>.of(controller.queue);
    final shuffle = controller.shuffle;
    final originalOrder = controller.originalQueueOrder;
    final index = controller.queueIndex;
    final position = controller.position;
    final signature =
        '${queue.map((track) => track.id).join('|')}:$index:${position.inMilliseconds}:$shuffle:${originalOrder.join(',')}:${controller.repeat.name}:${controller.volume}:${controller.queueTitle}';
    if (signature == lastSaved) return;
    saving = true;
    try {
      await widget.store.savePlayback(
        queue,
        index,
        position,
        shuffle: shuffle,
        repeat: controller.repeat.name,
        volume: controller.volume,
        title: controller.queueTitle,
      );
      if (shuffle) {
        final snapshot = jsonEncode({
          'queue': queue.map((t) => t.id).toList(),
          'order': originalOrder,
        });
        if (widget.settings.preferences.getString('playback.shuffle_restore') !=
            snapshot) {
          await widget.settings.preferences.setString(
            'playback.shuffle_restore',
            snapshot,
          );
        }
      } else if (widget.settings.preferences.containsKey(
        'playback.shuffle_restore',
      )) {
        await widget.settings.preferences.remove('playback.shuffle_restore');
      }
      lastSaved = signature;
    } catch (_) {
      if (mounted) {
        setState(() => storageError = 'Não foi possível salvar a fila.');
      }
      rethrow;
    } finally {
      saving = false;
    }
  }

  List<String> get backgroundTasks => [
    if (loading) 'Carregando biblioteca',
    if (localSync.running) 'Sincronização local',
    if (providers.anyMicrosoftBusy ||
        providers.anyMicrosoftLoginPending ||
        providers.additional.busy.isNotEmpty)
      'Sincronização ou conexão de fontes',
    if (downloads.running || downloads.maintaining) 'Downloads',
    if (mediaCache.pending.isNotEmpty) 'Pré-carregamento de áudio',
    if (providers.profileIndex.running || providers.flushingScrobbles)
      'Last.fm',
    if (widget.store.artwork.running) 'Otimização de capas',
    if (widget.settings.saving) 'Salvando configurações',
  ];

  Future<bool> confirmExit(bool unsaved) async {
    final tasks = backgroundTasks;
    if (!unsaved && tasks.isEmpty) return true;
    await windows?.show().timeout(const Duration(seconds: 3));
    if (!mounted) return false;
    return showExitConfirmation(context, tasks: tasks, unsaved: unsaved);
  }

  Future<void> prepareExit() async {
    shutdownRequested = true;
    localSync.cancel();
    downloads.suspended = true;
    if (downloads.current != null) downloads.cancelled.add(downloads.current!);
    mediaCache.suspendForExit();
    providers.suspended = true;
    providers.profileIndex.suspended = true;
    for (final source in providers.microsoftSources) {
      source.cancelMicrosoftSync();
      source.cancelMicrosoftLogin();
    }
    for (final id in providers.additional.busy.toList()) {
      providers.additional.cancel(id);
    }
    widget.store.artwork.cancel();
  }

  void resumeAfterExit() {
    shutdownRequested = false;
    downloads.suspended = false;
    providers.suspended = false;
    providers.profileIndex.suspended = false;
    providers.profileIndex.schedule();
    playbackConfiguration = '';
    configurePlayback();
  }

  Future<void> exportBackup() async {
    if (loading ||
        controller.opening ||
        providers.busy ||
        downloads.running ||
        widget.store.artwork.running ||
        widget.settings.saving) {
      throw StateError('Operação em andamento');
    }
    await save();
    if (!mounted) return;
    final options = await showBackupOptions(context);
    if (options == null) return;
    final location = await getSaveLocation(
      suggestedName: 'MusicTime-backup.mtbackup',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Backup Music Time', extensions: ['mtbackup']),
      ],
    );
    if (location == null) return;
    final content = await BackupArchive.create(
      widget.store,
      widget.settings.preferences,
      providers.vault,
      options.sections,
      password: options.password,
    );
    await XFile.fromData(
      content,
      mimeType: 'application/octet-stream',
    ).saveTo(location.path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: UiText(
            'Backup exportado. Guarde o arquivo e a senha em um local seguro.',
          ),
        ),
      );
    }
  }

  Future<void> restoreBackup() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Backup Music Time',
          extensions: ['json', 'mtbackup'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    if (await file.length() > AppData.maxBytes) {
      throw const FormatException('Backup maior que 128 MB.');
    }
    final bytes = await file.readAsBytes();
    String? password;
    if (BackupArchive.encrypted(bytes)) {
      if (!mounted) return;
      final options = await showBackupOptions(context, passwordOnly: true);
      if (options == null) return;
      password = options.password;
    }
    final archive = await BackupArchive.read(bytes, password: password);
    if (!mounted) return;
    final options = await showBackupOptions(
      context,
      available: (archive['sections'] as List).cast<String>().toSet(),
    );
    if (options == null) return;
    if (loading ||
        controller.opening ||
        providers.busy ||
        downloads.running ||
        widget.store.artwork.running ||
        widget.settings.saving) {
      throw StateError('Aguarde as operações em andamento.');
    }
    await save();
    importingBackup = true;
    int missing;
    try {
      if (options.sections.contains('queue')) {
        await controller.player.pause();
      }
      missing = await BackupArchive.restore(
        widget.store,
        widget.settings.preferences,
        providers.vault,
        archive,
        options.sections,
      );
      widget.settings.refreshFromPreferences();
      favorites = await widget.store.favoriteIds();
      await reloadCatalog();
      if (options.sections.contains('queue')) {
        await load(registerSources: false);
      }
    } finally {
      importingBackup = false;
    }
    await save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uiFormat(
              context,
              'Dados importados. $missing referências aguardam revisão. Se importou fontes ou credenciais, reinicie o app antes de conectar.',
              'Data imported. $missing references need review. If you imported sources or credentials, restart the app before connecting.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> restartForMaintenance({String? backup}) async {
    if (windows == null ||
        loading ||
        controller.opening ||
        providers.busy ||
        downloads.running ||
        widget.store.artwork.running ||
        widget.settings.saving) {
      throw StateError('Aguarde as operações em andamento.');
    }
    final root = Directory(path.dirname(widget.store.database.path));
    await AppData.stage(root, backup: backup);
    try {
      await Process.start(Platform.resolvedExecutable, [
        '--restart-after=$pid',
        if (widget.validation) '--validation-profile',
      ], mode: ProcessStartMode.detached);
    } catch (_) {
      await AppData.requestFile(root).delete();
      rethrow;
    }
    await windows!.exit();
  }

  Future<void> addFiles() async {
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Áudio',
            extensions: ['mp3', 'flac', 'm4a', 'ogg', 'wav', 'opus'],
          ),
        ],
      );
      if (!mounted || files.isEmpty) return;
      final additions = await compute(
        readLocalTracks,
        files.map((file) => file.path).toList(),
      );
      await widget.store.addTracks(additions);
      await widget.store.registerLocalSource(
        "files:${DateTime.now().microsecondsSinceEpoch}",
        "Arquivos selecionados",
        additions.map((t) => t.id).toList(),
      );
      coverCache.clear();
      catalogRevision++;
      final values = await widget.store.loadTracks(includeCovers: false);
      final favoriteIds = await widget.store.favoriteIds();
      if (!mounted) return;
      setState(() {
        favorites = favoriteIds;
        tracks
          ..clear()
          ..addAll(values);
        storageError = null;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: UiText('Não foi possível adicionar arquivos.'),
          ),
        );
      }
    }
  }

  Future<void> addFolder() async {
    final folder = await getDirectoryPath();
    if (folder == null || !mounted) return;
    await syncLocalSource(folder);
  }

  Future<void> syncLocalSource(String folder) async {
    if (loading || localSync.running || providers.busy || downloads.running) {
      return;
    }
    setState(() => loading = true);
    try {
      await localSync.sync(folder);
      coverCache.clear();
      catalogRevision++;
      final values = await widget.store.loadTracks(includeCovers: false);
      if (mounted) {
        setState(() {
          tracks
            ..clear()
            ..addAll(values);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => storageError = localSync.error);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void remember(ListeningSession session) {
    providers.observe(session);
    if (!countsForHistory(session)) return;
    final id = '${session.track.id}|${session.startedAt.toIso8601String()}';
    if (!historyClaims.add(id)) return;
    unawaited(
      widget.store
          .recordHistory(session.track.id, session.startedAt, session.listened)
          .then((_) {
            if (mounted) setState(() => catalogRevision++);
          })
          .catchError((Object error) {
            historyClaims.remove(id);
            if (mounted) {
              setState(
                () => storageError = 'Não foi possível registrar histórico.',
              );
            }
          }),
    );
  }

  Widget trackActions(Track track, {int? queueIndex}) {
    final queueKey = queueIndex == null
        ? null
        : controller.queueKeys[queueIndex];
    return PopupMenuButton<String>(
      tooltip: ui(context, 'Ações da faixa'),
      onSelected: (action) {
        final index = queueKey == null
            ? -1
            : controller.queueKeys.indexOf(queueKey);
        if (queueKey != null && index < 0) return;
        performTrackAction(track, action, queueIndex: index < 0 ? null : index);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: UiText('Editar informações no catálogo'),
        ),
        const PopupMenuItem(value: 'artist', child: UiText('Ir para artista')),
        if (track.album.isNotEmpty)
          const PopupMenuItem(value: 'album', child: UiText('Ir para álbum')),
        const PopupMenuItem(value: 'play', child: UiText('Reproduzir agora')),
        const PopupMenuItem(
          value: 'mix',
          child: UiText('Iniciar mix a partir deste item'),
        ),
        const PopupMenuItem(
          value: 'radio',
          child: UiText('Iniciar rádio a partir deste item'),
        ),
        const PopupMenuItem(value: 'next', child: UiText('Tocar a seguir')),
        const PopupMenuItem(value: 'queue', child: UiText('Adicionar à fila')),
        PopupMenuItem(
          value: 'favorite',
          child: Text(
            favorites.contains(track.id) ? 'Remover favorito' : 'Favoritar',
          ),
        ),
        const PopupMenuItem(
          value: 'playlist',
          child: UiText('Adicionar à playlist'),
        ),
        const PopupMenuItem(
          value: 'offline',
          child: UiText('Disponibilizar offline'),
        ),
        const PopupMenuItem(
          value: 'details',
          child: UiText('Detalhes da faixa'),
        ),
        if (queueIndex != null)
          const PopupMenuItem(
            value: 'remove',
            child: UiText('Remover da fila'),
          ),
      ],
    );
  }

  Future<void> performTrackAction(
    Track track,
    String action, {
    int? queueIndex,
  }) async {
    try {
      switch (action) {
        case 'mix':
          await startItemMix([track]);
        case 'radio':
          await startItemMix([track], radio: true);
        case 'edit':
          if (await editCatalogMetadata(context, widget.store, track)) {
            await reloadCatalog();
          }
        case 'artist':
          openCollection(track, false);
        case 'album':
          openCollection(track, true);
        case 'play':
          if (queueIndex != null) {
            await play(
              List.of(controller.queue),
              queueIndex,
              title: controller.queueTitle,
            );
          } else {
            await play([track], 0);
          }
        case 'next':
          await controller.enqueue(track, asNext: true);
          await save();
        case 'queue':
          await controller.enqueue(track);
          await save();
        case 'favorite':
          await favorite(track);
        case 'offline':
          await downloads.select('track:${track.id}', [track]);
        case 'details':
          showTrackDetails(track);
        case 'remove':
          if (queueIndex != null && !controller.opening) {
            await controller.removeQueueEntry(queueIndex);
            await save();
          }
        case 'playlist':
          final lists = await widget.store.playlists();
          if (!mounted) return;
          final id = await showDialog<int>(
            context: context,
            builder: (context) => SimpleDialog(
              insetPadding: const EdgeInsets.all(24),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              title: const UiText('Adicionar à playlist'),
              children: [
                if (lists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: UiText('Crie uma playlist na página Playlists.'),
                  ),
                for (final list in lists)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, list['id'] as int),
                    child: Text(list['name'] as String),
                  ),
              ],
            ),
          );
          if (id != null) await widget.store.appendToPlaylist(id, track.id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: UiText('Não foi possível concluir a ação.')),
        );
      }
    }
  }

  void showCurrentActions() {
    final track = controller.current;
    if (track == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in {
                'play': 'Reproduzir agora',
                'mix': 'Iniciar mix a partir deste item',
                'radio': 'Iniciar rádio a partir deste item',
                'next': 'Tocar a seguir',
                'queue': 'Adicionar à fila',
                'favorite': favorites.contains(track.id)
                    ? 'Remover favorito'
                    : 'Favoritar',
                'playlist': 'Adicionar à playlist',
                'offline': 'Disponibilizar offline',
                'details': 'Detalhes da faixa',
              }.entries)
                ListTile(
                  title: UiText(entry.value),
                  onTap: () {
                    Navigator.pop(context);
                    performTrackAction(track, entry.key);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> showTrackDetails(Track track) async {
    if (track.cover == null && track.hasArtwork) {
      track = track.withCover(await coverCache.load(track.id));
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: Text(track.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (track.cover != null)
                Image.memory(
                  track.cover!,
                  height: 160,
                  errorBuilder: (_, __, ___) =>
                      const MtIcon(Icons.album, size: 80),
                ),
              Text('${ui(context, 'Artista')}: ${track.artist}'),
              Text(
                '${ui(context, 'Álbum')}: ${track.album.isEmpty ? ui(context, 'Sem álbum') : track.album}',
              ),
              Text(
                '${ui(context, 'Ano')}: ${track.year ?? ui(context, 'Não informado')} • ${ui(context, 'Gênero')}: ${track.genre.isEmpty ? ui(context, 'Não informado') : track.genre}',
              ),
              Text(
                '${ui(context, 'Origem')}: ${track.localPath == null ? track.provider : ui(context, 'Arquivo local')}',
              ),
              Text('${ui(context, 'Duração')}: ${time(track.duration)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              controller.enqueue(track, asNext: true).then((_) => save());
            },
            child: const UiText('Tocar a seguir'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              controller.enqueue(track).then((_) => save());
            },
            child: const UiText('Adicionar à fila'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              downloads.select('track:${track.id}', [track]);
            },
            child: const UiText('Disponibilizar offline'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UiText('Fechar'),
          ),
        ],
      ),
    );
  }

  void showGroup(
    String title,
    List<Track> values, {
    required String selection,
  }) {
    final ordered = List<Track>.of(values)..sort(compareAlbumTracks);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: Text(title),
        content: SizedBox(
          width: 520,
          height: 360,
          child: ListView.builder(
            itemCount: ordered.length,
            itemBuilder: (context, index) => ListTile(
              title: Text(ordered[index].title),
              subtitle: Text(ordered[index].artist),
              trailing: trackActions(ordered[index]),
              onTap: () {
                Navigator.pop(context);
                play(ordered, index);
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              downloads.select(selection, ordered);
            },
            child: const UiText('Disponibilizar offline'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UiText('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> favorite(Track track) async {
    try {
      await widget.store.setFavorite(track.id, !favorites.contains(track.id));
      final ids = await widget.store.favoriteIds();
      if (mounted) setState(() => favorites = ids);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: UiText('Não foi possível salvar favorito.')),
        );
      }
    }
  }

  Future<void> playNamed(List<Track> values, int index, String title) =>
      play(values, index, title: title);

  Future<void> play(List<Track> values, int index, {String? title}) async {
    final queue = List<Track>.of(values);
    if (index >= 0 &&
        index < queue.length &&
        queue[index].cover == null &&
        queue[index].hasArtwork) {
      queue[index] = queue[index].withCover(
        await coverCache.load(queue[index].id),
      );
    }
    await controller.playQueue(queue, index, title: title);
    await save();
  }

  void showQueue() {
    setState(() => lyricsOpen = false);
    final box =
        queueScaffoldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.size.width >= 900) {
      widget.settings.updateVisual(
        'show_queue',
        !widget.settings.visualBool('show_queue'),
      );
    } else {
      queueScaffoldKey.currentState?.openEndDrawer();
    }
  }

  Widget sidePanel({bool drawer = false}) => lyricsActive
      ? Material(
          key: const ValueKey('lyrics.side-panel'),
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .82),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.current?.title ?? ui(context, 'Letras'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: ui(context, 'Fechar'),
                      icon: const MtIcon(Icons.close),
                      onPressed: () {
                        setState(() => lyricsOpen = false);
                        if (drawer) {
                          queueScaffoldKey.currentState?.closeEndDrawer();
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LyricsView(
                  controller: controller,
                  settings: widget.settings,
                  loader: libraryLyrics.load,
                ),
              ),
            ],
          ),
        )
      : queueSidebar(drawer: drawer);

  Widget queueSidebar({bool drawer = false}) => Material(
    key: const ValueKey("queue.surface"),
    color: Theme.of(context).colorScheme.surfaceContainerHigh
        .withValues(alpha: .82),
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UiText(
                        'Fila de reprodução',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (controller.queueTitle != null)
                        Text(
                          controller.queueTitle!,
                          key: const ValueKey('queue.context'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: const ValueKey('queue.actions'),
                  tooltip: ui(context, 'Ações'),
                  icon: const MtIcon(Icons.more_horiz),
                  onSelected: (action) async {
                    if (action == 'save') {
                      final snapshot = List<Track>.of(controller.queue);
                      final saved = await saveSelection(snapshot);
                      if (saved && mounted) await reloadCatalog();
                    } else if (action == 'clear') {
                      await controller.clearQueue();
                      await save();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      key: const ValueKey('queue.save-playlist'),
                      value: 'save',
                      enabled: controller.queue.isNotEmpty,
                      child: const UiText('Save queue as playlist'),
                    ),
                    PopupMenuItem(
                      key: const ValueKey('queue.clear'),
                      value: 'clear',
                      enabled:
                          !controller.opening && controller.queue.isNotEmpty,
                      child: const UiText('Limpar fila'),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: ui(context, 'Fechar fila'),
                  icon: const MtIcon(Icons.close),
                  onPressed: () {
                    if (drawer) {
                      queueScaffoldKey.currentState?.closeEndDrawer();
                    } else {
                      widget.settings.updateVisual('show_queue', false);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: controller.queue.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: UiText(
                        'Selecione uma música para iniciar a fila.',
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: controller.queue.length,
                    onReorderItem: (oldIndex, newIndex) {
                      controller.reorderQueue(oldIndex, newIndex);
                      save();
                    },
                    itemBuilder: (context, index) => ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      leading: SizedBox.square(
                        dimension: 32,
                        child: TrackCover(track: controller.queue[index]),
                      ),
                      key: ValueKey(controller.queueKeys[index]),
                      title: Text(
                        controller.queue[index].title,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        controller.queue[index].artist,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: index == controller.queueIndex,
                      onTap: controller.opening
                          ? null
                          : () => play(
                              List.of(controller.queue),
                              index,
                              title: controller.queueTitle,
                            ),
                      trailing: Padding(
                        padding: const EdgeInsets.only(right: 28),
                        child: trackActions(
                          controller.queue[index],
                          queueIndex: index,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    widget.store.beforeSourceRemoval = null;
    availabilityTimer?.cancel();
    saveTimer?.cancel();
    if (!shutdownRequested) unawaited(save());
    cacheTimer?.cancel();
    widget.settings.removeListener(configurePlayback);
    controller.removeListener(cachePlayback);
    downloads.removeListener(scheduleAvailability);
    mediaCache.removeListener(scheduleAvailability);
    mediaCache.dispose();
    windows?.dispose();
    controller.dispose();
    downloads.dispose();
    providers.dispose();
    localSync.dispose();
    super.dispose();
  }

  String time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> reloadCatalog() async {
    coverCache.clear();
    catalogRevision++;
    final values = await widget.store.loadTracks(includeCovers: false);
    if (mounted) {
      setState(() {
        tracks
          ..clear()
          ..addAll(values);
      });
      await controller.refreshMetadata(values);
    }
  }

  List<Track> get visibleTracks => tracks
      .where(
        (track) =>
            (!(favoritesOnly || widget.section == AppSection.favorites) ||
                favorites.contains(track.id)) &&
            '${track.title} ${track.artist} ${track.album}'
                .toLowerCase()
                .contains(query.toLowerCase()),
      )
      .toList();

  bool get globalSearch => {
    AppSection.home,
    AppSection.nowPlaying,
    AppSection.history,
    AppSection.insights,
  }.contains(widget.section);
  Widget searchField() => CatalogSearchField(
    value: query,
    onChanged: (value) => setState(() => query = value),
  );

  void openSearchResult(String type, CatalogGroup group) {
    setState(() => query = '');
    widget.onNavigate(
      type == 'albums'
          ? AppSection.albums
          : {'artists', 'albumArtists'}.contains(type)
          ? AppSection.artists
          : AppSection.library,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) catalogKey.currentState?.openGroup(group, type: type);
    });
  }

  @override
  void didUpdateWidget(covariant LibraryScreen old) {
    super.didUpdateWidget(old);
    if (widget.section != AppSection.settings) settingsDestination = null;
    if (old.navigationReset != widget.navigationReset) {
      settingsDestination = null;
      query = '';
      selectedPlaylist = null;
      cachedLibraryPage = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        catalogKey.currentState?.resetRoot(
          widget.section == AppSection.artists
              ? 'albumArtists'
              : widget.section == AppSection.albums
              ? 'albums'
              : widget.section == AppSection.favorites
              ? 'favorites'
              : 'songs',
        );
      });
    }
  }

  Widget libraryPage({String? category}) {
    final key =
        '$category|${widget.section}|$catalogRevision|$loading|$query|${identityHashCode(favorites)}|${controller.current?.id}|${controller.current?.title}|${controller.playing}';
    if (cachedLibraryPage != null && cachedLibraryPageKey == key) {
      return cachedLibraryPage!;
    }
    cachedLibraryPageKey = key;
    return cachedLibraryPage = CatalogBrowser(
      key: catalogKey,
      memory: catalogMemory,
      tracks: tracks,
      favorites: favorites,
      store: widget.store,
      settings: widget.settings,
      downloads: downloads,
      query: query,
      initialCategory:
          category ??
          (widget.section == AppSection.favorites ? 'favorites' : 'songs'),
      pageTitle: widget.section.label,
      home: widget.section == AppSection.home,
      loading: loading,
      revision: catalogRevision,
      onPlay: play,
      onPlayNamed: playNamed,
      onArtistSelection: openArtistSelection,
      onAction: catalogAction,
      trackActions: trackActions,
      onAddSource: () => widget.onNavigate(AppSection.settings),
      onResume: controller.current == null ? null : () => controller.toggle(),
      resumeTitle: controller.current?.title,
      resumeTrack: controller.current,
      resumePlaying: controller.playing,
      onNowPlaying: () => widget.onNavigate(AppSection.nowPlaying),
      onPlaylist: (id) {
        selectedPlaylist = id;
        widget.onNavigate(AppSection.playlists);
      },
    );
  }

  bool startingItemMix = false;
  late final artistSimilarity = ArtistSimilarity(
    widget.store,
    providers.lastfm,
  );
  Future<void> openArtistSelection(
    String artist,
    bool radio,
    List<Track> candidates,
    String action,
  ) async {
    final offline = await availableOffline();
    final only = widget.settings.visualBool('offline_only', fallback: false);
    final eligible = eligibleArtistTracks(
      List<Track>.of(tracks),
      offline,
      offlineOnly: only,
    );
    if (!mounted) return;
    await showArtistSelection(
      context,
      artist: artist,
      radio: radio,
      action: action,
      eligible: eligible,
      settings: widget.settings,
      similarity: artistSimilarity,
      onPlay: playNamed,
      onSave: saveSelection,
    );
  }

  Future<void> startItemMix(List<Track> seeds, {bool radio = false}) async {
    if (startingItemMix || seeds.isEmpty) return;
    startingItemMix = true;
    try {
      final available = await availableOffline();
      if (!mounted) return;
      final eligible = eligibleArtistTracks(
        List<Track>.of(tracks),
        available,
        offlineOnly: widget.settings.visualBool(
          'offline_only',
          fallback: false,
        ),
      );
      final artist = seeds.length == 1
          ? seeds.first.artistNames.first
          : navigationArtistName(seeds.first);
      final album = seeds.first.album;
      final label = seeds.length == 1
          ? seeds.first.title
          : album.isNotEmpty &&
                seeds.every((t) => albumKey(t) == albumKey(seeds.first))
          ? album
          : artist;
      await showArtistSelection(
        context,
        artist: artist,
        radio: radio,
        action: 'play',
        seeds: List<Track>.of(seeds),
        seedLabel: label,
        eligible: eligible,
        settings: widget.settings,
        similarity: artistSimilarity,
        onPlay: playNamed,
        onSave: saveSelection,
      );
    } finally {
      startingItemMix = false;
    }
  }

  Future<void> catalogAction(String action, List<Track> values) async {
    if (action == 'refresh') {
      await reloadCatalog();
      return;
    }
    if (values.isEmpty) return;
    try {
      switch (action) {
        case 'mix':
          await startItemMix(values);
        case 'radio':
          await startItemMix(values, radio: true);
        case 'play':
          await play(values, 0);
        case 'shuffle':
          if (!controller.shuffle) controller.toggleShuffle();
          await play(values, Random().nextInt(values.length));
        case 'next':
          for (final track in values.reversed) {
            await controller.enqueue(track, asNext: true);
          }
          await save();
        case 'queue':
          for (final track in values) {
            await controller.enqueue(track);
          }
          await save();
        case 'favorite':
        case 'unfavorite':
          await widget.store.setFavorites(
            values.map((t) => t.id).toList(),
            action == 'favorite',
          );
          final ids = await widget.store.favoriteIds();
          if (mounted) setState(() => favorites = ids);
        case 'offline':
          await downloads.select(
            'selection:${values.map((t) => t.id).join('|')}',
            values,
          );
        case 'details':
          showTrackDetails(values.first);
        case 'save':
          await saveSelection(values);
        case 'playlist':
          final lists = await widget.store.playlists();
          if (!mounted) return;
          final id = await showDialog<int>(
            context: context,
            builder: (context) => SimpleDialog(
              insetPadding: const EdgeInsets.all(24),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              title: const UiText('Adicionar seleção à playlist'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, -1),
                  child: const UiText('Criar playlist com a seleção'),
                ),
                for (final list in lists)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, list['id'] as int),
                    child: Text(list['name'] as String),
                  ),
              ],
            ),
          );
          if (id == -1) {
            await saveSelection(values);
          } else if (id != null) {
            await widget.store.appendTracksToPlaylist(
              id,
              values.map((t) => t.id).toList(),
            );
          }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: UiText('Não foi possível concluir a ação da seleção.'),
          ),
        );
      }
    }
  }

  Future<bool> saveSelection(List<Track> values) async {
    final input = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: const UiText('Salvar seleção como playlist manual'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: ui(context, 'Nome da playlist'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text.trim());
              }
            },
            child: const UiText('Criar'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), input.dispose);
    if (name != null) {
      await widget.store.importPlaylist(name, values.map((t) => t.id).toList());
      return true;
    }
    return false;
  }

  Widget cover(Track track, {bool artist = false}) => track.cover == null
      ? MtIcon(artist ? Icons.person : Icons.album, size: 40)
      : ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            track.cover!,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const MtIcon(Icons.album, size: 40),
          ),
        );

  Widget groupsPage(bool albums) => CollectionBrowser(
    albums: albums,
    tracks: List.of(tracks),
    query: query,
    settings: widget.settings,
    downloads: downloads,
    onPlay: play,
    onQueue: (values) async {
      for (final track in values) {
        await controller.enqueue(track);
      }
      await save();
    },
    onOffline: (selection, values) => downloads.select(selection, values),
    onTrackDetails: showTrackDetails,
    trackActions: trackActions,
  );

  Widget reviewPlayerBar() => PlayerBar(
    availability: TrackAvailabilityButton(
      track: controller.current,
      downloads: downloads,
    ),
    lyricsActive: lyricsActive,
    lastfmActive:
        providers.lastfmConnected &&
        ((widget.settings.preferences.getBool('lastfm.scrobbling') ?? false) ||
            (widget.settings.preferences.getBool('lastfm.now_playing') ??
                false)) &&
        !downloads.offlineOnly,
    lastfmStatus: providers.lastfmStatusLoading
        ? 'Restaurando conexão Last.fm…'
        : providers.lastfmStatusError
        ? 'Não foi possível ler a sessão Last.fm no cofre'
        : !providers.lastfmConnected
        ? 'Last.fm não conectado'
        : downloads.offlineOnly
        ? 'Last.fm conectado • modo offline'
        : ((widget.settings.preferences.getBool('lastfm.scrobbling') ??
                  false) ||
              (widget.settings.preferences.getBool('lastfm.now_playing') ??
                  false))
        ? 'Last.fm conectado • envios ativados'
        : 'Last.fm conectado • envios desativados',
    onArtist: () => controller.current == null
        ? null
        : openCollection(controller.current!, false, preferAlbumArtist: true),
    onAlbum: () => controller.current == null
        ? null
        : openCollection(controller.current!, true),
    controller: controller,
    settings: widget.settings,
    favorite: favorites.contains(controller.current?.id),
    onFavorite: () {
      if (controller.current != null) {
        favorite(controller.current!);
      }
    },
    onDetails: () {
      if (controller.current != null) {
        showCurrentActions();
      }
    },
    onLyrics: () {
      final enabled = !lyricsActive;
      setState(() => lyricsOpen = enabled);
      if (enabled) {
        widget.settings.updateVisual('show_queue', false);
        final box =
            queueScaffoldKey.currentContext?.findRenderObject() as RenderBox?;
        if (box != null && box.size.width < 900) {
          queueScaffoldKey.currentState?.openEndDrawer();
        }
      }
    },
    onQueue: showQueue,
    onExpand: () => widget.onNavigate(AppSection.nowPlaying),
    onSave: save,
  );

  bool get sharedBackdrop => true;
  Widget playbackSurface(Widget child) {
    if (!sharedBackdrop) return child;
    final cover = controller.current?.cover;
    final background = widget.settings.visualChoice('background', 'blur');
    return Stack(
      key: const ValueKey('app.global-background'),
      children: [
        if (cover != null && background != 'solid')
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: widget.settings
                    .visualNumber('background_intensity', .20)
                    .clamp(.05, .45),
                child: ImageFiltered(
                  imageFilter: ui_effects.ImageFilter.blur(
                    sigmaX: background == 'cover' ? 64 : 32,
                    sigmaY: background == 'cover' ? 64 : 32,
                  ),
                  child: Image.memory(
                    cover,
                    cacheWidth: 1280,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, widget.settings, providers]),
    builder: (context, _) => MediaIndicatorScope(
      favorites: favorites,
      collections: indicatorCollections,
      currentId: controller.current?.id,
      currentTrack: controller.current,
      playing: controller.playing,
      child: CatalogCoverScope(
        cache: coverCache,
        revision: catalogRevision,
        child: playbackSurface(
          Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.sidebar != null) widget.sidebar!,
                    Expanded(
                      child: Scaffold(
                        backgroundColor: Colors.transparent,
                        key: queueScaffoldKey,
                        extendBodyBehindAppBar: false,
                        endDrawer: Drawer(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 84, 16, 16),
                            child: Card(
                              elevation: 12,
                              clipBehavior: Clip.antiAlias,
                              child: sidePanel(drawer: true),
                            ),
                          ),
                        ),
                        appBar: AppBar(
                          backgroundColor: sharedBackdrop
                              ? Colors.transparent
                              : null,
                          surfaceTintColor: sharedBackdrop
                              ? Colors.transparent
                              : null,
                          flexibleSpace:
                              (widget.nativeIntegration || widget.designPreview)
                              ? const DragToMoveArea(child: SizedBox.expand())
                              : null,
                          actions: [
                            if (widget.designPreview)
                              Tooltip(
                                message: ui(
                                  context,
                                  'Perfil temporário com coleção de demonstração',
                                ),
                                child: Chip(
                                  label: UiText(
                                    'Prévia de design',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              ),
                            if (widget.nativeIntegration ||
                                widget.designPreview)
                              const WindowControls(),
                          ],
                          toolbarHeight: MtDesign.topbar,
                          centerTitle: true,
                          title: ConstrainedBox(
                            key: const ValueKey('search.global.container'),
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Expanded(child: searchField()),
                                  if ({
                                    AppSection.home,
                                    AppSection.library,
                                    AppSection.artists,
                                    AppSection.albums,
                                    AppSection.favorites,
                                  }.contains(widget.section))
                                    IconButton(
                                      tooltip: ui(context, 'Filtros da página'),
                                      icon: const MtIcon(Icons.filter_alt),
                                      onPressed: () => catalogKey.currentState
                                          ?.editFilters(),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          leading: widget.onMenu == null
                              ? null
                              : IconButton(
                                  tooltip: ui(context, widget.menuTooltip),
                                  icon: const MtIcon(Icons.menu),
                                  onPressed: widget.onMenu,
                                ),
                        ),
                        body: SafeArea(
                          child: Padding(
                            padding: EdgeInsets.zero,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) => Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              if (!{
                                                AppSection.home,
                                                AppSection.library,
                                                AppSection.favorites,
                                                AppSection.artists,
                                                AppSection.albums,
                                                AppSection.settings,
                                                AppSection.nowPlaying,
                                                AppSection.playlists,
                                                AppSection.insights,
                                              }.contains(widget.section))
                                                Padding(
                                                  key: const ValueKey(
                                                    'page.heading',
                                                  ),
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        24,
                                                        12,
                                                        24,
                                                        24,
                                                      ),
                                                  child: UiText(
                                                    widget.section.label,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .headlineSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                ),
                                              Expanded(
                                                child:
                                                    globalSearch &&
                                                        query.trim().isNotEmpty
                                                    ? GlobalLibrarySearch(
                                                        tracks:
                                                            downloads
                                                                .offlineOnly
                                                            ? tracks
                                                                  .where(
                                                                    (
                                                                      t,
                                                                    ) => catalogMemory
                                                                        .offline
                                                                        .contains(
                                                                          t.id,
                                                                        ),
                                                                  )
                                                                  .toList()
                                                            : tracks,
                                                        query: query,
                                                        store: widget.store,
                                                        revision:
                                                            catalogRevision,
                                                        onOpen:
                                                            openSearchResult,
                                                        onPlaylist: (id) {
                                                          setState(() {
                                                            query = '';
                                                            selectedPlaylist =
                                                                id;
                                                          });
                                                          widget.onNavigate(
                                                            AppSection
                                                                .playlists,
                                                          );
                                                        },
                                                      )
                                                    : switch (widget.section) {
                                                        AppSection.home ||
                                                        AppSection.library ||
                                                        AppSection.favorites =>
                                                          libraryPage(),
                                                        AppSection.artists =>
                                                          libraryPage(
                                                            category:
                                                                'albumArtists',
                                                          ),
                                                        AppSection.albums =>
                                                          libraryPage(
                                                            category: 'albums',
                                                          ),
                                                        AppSection.nowPlaying => NowPlayingPage(
                                                          loadLyrics:
                                                              libraryLyrics
                                                                  .load,
                                                          showLyrics: false,
                                                          onArtist: () =>
                                                              controller
                                                                      .current ==
                                                                  null
                                                              ? null
                                                              : openCollection(
                                                                  controller
                                                                      .current!,
                                                                  false,
                                                                ),
                                                          onAlbum: () =>
                                                              controller
                                                                      .current ==
                                                                  null
                                                              ? null
                                                              : openCollection(
                                                                  controller
                                                                      .current!,
                                                                  true,
                                                                ),
                                                          controller:
                                                              controller,
                                                          settings:
                                                              widget.settings,
                                                          favorite: favorites
                                                              .contains(
                                                                controller
                                                                    .current
                                                                    ?.id,
                                                              ),
                                                          onFavorite: () {
                                                            if (controller
                                                                    .current !=
                                                                null) {
                                                              favorite(
                                                                controller
                                                                    .current!,
                                                              );
                                                            }
                                                          },
                                                          onDetails: () {
                                                            if (controller
                                                                    .current !=
                                                                null) {
                                                              showCurrentActions();
                                                            }
                                                          },
                                                          onFullscreen:
                                                              widget
                                                                  .nativeIntegration
                                                              ? () async {
                                                                  await windowManager
                                                                      .setFullScreen(
                                                                        !await windowManager
                                                                            .isFullScreen(),
                                                                      );
                                                                }
                                                              : null,
                                                        ),
                                                        AppSection.playlists =>
                                                          PlaylistsPage(
                                                            key: ValueKey(
                                                              'playlists.root.${widget.navigationReset}',
                                                            ),
                                                            onChanged:
                                                                markCatalogDirty,
                                                            initialPlaylist:
                                                                selectedPlaylist,
                                                            query: query,
                                                            store: widget.store,
                                                            settings:
                                                                widget.settings,
                                                            trackActions:
                                                                trackActions,
                                                            tracks: List.of(
                                                              tracks,
                                                            ),
                                                            onPlay: play,
                                                            onPlayNamed:
                                                                playNamed,
                                                            onOffline:
                                                                (
                                                                  selection,
                                                                  values,
                                                                ) => downloads
                                                                    .select(
                                                                      selection,
                                                                      values,
                                                                    ),
                                                            onShuffle: (values) =>
                                                                catalogAction(
                                                                  'shuffle',
                                                                  values,
                                                                ),
                                                            onQueue: (values) =>
                                                                catalogAction(
                                                                  'queue',
                                                                  values,
                                                                ),
                                                          ),
                                                        AppSection.insights =>
                                                          ListeningInsightsPage(
                                                            repository:
                                                                listeningInsights,
                                                            settings:
                                                                widget.settings,
                                                            store: widget.store,
                                                            catalog: tracks,
                                                            catalogRevision:
                                                                catalogRevision,
                                                            availableOffline:
                                                                availableOffline,
                                                            onPlay: playNamed,
                                                            onSaved: () {
                                                              catalogMemory
                                                                      .dirty =
                                                                  true;
                                                            },
                                                            onConfigure: () {
                                                              settingsDestination =
                                                                  SettingsCategory
                                                                      .lastfm;
                                                              widget.onNavigate(
                                                                AppSection
                                                                    .settings,
                                                              );
                                                            },
                                                            onOpen:
                                                                openSearchResult,
                                                          ),
                                                        AppSection.history =>
                                                          HistoryPage(
                                                            store: widget.store,
                                                            onPlay: play,
                                                            trackActions:
                                                                trackActions,
                                                          ),
                                                        AppSection.downloads =>
                                                          DownloadsDialog(
                                                            manager: downloads,
                                                            embedded: true,
                                                          ),
                                                        AppSection.settings => SettingsPage(
                                                          initialCategory:
                                                              settingsDestination ??
                                                              SettingsCategory
                                                                  .general,
                                                          key: ValueKey(
                                                            'settings.root.${widget.navigationReset}',
                                                          ),
                                                          settings:
                                                              widget.settings,
                                                          canOptimizeArtwork: () =>
                                                              !loading &&
                                                              !shutdownRequested &&
                                                              !localSync
                                                                  .running,
                                                          onCustomizeHome: () {
                                                            widget.onNavigate(
                                                              AppSection.home,
                                                            );
                                                            WidgetsBinding
                                                                .instance
                                                                .addPostFrameCallback((
                                                                  _,
                                                                ) {
                                                                  if (mounted) {
                                                                    customizeHome(
                                                                      context,
                                                                      widget
                                                                          .settings,
                                                                    );
                                                                  }
                                                                });
                                                          },
                                                          localSources:
                                                              LocalSourcesPanel(
                                                                sync: localSync,
                                                                store: widget
                                                                    .store,
                                                                onAddFiles:
                                                                    addFiles,
                                                                onAddFolder:
                                                                    addFolder,
                                                                onSync:
                                                                    syncLocalSource,
                                                                onChanged:
                                                                    reloadCatalog,
                                                              ),
                                                          trackCount:
                                                              tracks.length,
                                                          onAddFiles: addFiles,
                                                          onAddFolder:
                                                              addFolder,
                                                          providers: providers,
                                                          onImported:
                                                              reloadCatalog,
                                                          previewTrack:
                                                              controller
                                                                  .current,
                                                          downloads: downloads,
                                                          controller:
                                                              controller,
                                                          onBackup:
                                                              exportBackup,
                                                          onRestore:
                                                              restoreBackup,
                                                          onReset: () =>
                                                              restartForMaintenance(),
                                                        ),
                                                      },
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (constraints.maxWidth >= 900 &&
                                            (widget.settings.visualBool(
                                                  'show_queue',
                                                ) ||
                                                lyricsActive)) ...[
                                          ResizableSidePanel(
                                            key: ValueKey(
                                              lyricsActive
                                                  ? 'lyrics.panel'
                                                  : 'queue.panel',
                                            ),
                                            settings: widget.settings,
                                            preference: lyricsActive
                                                ? 'lyrics_panel_width'
                                                : 'queue_panel_width',
                                            defaultWidth: lyricsActive
                                                ? MtDesign.lyrics
                                                : MtDesign.queue,
                                            maxWidth: constraints.maxWidth * .6,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    0,
                                                    0,
                                                    0,
                                                    0,
                                                  ),
                                              child: Card(
                                                color: Colors.transparent,
                                                key: const ValueKey(
                                                  "queue.floating",
                                                ),
                                                margin: EdgeInsets.zero,
                                                elevation: 0,
                                                clipBehavior: Clip.antiAlias,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(24),
                                                      ),
                                                ),
                                                child: sidePanel(),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                if (storageError != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: UiText(
                                      storageError!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                                if (controller.error != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: UiText(
                                      controller.error!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              reviewPlayerBar(),
            ],
          ),
        ),
      ),
    ),
  );
}
