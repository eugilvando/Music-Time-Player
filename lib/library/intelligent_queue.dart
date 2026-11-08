import 'dart:math';

import '../domain/track.dart';
import 'catalog.dart';

const intelligentQueueModes = {
  'related': 'Gênero',
  'artist': 'Artista',
  'era': 'Era',
  'shuffle': 'Aleatório',
};
const smartFlowModes = {
  'shuffle': 'Aleatório',
  'double': 'Dose dupla',
  'artist': 'Fã do artista',
  'era': 'Da era',
};

bool sameArtist(Track a, Track b) {
  final names = a.artistNames
      .map(artistNameKey)
      .where((n) => n.isNotEmpty)
      .toSet();
  return b.artistNames.map(artistNameKey).any(names.contains);
}

/// Explicit choices keep their influence even after several automatic rounds.
class QueueContext {
  QueueContext(this.tracks, {this.automatic = const {}});
  final List<Track> tracks;
  final Set<int> automatic;
  final artists = <String, double>{};
  final genres = <String, double>{};
  final decades = <int, double>{};

  void analyze() {
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final weight =
          (automatic.contains(i) ? .15 : 1.0) *
          (1 + (i + 1) / max(1, tracks.length));
      for (final artist in track.artistNames.map(artistNameKey).toSet()) {
        if (artist.isNotEmpty) {
          artists.update(artist, (v) => v + weight, ifAbsent: () => weight);
        }
      }
      for (final genre in track.genreNames.map(searchKey).toSet()) {
        if (genre.isNotEmpty) {
          genres.update(genre, (v) => v + weight, ifAbsent: () => weight);
        }
      }
      if (track.year != null && track.year! > 0) {
        decades.update(
          track.year! ~/ 10,
          (v) => v + weight,
          ifAbsent: () => weight,
        );
      }
    }
  }
}

class IntelligentQueueWork {
  const IntelligentQueueWork(
    this.library,
    this.queue, {
    this.automatic = const {},
    this.offline = const {},
    this.offlineOnly = false,
    this.similar = const {},
    this.mode = 'related',
    this.count = 5,
  });
  final List<Track> library, queue;
  final Set<int> automatic;
  final Set<String> offline, similar;
  final bool offlineOnly;
  final String mode;
  final int count;
}

List<Track> prepareIntelligentQueue(IntelligentQueueWork work) =>
    intelligentTracks(work);

List<Track> intelligentTracks(IntelligentQueueWork work, {Random? random}) {
  final context = QueueContext(work.queue, automatic: work.automatic)
    ..analyze();
  final used = work.queue.map((t) => t.id).toSet();
  final similar = work.similar.map(artistNameKey).toSet();
  double score(Track t) {
    final artist = t.artistNames
        .map(artistNameKey)
        .fold(0.0, (v, name) => v + (context.artists[name] ?? 0));
    final genre = t.genreNames
        .map(searchKey)
        .fold(0.0, (v, name) => v + (context.genres[name] ?? 0));
    final era = t.year == null ? 0.0 : (context.decades[t.year! ~/ 10] ?? 0.0);
    final related = t.artistNames.map(artistNameKey).any(similar.contains);
    return switch (work.mode) {
      'artist' => artist,
      'era' =>
        era > 0
            ? era *
                  (related
                      ? 2
                      : artist > 0
                      ? 1.5
                      : 1)
            : 0,
      'shuffle' => 1,
      _ => context.genres.isEmpty ? artist : genre,
    };
  }

  final rng = random ?? Random();
  final ranked = <(Track, double)>[];
  for (final t in work.library) {
    if (t.libraryHidden ||
        used.contains(t.id) ||
        !(work.offlineOnly
            ? work.offline.contains(t.id)
            : t.available || work.offline.contains(t.id))) {
      continue;
    }
    final weight = score(t);
    if (weight <= 0 || !used.add(t.id)) continue;
    // Weighted sampling keeps minority genres/artists represented across rounds.
    ranked.add((t, -log(max(rng.nextDouble(), 1e-12)) / weight));
  }
  ranked.sort((a, b) => a.$2.compareTo(b.$2));
  return ranked.take(max(0, work.count)).map((e) => e.$1).toList();
}

class SmartFlowWork {
  const SmartFlowWork(
    this.library,
    this.queue,
    this.anchors, {
    this.mode = 'shuffle',
    this.similar = const {},
    this.offline = const {},
    this.offlineOnly = false,
  });
  final List<Track> library, queue;
  final List<int> anchors;
  final String mode;
  final Map<String, Set<String>> similar;
  final Set<String> offline;
  final bool offlineOnly;
}

Map<int, Track> prepareSmartFlow(SmartFlowWork work) {
  final used = work.queue.map((t) => t.id).toSet();
  final pool =
      work.library
          .where(
            (t) =>
                !t.libraryHidden &&
                (work.offlineOnly
                    ? work.offline.contains(t.id)
                    : t.available || work.offline.contains(t.id)),
          )
          .toList()
        ..shuffle();
  final context = QueueContext(work.queue)..analyze();
  final result = <int, Track>{};
  for (final index in work.anchors) {
    if (index < 0 || index + 1 >= work.queue.length) continue;
    final seed = work.queue[index];
    if (work.mode == 'double' &&
        (sameArtist(seed, work.queue[index + 1]) ||
            index > 0 && sameArtist(seed, work.queue[index - 1]))) {
      continue;
    }
    final related = seed.artistNames
        .expand((a) => work.similar[artistNameKey(a)] ?? <String>{})
        .map(artistNameKey)
        .toSet();
    final genres = seed.genreNames.map(searchKey).toSet();
    int score(Track t) {
      final same = sameArtist(seed, t);
      final similar = t.artistNames.map(artistNameKey).any(related.contains);
      final inQueue = t.artistNames
          .map(artistNameKey)
          .any(context.artists.containsKey);
      final genre = t.genreNames.map(searchKey).any(genres.contains);
      return switch (work.mode) {
        'double' => same ? 1 : 0,
        'artist' =>
          same
              ? 5
              : similar
              ? (inQueue ? 4 : 3)
              : inQueue
              ? 2
              : related.isEmpty && genre
              ? 1
              : 0,
        'era' =>
          seed.year != null &&
                  t.year != null &&
                  seed.year! ~/ 10 == t.year! ~/ 10
              ? (similar
                    ? 4
                    : same
                    ? 3
                    : genre
                    ? 2
                    : 1)
              : 0,
        _ => 1,
      };
    }

    Track? chosen;
    var best = 0;
    for (final t in pool) {
      if (used.contains(t.id)) continue;
      final value = score(t);
      if (value > best) {
        best = value;
        chosen = t;
      }
    }
    if (chosen != null) {
      result[index] = chosen;
      used.add(chosen.id);
    }
  }
  return result;
}
