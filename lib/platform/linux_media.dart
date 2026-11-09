import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dbus/dbus.dart';

import '../application/player_controller.dart';
import '../domain/queue_navigation.dart';

/// The session bus remains registered while the application is hidden in tray.
class LinuxMedia extends DBusObject {
  LinuxMedia(this.player, {required this.raise, required this.quit})
    : super(DBusObjectPath('/org/mpris/MediaPlayer2'));
  static const root = 'org.mpris.MediaPlayer2';
  static const playback = '$root.Player';
  final PlayerController player;
  final Future<void> Function() raise, quit;
  DBusClient? bus;
  Directory? artworkDirectory;
  String artwork = '', artworkKey = '';
  String? stoppedTrack;
  bool busy = false, closed = false;
  Map<String, DBusValue> previous = {};

  Future<void> initialize() async {
    artworkDirectory = await Directory.systemTemp.createTemp(
      'music-time-mpris-',
    );
    final connection = DBusClient.session();
    bus = connection;
    try {
      await connection.registerObject(this);
      final result = await connection.requestName(
        '$root.MusicTime.instance$pid',
      );
      if (result != DBusRequestNameReply.primaryOwner) {
        throw StateError('MPRIS name unavailable');
      }
      player.addListener(changed);
      await sync();
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  DBusObjectPath get trackPath => DBusObjectPath(
    player.current == null
        ? '/org/mpris/MediaPlayer2/TrackList/NoTrack'
        : '/org/mpris/MediaPlayer2/track/${sha256.convert(utf8.encode(player.current!.id))}',
  );

  Map<String, DBusValue> properties(String interface) {
    if (interface == root) {
      return {
        'CanQuit': const DBusBoolean(true),
        'CanRaise': const DBusBoolean(true),
        'HasTrackList': const DBusBoolean(false),
        'Identity': const DBusString('Music Time'),
        'DesktopEntry': const DBusString('app.musictime.preview'),
        'SupportedUriSchemes': DBusArray.string([]),
        'SupportedMimeTypes': DBusArray.string([]),
      };
    }
    if (interface != playback) return {};
    final track = player.current;
    return {
      'PlaybackStatus': DBusString(
        track == null || (!player.playing && stoppedTrack == track.id)
            ? 'Stopped'
            : player.playing
            ? 'Playing'
            : 'Paused',
      ),
      'LoopStatus': DBusString(switch (player.repeat) {
        PlaybackRepeat.off => 'None',
        PlaybackRepeat.queue => 'Playlist',
        PlaybackRepeat.track => 'Track',
      }),
      'Rate': const DBusDouble(1),
      'MinimumRate': const DBusDouble(1),
      'MaximumRate': const DBusDouble(1),
      'Shuffle': DBusBoolean(player.shuffle),
      'Volume': DBusDouble(player.volume / 100),
      'Position': DBusInt64(player.position.inMicroseconds),
      'CanControl': const DBusBoolean(true),
      'CanPlay': DBusBoolean(track != null),
      'CanPause': DBusBoolean(track != null),
      'CanSeek': DBusBoolean(track != null && player.duration > Duration.zero),
      'CanGoNext': DBusBoolean(
        player.queueIndex + 1 < player.queue.length ||
            player.repeat == PlaybackRepeat.queue,
      ),
      'CanGoPrevious': DBusBoolean(player.queueIndex > 0 || track != null),
      'Metadata': DBusDict.stringVariant({
        'mpris:trackid': trackPath,
        if (track != null) ...{
          'xesam:title': DBusString(track.title),
          'xesam:artist': DBusArray.string(track.artistNames),
          'xesam:album': DBusString(track.album),
          'mpris:length': DBusInt64(player.duration.inMicroseconds),
          if (artwork.isNotEmpty) 'mpris:artUrl': DBusString(artwork),
        },
      }),
    };
  }

  void changed() {
    unawaited(sync());
  }

  Future<void> sync() async {
    if (closed || busy) return;
    busy = true;
    try {
      do {
        final track = player.current;
        if (player.playing || stoppedTrack != track?.id) stoppedTrack = null;
        final bytes = track?.cover;
        final key =
            '${track?.id}:${bytes == null ? '' : sha256.convert(bytes)}';
        if (key != artworkKey) {
          var uri = '';
          if (bytes != null && artworkDirectory != null) {
            final extension =
                bytes.length > 2 && bytes[0] == 255 && bytes[1] == 216
                ? 'jpg'
                : 'png';
            final file = File(
              '${artworkDirectory!.path}/${sha256.convert(bytes)}.$extension',
            );
            if (!await file.exists()) {
              await file.writeAsBytes(bytes, flush: true);
            }
            uri = file.uri.toString();
          }
          if (closed) return;
          if (!identical(track, player.current)) continue;
          artwork = uri;
          artworkKey = key;
        }
        final values = properties(playback)..remove('Position');
        final changed = <String, DBusValue>{
          for (final e in values.entries)
            if (previous[e.key] != e.value) e.key: e.value,
        };
        if (changed.isNotEmpty && !closed) {
          await emitPropertiesChanged(playback, changedProperties: changed);
        }
        previous = values;
        break;
      } while (!closed);
    } catch (_) {
      // A missing session bus must never interrupt playback.
    } finally {
      busy = false;
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = properties(interface)[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      interface == root || interface == playback
      ? DBusGetAllPropertiesResponse(properties(interface))
      : DBusMethodErrorResponse.unknownInterface();

  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async {
    if (interface != playback) {
      return DBusMethodErrorResponse.propertyReadOnly();
    }
    try {
      if (name == 'Volume' && value is DBusDouble && value.value.isFinite) {
        await player.setVolume((value.value * 100).clamp(0, 100));
      } else if (name == 'Shuffle' && value is DBusBoolean) {
        if (player.shuffle != value.value) player.toggleShuffle();
      } else if (name == 'LoopStatus' &&
          value is DBusString &&
          ['None', 'Playlist', 'Track'].contains(value.value)) {
        final wanted = {
          'None': PlaybackRepeat.off,
          'Playlist': PlaybackRepeat.queue,
          'Track': PlaybackRepeat.track,
        }[value.value];
        for (var i = 0; i < 3 && player.repeat != wanted; i++) {
          player.cycleRepeat();
        }
      } else if (name == 'Rate' && value == const DBusDouble(1)) {
        return DBusMethodSuccessResponse();
      } else {
        return DBusMethodErrorResponse.invalidArgs();
      }
      await sync();
      return DBusMethodSuccessResponse();
    } catch (_) {
      return DBusMethodErrorResponse.failed();
    }
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    try {
      if (methodCall.interface == root && methodCall.values.isEmpty) {
        if (methodCall.name == 'Raise') {
          await raise();
        } else if (methodCall.name == 'Quit') {
          unawaited(
            Future<void>.delayed(const Duration(milliseconds: 100), quit),
          );
        } else {
          return DBusMethodErrorResponse.unknownMethod();
        }
      } else if (methodCall.interface == playback) {
        if (methodCall.name == 'Seek' || methodCall.name == 'SetPosition') {
          final relative = methodCall.name == 'Seek';
          if (methodCall.values.length != (relative ? 1 : 2) ||
              methodCall.values.last is! DBusInt64 ||
              (!relative && methodCall.values.first is! DBusObjectPath)) {
            return DBusMethodErrorResponse.invalidArgs();
          }
          if (!relative && methodCall.values.first != trackPath) {
            return DBusMethodSuccessResponse();
          }
          final us =
              (methodCall.values.last as DBusInt64).value +
              (relative ? player.position.inMicroseconds : 0);
          if (player.current != null &&
              (relative || us >= 0 && us <= player.duration.inMicroseconds)) {
            if (relative && us > player.duration.inMicroseconds) {
              await player.next();
            } else {
              await player.seek(
                Duration(
                  microseconds: us.clamp(0, player.duration.inMicroseconds),
                ),
              );
            }
            await emitSignal(playback, 'Seeked', [
              DBusInt64(player.position.inMicroseconds),
            ]);
          }
        } else {
          if (methodCall.values.isNotEmpty) {
            return DBusMethodErrorResponse.invalidArgs();
          }
          switch (methodCall.name) {
            case 'Next':
              await player.next();
            case 'Previous':
              await player.previous();
            case 'PlayPause':
              stoppedTrack = null;
              await player.toggle();
            case 'Play':
              stoppedTrack = null;
              if (!player.playing) await player.toggle();
            case 'Pause':
              if (player.playing) await player.toggle();
            case 'Stop':
              stoppedTrack = player.current?.id;
              if (player.playing) await player.toggle();
              await player.seek(Duration.zero);
            default:
              return DBusMethodErrorResponse.unknownMethod();
          }
        }
      } else {
        return DBusMethodErrorResponse.unknownInterface();
      }
      await sync();
      return DBusMethodSuccessResponse();
    } catch (_) {
      return DBusMethodErrorResponse.failed();
    }
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
    for (final interface in [root, playback])
      DBusIntrospectInterface(
        interface,
        properties: [
          for (final e in properties(interface).entries)
            DBusIntrospectProperty(
              e.key,
              e.value.signature,
              access:
                  interface == playback &&
                      [
                        'Volume',
                        'Shuffle',
                        'LoopStatus',
                        'Rate',
                      ].contains(e.key)
                  ? DBusPropertyAccess.readwrite
                  : DBusPropertyAccess.read,
            ),
        ],
        methods: [
          for (final name
              in interface == root
                  ? ['Raise', 'Quit']
                  : [
                      'Next',
                      'Previous',
                      'Pause',
                      'PlayPause',
                      'Stop',
                      'Play',
                      'Seek',
                      'SetPosition',
                    ])
            DBusIntrospectMethod(
              name,
              args: [
                if (name == 'SetPosition')
                  DBusIntrospectArgument(
                    DBusSignature('o'),
                    DBusArgumentDirection.in_,
                  ),
                if (name == 'Seek' || name == 'SetPosition')
                  DBusIntrospectArgument(
                    DBusSignature('x'),
                    DBusArgumentDirection.in_,
                  ),
              ],
            ),
        ],
        signals: interface == playback
            ? [
                DBusIntrospectSignal(
                  'Seeked',
                  args: [
                    DBusIntrospectArgument(
                      DBusSignature('x'),
                      DBusArgumentDirection.out,
                    ),
                  ],
                ),
              ]
            : [],
      ),
  ];

  Future<void> dispose() async {
    if (closed) return;
    closed = true;
    player.removeListener(changed);
    await bus?.close();
    final directory = artworkDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
