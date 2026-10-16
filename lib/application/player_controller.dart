import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../domain/track.dart';
import '../domain/scrobble_policy.dart';
import '../domain/queue_navigation.dart';
import '../domain/ports.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({this.onListening, this.resolver, this.coverLoader}) {
    _subscriptions.add(
      player.stream.playing.listen((value) {
        _settle();
        playing = value;
        _updateClock();
        _notify();
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((value) {
        _settle();
        buffering = value;
        _updateClock();
        _notify();
      }),
    );
    _subscriptions.add(
      player.stream.position.listen((value) {
        position = value;
        _notify();
      }),
    );
    _subscriptions.add(
      player.stream.duration.listen((value) {
        duration = value;
        session?.duration = value;
        _notify();
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((value) {
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
        _settle();
        playing = false;
        error = 'Não foi possível reproduzir este arquivo.';
        _notify();
      }),
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _settle();
      _updateClock();
      _notify();
    });
  }

  final void Function(ListeningSession)? onListening;
  final MediaSourceResolver? resolver;
  final Future<Uint8List?> Function(String)? coverLoader;
  Future<List<Track>> Function(Track, List<Track>)? continuous;
  bool extending = false;
  final Player player = Player();
  static const equalizerFrequencies = [60, 230, 910, 3600, 14000];
  Future<void> setEqualizer(bool enabled, List<double> gains) async {
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
  int _nextQueueKey = 0;
  bool get canGoPrevious => shuffle ? _previous.isNotEmpty : queueIndex > 0;
  int queueIndex = -1;
  final _cycle = ShuffleCycle();
  List<Track> upcoming(int count) {
    if (shuffle) {
      if (_cycle.remaining.isEmpty && repeat == PlaybackRepeat.queue) {
        _cycle.reset(queue.length, queueIndex);
      }
      return _cycle.remaining.take(count).map((i) => queue[i]).toList();
    }
    final values = queue.skip(queueIndex + 1).take(count).toList();
    if (repeat == PlaybackRepeat.queue && values.length < count) {
      values.addAll(queue.take(count - values.length));
    }
    return values;
  }

  final _previous = <int>[];
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
        // Lyrics are parsed by Music Time; libmpv must not autoload sidecar subtitles.
        await (player.platform as NativePlayer).setProperty('sub-auto', 'no');
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
    final copy = List<Track>.of(tracks);
    queue
      ..clear()
      ..addAll(copy);
    queueIndex = index;
    queueKeys
      ..clear()
      ..addAll(List.generate(queue.length, (_) => _nextQueueKey++));
    _cycle.reset(queue.length, queueIndex);
    _previous.clear();
    await open(queue[index]);
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
    _cycle.reset(queue.length, queueIndex);
    _previous.clear();
    await open(queue[queueIndex], play: false, start: position);
  }

  int get nextIndex => shuffle
      ? (_cycle.canAdvance(queue.length, repeat == PlaybackRepeat.queue)
            ? queueIndex
            : -1)
      : nextQueueIndex(
          current: queueIndex,
          length: queue.length,
          repeat: repeat,
          shuffle: false,
        );
  Future<void> next({bool automatic = false}) async {
    if (opening || extending) return;
    var index = automatic && repeat == PlaybackRepeat.track
        ? queueIndex
        : shuffle
        ? _cycle.next(
            queue.length,
            queueIndex,
            repeatAll: repeat == PlaybackRepeat.queue,
          )
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
          _cycle.reset(queue.length, queueIndex);
        }
      } catch (_) {
        /* Optional recommendations do not alter the existing queue on failure. */
      } finally {
        extending = false;
      }
    }
    if (index < 0) return;
    if (index != queueIndex) _previous.add(queueIndex);
    queueIndex = index;
    await open(queue[queueIndex]);
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    _cycle.reset(queue.length, queueIndex);
    _previous.clear();
    _notify();
  }

  void cycleRepeat() {
    repeat = PlaybackRepeat
        .values[(repeat.index + 1) % PlaybackRepeat.values.length];
    _notify();
  }

  Future<void> setVolume(double value) async {
    try {
      await player.setVolume(value.clamp(0, 100));
      volume = value.clamp(0, 100);
      _notify();
    } catch (_) {
      error = 'Não foi possível alterar o volume.';
      _notify();
    }
  }

  Future<void> previous() async {
    if (opening) return;
    final index = shuffle
        ? (_previous.isEmpty ? -1 : _previous.removeLast())
        : queueIndex - 1;
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
      _cycle.reset(queue.length, queueIndex);
      await open(track, play: false);
      return;
    }
    queueKeys.insert(asNext ? queueIndex + 1 : queue.length, _nextQueueKey++);
    queue.insert(asNext ? queueIndex + 1 : queue.length, track);
    _cycle.reset(queue.length, queueIndex);
    _previous.clear();
    _notify();
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
    _cycle.reset(queue.length, queueIndex);
    _previous.clear();
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
    _cycle.reset(queue.length, queueIndex);
    _previous.clear();
    _notify();
  }

  Future<void> clearQueue() async {
    if (opening) return;
    _settle();
    await player.stop();
    queue.clear();
    queueTitle = null;
    queueKeys.clear();
    queueIndex = -1;
    current = null;
    session = null;
    position = Duration.zero;
    duration = Duration.zero;
    playing = false;
    _cycle.reset(0, -1);
    _previous.clear();
    _notify();
  }

  Future<void> toggle() async {
    if (current == null || opening) return;
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
    _timer.cancel();
    _clock.stop();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }
}
