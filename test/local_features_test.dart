import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/queue_navigation.dart';
import 'package:music_time/domain/history_policy.dart';
import 'package:music_time/domain/scrobble_policy.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/local_metadata.dart';

void main() {
  test('repetição diferencia fim automático de próxima manual', () {
    expect(
      nextQueueIndex(
        current: 1,
        length: 2,
        repeat: PlaybackRepeat.off,
        shuffle: false,
      ),
      -1,
    );
    expect(
      nextQueueIndex(
        current: 1,
        length: 2,
        repeat: PlaybackRepeat.queue,
        shuffle: false,
      ),
      0,
    );
    expect(
      nextQueueIndex(
        current: 0,
        length: 2,
        repeat: PlaybackRepeat.track,
        shuffle: false,
        automatic: true,
      ),
      0,
    );
    expect(
      nextQueueIndex(
        current: 0,
        length: 2,
        repeat: PlaybackRepeat.track,
        shuffle: false,
      ),
      1,
    );
    expect(
      nextQueueIndex(
        current: -1,
        length: 0,
        repeat: PlaybackRepeat.queue,
        shuffle: true,
      ),
      -1,
    );
    expect(
      nextQueueIndex(
        current: 1,
        length: 4,
        repeat: PlaybackRepeat.off,
        shuffle: true,
        random: Random(1),
      ),
      isNot(1),
    );
  });
  test('histórico tem regra própria sem exigir tags Last.fm', () {
    final session = ListeningSession(
      const Track(
        id: 'a',
        title: 'a',
        artist: 'Artista desconhecido',
        duration: Duration(seconds: 120),
      ),
      DateTime.utc(2026),
    );
    session.addListening(const Duration(seconds: 29));
    expect(countsForHistory(session), isFalse);
    session.addListening(const Duration(seconds: 1));
    expect(countsForHistory(session), isTrue);
    expect(session.eligible, isFalse);
  });
  test('álbuns usam artista de álbum, título e ano', () {
    const a = Track(
      id: 'a',
      title: 'a',
      artist: 'Participante 1',
      album: 'Coletânea',
      albumArtist: 'Vários',
      year: 2020,
    );
    const b = Track(
      id: 'b',
      title: 'b',
      artist: 'Participante 2',
      album: 'Coletânea',
      albumArtist: 'Vários',
      year: 2020,
    );
    const c = Track(
      id: 'c',
      title: 'c',
      artist: 'Outro',
      album: 'Coletânea',
      year: 2020,
    );
    expect(albumKey(a), albumKey(b));
    expect(albumKey(a), isNot(albumKey(c)));
  });
  test('arquivo inválido mantém fallback do nome', () {
    final track = readLocalTracks(['C:/missing/audio-inexistente.mp3']).single;
    expect(track.title, 'audio-inexistente');
    expect(track.artist, 'Artista desconhecido');
  });
  test('shuffle percorre ocorrências sem repetir até terminar o ciclo', () {
    final cycle = ShuffleCycle(random: Random(7));
    cycle.reset(4, 2);
    final visited = <int>[];
    var current = 2;
    for (var i = 0; i < 3; i++) {
      current = cycle.next(4, current, repeatAll: false);
      visited.add(current);
    }
    expect(visited.toSet(), {0, 1, 3});
    expect(cycle.next(4, current, repeatAll: false), -1);
    expect(cycle.next(4, current, repeatAll: true), isNot(current));
  });
}
