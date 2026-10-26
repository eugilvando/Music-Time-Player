import 'dart:math';

enum PlaybackRepeat { off, queue, track }

/// Keep the current occurrence first, with a visible, stable upcoming order.
List<int> shuffledQueueOrder(int length, int current, {Random? random}) {
  if (length == 0) return [];
  final rest = List.generate(length, (i) => i)..remove(current);
  rest.shuffle(random ?? Random());
  return current >= 0 && current < length ? [current, ...rest] : rest;
}

int nextQueueIndex({
  required int current,
  required int length,
  required PlaybackRepeat repeat,
  required bool shuffle,
  bool automatic = false,
  Random? random,
}) {
  if (length == 0 || current < 0) return -1;
  if (automatic && repeat == PlaybackRepeat.track) return current;
  if (shuffle && length > 1) {
    final value = (random ?? Random()).nextInt(length - 1);
    return value >= current ? value + 1 : value;
  }
  if (current + 1 < length) return current + 1;
  return repeat == PlaybackRepeat.queue ? 0 : -1;
}

class ShuffleCycle {
  ShuffleCycle({Random? random}) : random = random ?? Random();
  final Random random;
  final remaining = <int>[];
  void reset(int length, int current) {
    remaining
      ..clear()
      ..addAll(
        List.generate(
          length,
          (index) => index,
        ).where((index) => index != current),
      );
    remaining.shuffle(random);
  }

  bool canAdvance(int length, bool repeatAll) =>
      remaining.isNotEmpty || (repeatAll && length > 0);
  int next(int length, int current, {required bool repeatAll}) {
    if (remaining.isEmpty && repeatAll) reset(length, current);
    if (remaining.isEmpty) return repeatAll && length == 1 ? current : -1;
    return remaining.removeAt(0);
  }
}
