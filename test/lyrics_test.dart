import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/lyrics/lyrics.dart';
import 'package:music_time/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('LRC ordena linhas e aplica offset e ajuste após seek', () {
    final lyrics = parseLyrics(
      '[ti:Teste]\n[offset:250]\n[00:02.00]Segunda\n[00:00.50][00:04.000]Refrão',
    );
    expect(lyrics.lines.map((line) => line.text), [
      'Refrão',
      'Segunda',
      'Refrão',
    ]);
    expect(lyrics.activeIndex(const Duration(milliseconds: 749)), -1);
    expect(lyrics.activeIndex(const Duration(milliseconds: 750)), 0);
    expect(lyrics.activeIndex(const Duration(milliseconds: 2250)), 1);
    expect(lyrics.activeIndex(const Duration(milliseconds: 4250)), 2);
    expect(
      lyrics.activeIndex(
        const Duration(milliseconds: 4250),
        adjustment: const Duration(milliseconds: 500),
      ),
      1,
    );
    expect(lyrics.activeIndex(const Duration(seconds: 1)), 0);
  });
  test(
    'letras simples permanecem sem timestamps e arquivos inválidos falham',
    () {
      final lyrics = parseLyrics('Uma linha\nOutra linha');
      expect(lyrics.synchronized, isFalse);
      expect(lyrics.activeIndex(const Duration(seconds: 10)), -1);
      for (final text in [
        '',
        '[00:99.00]Inválida',
        '[00:00.00]Linha\nTexto solto',
        '[00:xx]Inválida',
      ]) {
        expect(() => parseLyrics(text), throwsFormatException);
      }
    },
  );
  test('palavras são temporizadas apenas quando o LRC contém tempos reais', () {
    final enhanced = parseLyrics('[00:01.00]<00:01.00>Uma <00:01.50>palavra');
    expect(enhanced.lines.single.text, 'Uma palavra');
    expect(enhanced.lines.single.words.map((word) => word.at.inMilliseconds), [
      1000,
      1500,
    ]);
    expect(parseLyrics('[00:01.00]Uma palavra').lines.single.words, isEmpty);
    expect(
      () => parseLyrics('[00:01.00]<00:02.00>Uma <00:01.00>palavra'),
      throwsFormatException,
    );
  });
  test('aparência, favoritos de coleção e ajuste por faixa persistem separadamente', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(prefs);
    await settings.updateVisual('style', 'gallery');
    await settings.updateVisual('reduce_motion', true);
    await settings.updateVisual('cover_scale', .8);
    await settings.favoriteCollection('album:test');
    await settings.setLyricsOffset('track-a', 500);
    final restored = AppSettings(prefs);
    expect(restored.nowPlayingStyle, 'gallery');
    expect(restored.visualBool('reduce_motion', fallback: false), isTrue);
    expect(restored.collectionFavorites, contains('album:test'));
    expect(restored.lyricsOffset('track-a'), 500);
    expect(restored.lyricsOffset('track-b'), 0);
    await restored.resetVisual();
    expect(restored.nowPlayingStyle, 'vinyl');
    expect(restored.collectionFavorites, contains('album:test'));
    expect(restored.lyricsOffset('track-a'), 500);
    settings.dispose();
    restored.dispose();
  });
}
