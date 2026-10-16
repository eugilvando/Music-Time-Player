import 'track.dart';

/// Uma instância por execução de uma faixa; replay cria outra instância.
/// Recebe tempo realmente ouvido, nunca posição do seek.
class ListeningSession {
  ListeningSession(this.track, this.startedAt);
  final Track track;
  final DateTime startedAt;
  Duration listened = Duration.zero;
  Duration duration = Duration.zero;
  bool claimed = false;

  void addListening(Duration elapsed) {
    if (elapsed > Duration.zero) listened += elapsed;
  }

  bool get eligible {
    final length = duration > Duration.zero ? duration : track.duration;
    if (!track.hasScrobbleMetadata || length <= const Duration(seconds: 30)) {
      return false;
    }
    final half = length.inMicroseconds ~/ 2;
    final threshold = half < 240000000 ? half : 240000000;
    return listened.inMicroseconds >= threshold;
  }

  /// Claim local evita duplicatas. A entrega deve usar outbox persistente.
  bool claim() {
    if (claimed || !eligible) return false;
    claimed = true;
    return true;
  }
}
