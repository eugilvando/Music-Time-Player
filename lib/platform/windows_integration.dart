import 'tray_window.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_media_session/flutter_media_session.dart' as media;
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

import '../application/player_controller.dart';
import '../application/exit_coordinator.dart';
import '../settings/app_settings.dart';
import '../sources/microsoft_auth.dart';
import '../domain/queue_navigation.dart';
import 'system_accent.dart';

class WindowsIntegration with WindowListener {
  WindowsIntegration(
    this.controller,
    this.settings, {
    required this.save,
    required this.onError,
    this.confirmExit,
    this.prepareExit,
    this.resumeAfterExit,
    this.validation = false,
  });
  final PlayerController controller;
  final AppSettings settings;
  final Future<void> Function() save;
  final void Function(String) onError;
  final Future<bool> Function(bool unsaved)? confirmExit;
  final Future<void> Function()? prepareExit;
  final void Function()? resumeAfterExit;
  final bool validation;
  final session = media.FlutterMediaSession();
  late final systemAccent = SystemAccentController(settings);
  tray.TrayIcon? icon;
  tray.Menu? menu;
  tray.MenuItem? playItem;
  bool _disposed = false, _syncing = false, _mediaReady = false;
  bool get _exiting => _exit.running;
  late final _exit = ExitCoordinator(
    confirm: (unsaved) => confirmExit?.call(unsaved) ?? Future.value(true),
    prepare: () => prepareExit?.call() ?? Future.value(),
    save: save,
    releaseMedia: _releaseMedia,
    close: _close,
    resume: () {
      if (_mediaReleased) {
        controller.addListener(changed);
        _mediaReleased = false;
        unawaited(session.activate().catchError((Object _) {}));
      }
      unawaited(
        windowManager.setPreventClose(icon != null).catchError((Object _) {}),
      );
      resumeAfterExit?.call();
    },
    log: log,
  );
  Timer? _validationTimer;
  String lastState = '', lastMetadata = '';
  bool _mediaReleased = false;

  Future<void> _logTail = Future.value();
  Future<void> log(String event) {
    final job = _logTail.then((_) => _appendLog(event));
    _logTail = job;
    return job;
  }

  Future<void> _appendLog(String event) async {
    try {
      final dir = validation
          ? Directory(
              path.join(
                Directory.systemTemp.path,
                'music_time_validation_profile',
              ),
            )
          : await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      await File(path.join(dir.path, 'windows_diagnostics.log')).writeAsString(
        '${DateTime.now().toUtc().toIso8601String()} $event\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  Future<void> initialize() async {
    if (!Platform.isWindows) return;
    unawaited(
      systemAccent.initialize().then(
        (ready) =>
            log(ready ? 'system_accent_ready' : 'system_accent_unavailable'),
      ),
    );
    windowManager.addListener(this);
    try {
      icon = tray.TrayIcon.create();
      if (icon == null) throw StateError('Bandeja indisponível');
      final image = tray.ImageAsset.fromAsset('assets/tray_icon.ico');
      if (image == null) throw StateError('Ícone indisponível');
      icon!.icon = image;
      icon!.setTooltip('Music Time');
      icon!.addListener((event) {
        if (event is tray.TrayIconClickedEvent ||
            event is tray.TrayIconDoubleClickedEvent) {
          unawaited(show());
        }
      });
      menu = tray.Menu.create();
      if (menu == null) throw StateError('Menu indisponível');
      addMenu('Abrir Music Time', show);
      playItem = addMenu('Reproduzir/Pausar', controller.toggle);
      addMenu('Anterior', controller.previous);
      addMenu('Próxima', controller.next);
      menu!.addSeparator();
      addMenu('Sair', exit);
      icon!.setContextMenu(menu);
      icon!.setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked);
      icon!.setVisible(true);
      await windowManager.setPreventClose(true);
      await log('tray_ready');
    } catch (_) {
      icon?.dispose();
      icon = null;
      await windowManager.setPreventClose(false);
      await log('tray_unavailable');
      onError('Bandeja indisponível; fechar a janela encerrará o aplicativo.');
    }
    try {
      await session.setWindowsAppUserModelId(
        validation ? 'MusicTime.Desktop.Validation' : 'MusicTime.Desktop',
      );
      await session.activate();
      session.setActionHandler(
        onPlay: () {
          unawaited(log('smtc_play'));
          if (!controller.playing) unawaited(controller.toggle());
        },
        onPause: () {
          unawaited(log('smtc_pause'));
          if (controller.playing) unawaited(controller.toggle());
        },
        onSkipToNext: () => unawaited(controller.next()),
        onSkipToPrevious: () => unawaited(controller.previous()),
        onSeekTo: (position) => unawaited(controller.seek(position)),
        onShuffle: controller.toggleShuffle,
        onRepeat: controller.cycleRepeat,
      );
      _mediaReady = true;
      await log('smtc_ready');
      if (validation) {
        unawaited(validateVault());
        _validationTimer = Timer(const Duration(seconds: 12), () async {
          if (_disposed || _exiting) return;
          final player = controller.player;
          final id = controller.current?.id;
          final index = controller.queueIndex;
          final volume = controller.volume;
          var preserved = id != null && controller.playing;
          for (final style in [
            'classic',
            'vinyl',
            'minimal',
            'cover_only',
            'lyrics_only',
          ]) {
            await settings.updateVisual('style', style);
            await Future<void>.delayed(const Duration(milliseconds: 150));
            preserved =
                preserved &&
                identical(player, controller.player) &&
                controller.current?.id == id &&
                controller.queueIndex == index &&
                controller.volume == volume &&
                controller.playing &&
                controller.error == null;
          }
          await log(
            preserved ? 'styles_session_preserved' : 'styles_session_failed',
          );
          var placementPreserved = true;
          for (final maximized in [false, true]) {
            if (_disposed || _exiting) return;
            if (maximized) {
              await windowManager.maximize();
            } else {
              await windowManager.unmaximize();
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
            final before = await windowManager.getBounds();
            await hide();
            await Future<void>.delayed(const Duration(milliseconds: 250));
            await show();
            await Future<void>.delayed(const Duration(milliseconds: 250));
            final after = await windowManager.getBounds();
            placementPreserved =
                placementPreserved &&
                await windowManager.isMaximized() == maximized &&
                (before.width - after.width).abs() <= 1 &&
                (before.height - after.height).abs() <= 1;
          }
          await log(
            placementPreserved
                ? 'window_placement_preserved'
                : 'window_placement_failed',
          );
        });
      }
      controller.addListener(changed);
      changed();
    } catch (_) {
      await log('smtc_unavailable');
      onError('Os controles de mídia do Windows não puderam ser ativados.');
    }
  }

  Future<void> validateVault() async {
    const vault = SystemVault();
    final value = secureRandomString();
    try {
      await vault
          .write('validation.self_test', value)
          .timeout(const Duration(seconds: 3));
      final read = await vault
          .read('validation.self_test')
          .timeout(const Duration(seconds: 3));
      await log(read == value ? 'vault_ready' : 'vault_unavailable');
    } catch (_) {
      await log('vault_unavailable');
    } finally {
      try {
        await vault.delete('validation.self_test');
      } catch (_) {}
    }
  }

  tray.MenuItem? addMenu(String title, Future<void> Function() action) {
    final item = tray.MenuItem.createWithLabelAndType(
      title,
      tray.MenuItemType.normal,
    );
    item?.addListener((event) {
      if (event is tray.MenuItemClickedEvent) unawaited(action());
    });
    menu?.addItem(item);
    return item;
  }

  Future<void> show() async {
    await showTrayWindow();
    unawaited(log('window_restored'));
  }

  Future<void> hide() async {
    if (icon == null) return;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
    unawaited(log('window_hidden_tray'));
  }

  Future<void> exit() => _exit.exit();

  Future<void> _releaseMedia() async {
    controller.removeListener(changed);
    _mediaReleased = true;
    try {
      await controller.player.pause().timeout(const Duration(seconds: 2));
      await log('exit_paused').timeout(const Duration(seconds: 1));
    } catch (_) {}
    if (_mediaReady) {
      try {
        await session
            .setBackgroundKeepAlive(false)
            .timeout(const Duration(seconds: 2));
        await session.deactivate().timeout(const Duration(seconds: 2));
        await log('exit_media_deactivated').timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
  }

  Future<void> _close() async {
    try {
      await windowManager
          .setPreventClose(false)
          .timeout(const Duration(seconds: 2));
      // Log before close: destroying the window can end the process immediately.
      await log('exit_close_sent').timeout(const Duration(seconds: 1));
      await windowManager.close().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Native close can itself stop responding; destroy only after confirmed exit.
      await windowManager.destroy().timeout(const Duration(seconds: 2));
    }
  }

  @override
  void onWindowClose() {
    if (_exiting) return;
    if ((settings.closeToTray) && icon != null) {
      unawaited(hide());
    } else {
      unawaited(exit());
    }
  }

  @override
  void onWindowMinimize() {
    if ((settings.minimizeToTray) && icon != null) {
      unawaited(hide());
    }
  }

  @override
  void onWindowFocus() {
    unawaited(windowManager.setSkipTaskbar(false));
  }

  void changed() {
    if (_disposed || _exiting || !_mediaReady) return;
    playItem?.label = controller.playing ? 'Pausar' : 'Reproduzir';
    unawaited(sync());
  }

  Future<void> sync() async {
    if (_syncing || _disposed) return;
    final track = controller.current;
    final artworkHash = track?.cover == null
        ? 'fallback'
        : sha256.convert(track!.cover!).toString();
    final state =
        '${track?.id}|$artworkHash|${controller.playing}|${controller.buffering}|${controller.position.inSeconds}|${controller.duration.inSeconds}|${controller.shuffle}|${controller.repeat}';
    if (state == lastState) return;
    _syncing = true;
    try {
      final platform = media.FlutterMediaSessionPlatform.instance;
      if (track != null) {
        final metadata =
            '${track.id}|${controller.duration.inMilliseconds}|$artworkHash';
        if (metadata != lastMetadata) {
          String? artwork;
          {
            final support = await getApplicationSupportDirectory();
            await support.create(recursive: true);
            final bytes =
                track.cover ??
                (await rootBundle.load('assets/branding/icon.png')).buffer
                    .asUint8List();
            final extension =
                bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8
                ? 'jpg'
                : 'png';
            final cover = File(
              path.join(
                support.path,
                '${sha256.convert(utf8.encode(track.id))}-$artworkHash.$extension',
              ),
            );
            if (!await cover.exists()) {
              await cover.writeAsBytes(bytes, flush: true);
            }
            artwork = cover.path;
          }
          await platform.updateMetadata(
            media.MediaMetadata(
              title: track.title,
              artist: track.artist,
              album: track.album,
              artworkUri: artwork,
              duration: controller.duration,
            ),
          );
          lastMetadata = metadata;
        }
        await platform.updateAvailableActions({
          media.MediaAction.play,
          media.MediaAction.pause,
          if (controller.nextIndex >= 0) media.MediaAction.skipToNext,
          if (controller.canGoPrevious) media.MediaAction.skipToPrevious,
          media.MediaAction.seekTo,
        });
      } else {
        await platform.updateAvailableActions({});
      }
      await platform.updatePlaybackState(
        media.PlaybackState(
          status: track == null
              ? media.PlaybackStatus.idle
              : controller.buffering
              ? media.PlaybackStatus.buffering
              : controller.playing
              ? media.PlaybackStatus.playing
              : media.PlaybackStatus.paused,
          position: controller.position,
          repeatMode: controller.repeat == PlaybackRepeat.track
              ? media.MediaRepeatMode.one
              : controller.repeat == PlaybackRepeat.queue
              ? media.MediaRepeatMode.all
              : media.MediaRepeatMode.none,
          shuffleModeEnabled: controller.shuffle,
        ),
      );
      if (!_exiting) await session.setBackgroundKeepAlive(controller.playing);
      lastState = state;
    } catch (_) {
      await log('smtc_update_failed');
      onError('Não foi possível atualizar os controles de mídia do Windows.');
    } finally {
      _syncing = false;
    }
  }

  void dispose() {
    _disposed = true;
    systemAccent.dispose();
    _validationTimer?.cancel();
    controller.removeListener(changed);
    windowManager.removeListener(this);
    session.clearActionHandler();
    icon?.dispose();
    menu?.dispose();
  }
}
