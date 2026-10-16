import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/scrobble_policy.dart';
import 'package:music_time/domain/track.dart';

void main() {
  ListeningSession session({int seconds = 180, String artist = 'Artista'}) {
    return ListeningSession(
      Track(
        id: '1',
        title: 'Faixa',
        artist: artist,
        duration: Duration(seconds: seconds),
      ),
      DateTime.utc(2026),
    );
  }

  test('metade da faixa habilita uma única reivindicação', () {
    final value = session();
    value.addListening(const Duration(seconds: 89));
    expect(value.claim(), isFalse);
    value.addListening(const Duration(seconds: 1));
    expect(value.claim(), isTrue);
    expect(value.claim(), isFalse);
  });

  test('faixas longas usam limite de quatro minutos', () {
    final value = session(seconds: 900);
    value.addListening(const Duration(seconds: 239));
    expect(value.eligible, isFalse);
    value.addListening(const Duration(seconds: 1));
    expect(value.eligible, isTrue);
  });

  test('faixas curtas e artista desconhecido não são elegíveis', () {
    for (final value in [
      session(seconds: 30),
      session(artist: 'Artista desconhecido'),
      session(artist: 'Unknown artist'),
      session(artist: ' '),
    ]) {
      value.addListening(const Duration(minutes: 10));
      expect(value.eligible, isFalse);
    }
  });

  test('duração do player prevalece e tempo negativo é ignorado', () {
    final value = session()..duration = const Duration(seconds: 100);
    value.addListening(const Duration(seconds: -10));
    expect(value.listened, Duration.zero);
    value.addListening(const Duration(seconds: 50));
    expect(value.eligible, isTrue);
    expect(session().claimed, isFalse);
  });
}
