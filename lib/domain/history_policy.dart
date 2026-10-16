import 'scrobble_policy.dart';

bool countsForHistory(ListeningSession session) {
  final duration = session.duration > Duration.zero
      ? session.duration
      : session.track.duration;
  if (duration <= Duration.zero) return false;
  final threshold = duration.inMicroseconds ~/ 2;
  final required = threshold < 30000000 ? threshold : 30000000;
  return session.listened.inMicroseconds >= required;
}
