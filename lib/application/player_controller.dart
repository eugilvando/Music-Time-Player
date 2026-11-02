import 'dart:async';
import 'dart:io';

import 'fade_analysis.dart';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../domain/track.dart';
import '../domain/scrobble_policy.dart';
import '../domain/queue_navigation.dart';
import '../domain/ports.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({this.onListening, this.resolver, this.coverLoader}) {
    _bindPlayer();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _settle();
      _updateClock();
      _notify();
    });
  }

  void _bindPlayer() {
    final boundPlayer = player;
    _subscriptions.add(
      player.stream.playing.listen((value) {
        if (_disposed || !identical(player, boundPlayer)) return;
        _settle();
        if (!value) _generation++;
        playing = value;
        if (!value && _tail != null) unawaited(_finishFade());
        _updateClock();
        _notify();
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((value) {
        if (_disposed || !identical(player, boundPlayer)) return;
        _settle();
        buffering = value;
        _updateClock();
        _notify();
      }),
    );
    _subscriptions.add(
      player.stream.position.listen((value) {
        if (_disposed || !identical(player, boundPlayer)) return;
        position = value;
        _checkTransition();
        _notify();
      }),
    );
    _subscriptions.add(
      player.stream.duration.listen((value) {
        if (_disposed || !identical(player, boundPlayer)) return;
        duration = value;
        session?.duration = value;
        _notify();
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((value) {
        if (_disposed || !identical(player, boundPlayer)) return;
        if (value && !opening) {
          _settle();
          playing = false;
          completed = true;
          _notify();
          unawaited(next(automatic: true));
        }
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((_) {
        if (_disposed || !identical(player, boundPlayer)) return;
        _settle();
        playing = false;
        error = 'Não foi possível reproduzir este arquivo.';
        _notify();
      }),
    );
  }

  Future<void> _configureNative(NativePlayer native) async {
    // Lyrics are handled by Music Time, without native sidecar loading.
    await native.setProperty('sub-auto', 'no');
    if (Platform.isWindows) {
      // Restrict the backend list (no trailing comma): the bundled OpenAL
      // fallback can pass a null renderer string to strstr and crash the
      // process when opening 32-bit audio without a valid OpenAL context.
      // WASAPI failure must surface as a playback error, not select OpenAL.
      await native.setProperty('ao', 'wasapi');
    }
  }

  final void Function(ListeningSession)? onListening;
  final MediaSourceResolver? resolver;
  final Future<Uint8List?> Function(String)? coverLoader;
  Future<List<Track>> Function(Track, List<Track>)? continuous;
  bool extending = false;
  Player player = Player();
  int fadeSeconds = 0;
  String fadeMode = 'fixed';
  Player? _tail;
  ListeningSession? _tailSession;
  final Stopwatch _tailClock = Stopwatch();
  bool get transitioning => _tail != null;
  double _fadeFraction = 1;
  String? _activeFadeMode;

  void _settleTail() {
    final tail = _tailSession;
    if (tail == null) return;
    _tailClock.stop();
    tail.addListening(_tailClock.elapsed);
    _tailClock.reset();
    onListening?.call(tail);
    if (_tail?.state.playing == true && _tail?.state.buffering == false) {
      _tailClock.start();
    }
  }

  int _generation = 0;
  bool _preparing = false;
  int? _attemptedKey;
  bool _eqEnabled = false;
  List<double> _eqGains = const [0, 0, 0, 0, 0];

  void _checkTransition() {
    if (fadeSeconds <= 0 ||
        !playing ||
        opening ||
        buffering ||
        seeking ||
        _disposed ||
        _preparing ||
        _tail != null ||
        repeat == PlaybackRepeat.track ||
        queueIndex < 0 ||
        queueIndex + 1 >= queue.length ||
        duration.inMilliseconds < fadeSeconds * 2000 ||
        _attemptedKey == queueKeys[queueIndex]) {
      return;
    }
    final remaining = duration - position;
    if (remaining.inMilliseconds < 400 || remaining.inSeconds >= fadeSeconds) {
      return;
    }
    final next = queue[queueIndex + 1];
    if (fadeMode == 'mix' &&
        (next.localPath == null || current?.localPath == null)) {
      return;
    }
    final sequentialAlbum =
        !shuffle &&
        current!.album.trim().isNotEmpty &&
        current!.album == next.album &&
        (current!.albumArtist.isEmpty
                ? current!.artist
                : current!.albumArtist) ==
            (next.albumArtist.isEmpty ? next.artist : next.albumArtist);
    if (sequentialAlbum) return;
    _attemptedKey = queueKeys[queueIndex];
    unawaited(_overlap(next, queueKeys[queueIndex + 1], _generation));
  }

  Future<void> _overlap(Track next, int nextKey, int generation) async {
    _preparing = true;
    Player? incoming;
    try {
      final outgoingKey = queueKeys[queueIndex];
      final staged = Player();
      incoming = staged;
      await staged.setVolume(0);
      if (staged.platform is NativePlayer) {
        await _configureNative(staged.platform as NativePlayer);
      }
      final source = resolver == null
          ? Uri.file(next.localPath!)
          : await resolver!.resolve(next);
      final headers = resolver == null
          ? <String, String>{}
          : await mediaHeaders(resolver!, next, source);
      await staged.open(
        Media(source.toString(), httpHeaders: headers),
        play: false,
      );
      if (staged.state.duration <= Duration.zero) {
        await staged.stream.duration
            .firstWhere((value) => value > Duration.zero)
            .timeout(const Duration(seconds: 3));
      }
      final mode = fadeMode;
      bool valid() =>
          generation == _generation &&
          !_disposed &&
          playing &&
          !opening &&
          !seeking &&
          fadeSeconds > 0 &&
          queueIndex >= 0 &&
          queueKeys[queueIndex] == outgoingKey &&
          queueIndex + 1 < queueKeys.length &&
          queueKeys[queueIndex + 1] == nextKey &&
          repeat != PlaybackRepeat.track &&
          fadeMode == mode;
      if (!valid()) return;
      if (mode != 'fixed' &&
          current?.localPath != null &&
          next.localPath != null) {
        final window = await smartOverlapMs(
          current!.localPath!,
          next.localPath!,
          fadeSeconds,
          mixOnly: mode == 'mix',
        );
        if (!valid() || window == 0 || (window == null && mode == 'mix')) {
          return;
        }
        if (window != null) {
          while (valid() && (duration - position).inMilliseconds > window) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
      }
      if (!valid()) return;
      if (_eqEnabled) await _applyEqualizer(staged, true, _eqGains);
      final milliseconds = (duration - position).inMilliseconds;
      if (!valid() || milliseconds < 250) return;
      if (mode == 'mix' && _eqEnabled) return;
      if (mode == 'mix') await staged.setVolume(volume);
      await staged.play();
      if (!valid()) return;
      final outgoing = player;
      _settle();
      for (final sub in _subscriptions) {
        unawaited(sub.cancel());
      }
      _subscriptions.clear();
      player = staged;
      incoming = null;
      _tail = outgoing;
      _tailSession = session;
      _tailClock
        ..reset()
        ..start();
      _activeFadeMode = mode;
      _fadeFraction = mode == 'mix' ? 1 : 0;
      current = next;
      queueIndex++;
      position = staged.state.position;
      duration = staged.state.duration;
      completed = false;
      playing = true;
      buffering = staged.state.buffering;
      session = ListeningSession(next, DateTime.now().toUtc())
        ..duration = duration;
      _bindPlayer();
      _updateClock();
      _notify();
      final elapsed = Stopwatch()..start();
      while (identical(_tail, outgoing) && !_disposed) {
        final fraction = (elapsed.elapsedMilliseconds / milliseconds).clamp(
          0.0,
          1.0,
        );
        _fadeFraction = fraction;
        _settleTail();
        if (mode != 'mix') {
          await Future.wait([
            staged.setVolume(volume * fraction),
            outgoing.setVolume(volume * (1 - fraction)),
          ]);
        }
        if (fraction >= 1) break;
        await Future<void>.delayed(const Duration(milliseconds: 45));
      }
    } catch (_) {
      // A failed preload leaves the ordinary end-of-track advance available.
    } finally {
      if (incoming != null) await incoming.dispose();
      if (_tail != null) await _finishFade();
      _preparing = false;
    }
  }

  Future<void> _finishFade() async {
    _generation++;
    _settleTail();
    _tailClock.stop();
    _tailSession = null;
    _activeFadeMode = null;
    _fadeFraction = 1;
    final tail = _tail;
    _tail = null;
    if (tail != null) {
      await tail.dispose();
      if (!_disposed) await player.setVolume(volume);
    }
  }

  static const equalizerFrequencies = [60, 230, 910, 3600, 14000];
  Future<void> setEqualizer(bool enabled, List<double> gains) async {
    await _finishFade();
    await _applyEqualizer(player, enabled, gains);
    _eqEnabled = enabled;
    _eqGains = List.of(gains);
  }

  Future<void> _applyEqualizer(
    Player player,
    bool enabled,
    List<double> gains,
  ) async {
    if (player.platform is! NativePlayer) {
      throw UnsupportedError('Equalizador indisponível');
    }
    if (gains.length != equalizerFrequencies.length ||
        gains.any((v) => !v.isFinite || v < -12 || v > 12)) {
      throw ArgumentError('Ganhos inválidos');
    }
    final boost = gains.fold<double>(0, (a, b) => a + (b > 0 ? b : 0));
    final chain = [
      for (var i = 0; i < gains.length; i++)
        'equalizer=f=${equalizerFrequencies[i]}:t=o:w=1:r=f32:g=${gains[i]}',
    ].join(',');
    final native = player.platform as NativePlayer;
    // The bundled FFmpeg omits volume & aresample. Convert in mpv before
    // entering lavfi; 48 kHz also keeps all five bands below Nyquist.
    // replaygain-fallback is mpv's native dB gain when replaygain is off.
    await native.setProperty('replaygain-fallback', enabled ? '-$boost' : '0');
    await native.setProperty(
      'af',
      enabled ? 'format=format=floatp:srate=48000,lavfi=[$chain]' : '',
    );
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Stopwatch _clock = Stopwatch();
  late final Timer _timer;
  final List<Track> queue = [];
  String? queueTitle;
  final queueKeys = <int>[];
  final _originalQueueKeys = <int>[];
  List<int> get originalQueueOrder {
    final positions = {
      for (var i = 0; i < queueKeys.length; i++) queueKeys[i]: i,
    };
    final ordered = _originalQueueKeys.where(positions.containsKey).toList();
    final known = ordered.toSet();
    ordered.addAll(queueKeys.where((key) => !known.contains(key)));
    return ordered.map((key) => positions[key]!).toList();
  }

  void restoreShuffleSnapshot(Map<String, dynamic> snapshot) {
    final ids = snapshot['queue'], order = snapshot['order'];
    if (!shuffle ||
        ids is! List ||
        order is! List ||
        !listEquals(ids, queue.map((t) => t.id).toList()) ||
        order.length != queue.length ||
        order.any((i) => i is! int || i < 0 || i >= queue.length) ||
        order.toSet().length != queue.length) {
      return;
    }
    _originalQueueKeys
      ..clear()
      ..addAll(order.cast<int>().map((i) => queueKeys[i]));
  }

  int _nextQueueKey = 0;
  bool get canGoPrevious => queueIndex > 0;
  int queueIndex = -1;
  List<Track> upcoming(int count) {
    final values = queue.skip(queueIndex + 1).take(count).toList();
    if (repeat == PlaybackRepeat.queue && values.length < count) {
      values.addAll(queue.take(count - values.length));
    }
    return values;
  }

  PlaybackRepeat repeat = PlaybackRepeat.off;
  bool shuffle = false;
  double volume = 100;
  double volumeBeforeMute = 100;
  Future<void> toggleMute() async {
    if (volume > 0) {
      volumeBeforeMute = volume;
      await setVolume(0);
    } else {
      await setVolume(volumeBeforeMute > 0 ? volumeBeforeMute : 100);
    }
  }

  Track? current;
  ListeningSession? session;
  bool playing = false, buffering = false, opening = false;
  bool completed = false, seeking = false, _disposed = false;
  bool _nativeConfigured = false;
  Duration position = Duration.zero, duration = Duration.zero;
  String? error;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _settle() {
    _clock.stop();
    session?.addListening(_clock.elapsed);
    if (session != null) {
      onListening?.call(session!);
    }
    _clock.reset();
  }

  void _updateClock() {
    if (playing && !buffering && !opening && !seeking && !_disposed) {
      _clock.start();
    }
  }

  /// Apply catalog changes without reopening audio or creating a new audition.
  Future<void> refreshMetadata(List<Track> tracks) async {
    if (_disposed) return;
    final updated = {for (final track in tracks) track.id: track};
    for (var i = 0; i < queue.length; i++) {
      queue[i] = updated[queue[i].id] ?? queue[i];
    }
    final active = current;
    final metadata = active == null ? null : updated[active.id];
    if (metadata == null) {
      _notify();
      return;
    }
    Track value = metadata;
    if (value.cover == null && value.hasArtwork && coverLoader != null) {
      try {
        value = value.withCover(await coverLoader!(value.id));
      } catch (_) {
        // Optional cover failure does not interrupt the current music.
      }
    }
    if (_disposed || !identical(current, active)) return;
    current = value;
    final listening = session;
    if (listening != null && listening.track.id == value.id) {
      session = ListeningSession(value, listening.startedAt)
        ..listened = listening.listened
        ..duration = listening.duration
        ..claimed = listening.claimed;
    }
    _notify();
  }

  Future<void> open(
    Track track, {
    bool play = true,
    Duration start = Duration.zero,
  }) async {
    if (opening || _disposed) return;
    opening = true;
    await _finishFade();
    _attemptedKey = null;
    _settle();
    playing = false;
    completed = false;
    if (track.cover == null && track.hasArtwork && coverLoader != null) {
      try {
        track = track.withCover(await coverLoader!(track.id));
      } catch (_) {
        /* Artwork failure must not prevent audio playback. */
      }
      if (_disposed) {
        opening = false;
        return;
      }
    }
    current = track;
    session = play ? ListeningSession(track, DateTime.now().toUtc()) : null;
    error = null;
    position = Duration.zero;
    duration = Duration.zero;
    _notify();
    try {
      if (!_nativeConfigured && player.platform is NativePlayer) {
        await _configureNative(player.platform as NativePlayer);
        _nativeConfigured = true;
      }
      final source = resolver != null
          ? await resolver!.resolve(track)
          : Uri.file(track.localPath!);
      final headers = resolver == null
          ? <String, String>{}
          : await mediaHeaders(resolver!, track, source);
      await player.open(
        Media(source.toString(), httpHeaders: headers),
        play: false,
      );
      if (start > Duration.zero) await player.seek(start);
      if (play && !_disposed) await player.play();
    } on MediaSourceFailure catch (failure) {
      error = failure.message;
    } catch (_) {
      error = 'Não foi possível abrir este arquivo.';
    } finally {
      opening = false;
      _updateClock();
      _notify();
    }
  }

  Future<void> playQueue(List<Track> tracks, int index, {String? title}) async {
    if (opening || index < 0 || index >= tracks.length) return;
    queueTitle = title?.trim().isNotEmpty == true ? title!.trim() : null;
    final sameOrder = listEquals(tracks, queue);
    final copy = List<Track>.of(tracks);
    queue
      ..clear()
      ..addAll(copy);
    queueIndex = index;
    if (!sameOrder) {
      queueKeys
        ..clear()
        ..addAll(List.generate(queue.length, (_) => _nextQueueKey++));
      _originalQueueKeys.clear();
    }
    if (shuffle && !sameOrder) shuffleQueue();
    await open(queue[queueIndex]);
  }

  Future<void> restore(
    List<Track> tracks,
    int index,
    Duration position, {
    String? title,
  }) async {
    if (tracks.isEmpty) return;
    queueTitle = title;
    queue
      ..clear()
      ..addAll(tracks);
    queueIndex = index.clamp(0, tracks.length - 1);
    queueKeys
      ..clear()
      ..addAll(List.generate(queue.length, (_) => _nextQueueKey++));
    _originalQueueKeys
      ..clear()
      ..addAll(queueKeys);
    await open(queue[queueIndex], play: false, start: position);
  }

  int get nextIndex => nextQueueIndex(
    current: queueIndex,
    length: queue.length,
    repeat: repeat,
    shuffle: false,
  );
  Future<void> next({bool automatic = false}) async {
    if (opening || extending) return;
    var index = automatic && repeat == PlaybackRepeat.track
        ? queueIndex
        : nextQueueIndex(
            current: queueIndex,
            length: queue.length,
            repeat: repeat,
            shuffle: false,
            automatic: automatic,
          );
    if (index < 0 &&
        automatic &&
        repeat == PlaybackRepeat.off &&
        continuous != null &&
        current != null) {
      final active = current;
      final recommend = continuous!;
      final previousIndex = queueIndex;
      final keys = List<int>.of(queueKeys);
      extending = true;
      try {
        final suggested = await recommend(current!, List.of(queue));
        if (_disposed ||
            !identical(continuous, recommend) ||
            !identical(current, active) ||
            queueIndex != previousIndex ||
            !listEquals(keys, queueKeys)) {
          return;
        }
        if (suggested.isNotEmpty) {
          index = queue.length;
          queue.addAll(suggested);
          queueKeys.addAll(suggested.map((_) => _nextQueueKey++));
        }
      } catch (_) {
        /* Optional recommendations do not alter the existing queue on failure. */
      } finally {
        extending = false;
      }
    }
    if (index < 0) return;
    queueIndex = index;
    await open(queue[queueIndex]);
  }

  void shuffleQueue() {
    if (queue.isEmpty) return;
    _originalQueueKeys
      ..clear()
      ..addAll(queueKeys);
    final order = shuffledQueueOrder(queue.length, queueIndex);
    final tracks = [for (final i in order) queue[i]];
    final keys = [for (final i in order) queueKeys[i]];
    queue
      ..clear()
      ..addAll(tracks);
    queueKeys
      ..clear()
      ..addAll(keys);
    queueIndex = 0;
  }

  void toggleShuffle() {
    if (opening) return;
    shuffle = !shuffle;
    if (shuffle) {
      shuffleQueue();
    } else if (queue.isNotEmpty) {
      final currentKey = queueKeys[queueIndex];
      final order = originalQueueOrder;
      final tracks = [for (final i in order) queue[i]];
      final keys = [for (final i in order) queueKeys[i]];
      queue
        ..clear()
        ..addAll(tracks);
      queueKeys
        ..clear()
        ..addAll(keys);
      queueIndex = queueKeys.indexOf(currentKey);
      _originalQueueKeys.clear();
    }
    _notify();
  }

  void cycleRepeat() {
    repeat = PlaybackRepeat
        .values[(repeat.index + 1) % PlaybackRepeat.values.length];
    _notify();
  }

  Future<void> setVolume(double value) async {
    try {
      volume = value.clamp(0, 100);
      final mixed = _activeFadeMode == 'mix';
      await player.setVolume(
        volume * (_tail == null || mixed ? 1 : _fadeFraction),
      );
      final tail = _tail;
      if (tail != null) {
        await tail.setVolume(volume * (mixed ? 1 : 1 - _fadeFraction));
      }
      _notify();
    } catch (_) {
      error = 'Não foi possível alterar o volume.';
      _notify();
    }
  }

  Future<void> previous() async {
    if (opening) return;
    final index = queueIndex - 1;
    if (index < 0) return;
    queueIndex = index;
    await open(queue[queueIndex]);
  }

  Future<void> enqueue(Track track, {bool asNext = false}) async {
    if (opening) return;
    if (queue.isEmpty) {
      queue.add(track);
      queueKeys.add(_nextQueueKey++);
      queueIndex = 0;
      await open(track, play: false);
      return;
    }
    final key = _nextQueueKey++;
    if (shuffle) {
      final baseline = originalQueueOrder.map((i) => queueKeys[i]).toList();
      _originalQueueKeys
        ..clear()
        ..addAll(baseline);
      final current = _originalQueueKeys.indexOf(queueKeys[queueIndex]);
      _originalQueueKeys.insert(
        asNext && current >= 0 ? current + 1 : _originalQueueKeys.length,
        key,
      );
    }
    queueKeys.insert(asNext ? queueIndex + 1 : queue.length, key);
    queue.insert(asNext ? queueIndex + 1 : queue.length, track);
    _notify();
  }

  Future<void> insertTracks(List<Track> items, int at) async {
    if (opening || items.isEmpty) return;
    final wasEmpty = queue.isEmpty;
    final index = at.clamp(0, queue.length);
    final keys = items.map((_) => _nextQueueKey++).toList();
    if (shuffle) {
      final baseline = originalQueueOrder.map((i) => queueKeys[i]).toList();
      baseline.insertAll(
        index == queue.length
            ? baseline.length
            : baseline.indexOf(queueKeys[index]),
        keys,
      );
      _originalQueueKeys
        ..clear()
        ..addAll(baseline);
    }
    queue.insertAll(index, items);
    queueKeys.insertAll(index, keys);
    if (wasEmpty) {
      queueIndex = 0;
      await open(queue.first, play: false);
    } else {
      if (index <= queueIndex) queueIndex += items.length;
      _notify();
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (opening || oldIndex == newIndex) return;
    final track = queue.removeAt(oldIndex);
    final key = queueKeys.removeAt(oldIndex);
    queueKeys.insert(newIndex, key);
    if (queueIndex == oldIndex) {
      queueIndex = newIndex;
    } else {
      if (oldIndex < queueIndex) queueIndex--;
      if (newIndex <= queueIndex) queueIndex++;
    }
    queue.insert(newIndex, track);
    _notify();
  }

  Future<void> removeQueueEntry(int index) async {
    if (opening) return;
    final active = index == queueIndex, wasPlaying = playing;
    queue.removeAt(index);
    queueKeys.removeAt(index);
    if (queue.isEmpty) {
      await clearQueue();
      return;
    }
    if (index < queueIndex) queueIndex--;
    if (active) {
      queueIndex = queueIndex.clamp(0, queue.length - 1);
      await open(queue[queueIndex], play: wasPlaying);
    }
    _notify();
  }

  Future<void> clearQueue() async {
    if (opening) return;
    _settle();
    await _finishFade();
    await player.stop();
    queue.clear();
    queueTitle = null;
    queueKeys.clear();
    _originalQueueKeys.clear();
    queueIndex = -1;
    current = null;
    session = null;
    position = Duration.zero;
    duration = Duration.zero;
    playing = false;
    _notify();
  }

  Future<void> removeSourceTracks(Set<String> ids) async {
    if (opening || extending || playing) {
      throw StateError('Pause playback before removing this source.');
    }
    final remaining = queue.where((t) => !ids.contains(t.id)).toList();
    final active = current;
    if (remaining.length == queue.length) return;
    if (active == null || ids.contains(active.id)) {
      final title = queueTitle;
      final remainingKeys = [
        for (var i = 0; i < queue.length; i++)
          if (!ids.contains(queue[i].id)) queueKeys[i],
      ];
      final original = [
        for (final i in originalQueueOrder)
          if (!ids.contains(queue[i].id)) remainingKeys.indexOf(queueKeys[i]),
      ];
      await clearQueue();
      if (remaining.isNotEmpty) {
        await restore(remaining, 0, Duration.zero, title: title);
        restoreShuffleSnapshot({
          'queue': remaining.map((t) => t.id).toList(),
          'order': original,
        });
      }
      return;
    }
    final before = queue
        .take(queueIndex)
        .where((t) => !ids.contains(t.id))
        .length;
    final keys = [
      for (var i = 0; i < queue.length; i++)
        if (!ids.contains(queue[i].id)) queueKeys[i],
    ];
    queue
      ..clear()
      ..addAll(remaining);
    queueKeys
      ..clear()
      ..addAll(keys);
    queueIndex = before;
    _notify();
  }

  Future<void> toggle() async {
    if (current == null || opening) return;
    await _finishFade();
    if (completed) {
      await open(current!);
      return;
    }
    session ??= ListeningSession(current!, DateTime.now().toUtc())
      ..duration = duration;
    try {
      await player.playOrPause();
    } catch (_) {
      error = 'Falha ao controlar reprodução.';
      _notify();
    }
  }

  Future<void> seek(Duration target) async {
    if (opening || seeking || current == null) return;
    seeking = true;
    await _finishFade();
    _settle();
    try {
      await player.seek(target);
    } catch (_) {
      error = 'Falha ao avançar a faixa.';
    } finally {
      seeking = false;
      _updateClock();
      _notify();
    }
  }

  @override
  void dispose() {
    _settle();
    _disposed = true;
    unawaited(_finishFade());
    _timer.cancel();
    _clock.stop();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }
}
