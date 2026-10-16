import 'package:flutter_test/flutter_test.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/library/m3u8.dart';
import 'package:music_time/persistence/library_store.dart';

void main() {
  const symfoniumPath =
      '/Música/My Music/Internacionais/The Killers/Sawdust/03 - All the Pretty Faces.mp3';
  const oneDrive = Track(
    id: 'onedrive:drive:original-id',
    title: 'All the Pretty Faces',
    artist: 'The Killers',
    driveId: 'drive',
    itemId: 'original-id',
    sourceProvider: 'onedrive',
    sourcePath:
        '/drive/root:/Música/My Music/Internacionais/The Killers/Sawdust',
    fileName: '03 - All the Pretty Faces.mp3',
  );
  test('Symfonium usa caminho original do OneDrive e preserva repetições', () {
    expect(
      importM3u8(
        '#EXTM3U\r\n\r\n$symfoniumPath\r\n$symfoniumPath',
        r'C:\Playlists\Favoritas.m3u8',
        [oneDrive],
      ),
      [oneDrive.id, oneDrive.id],
    );
    final content = exportM3u8('Favoritas', [oneDrive]);
    expect(content, contains('\n$symfoniumPath\n'));
    expect(content, isNot(contains('musictime://')));
    expect(importM3u8(content, 'Favoritas.m3u8', [oneDrive]), [oneDrive.id]);
  });
  test('caminho igual em contas diferentes exige fonte e não usa título', () {
    const another = Track(
      id: 'another',
      title: 'Outra tag',
      artist: 'Outro artista',
      driveId: 'other',
      itemId: 'other-id',
      sourcePath:
          '/drive/root:/Música/My Music/Internacionais/The Killers/Sawdust',
      fileName: '03 - All the Pretty Faces.mp3',
    );
    expect(
      () => importM3u8(symfoniumPath, 'lista.m3u8', [oneDrive, another]),
      throwsFormatException,
    );
    expect(
      importM3u8(symfoniumPath, 'lista.m3u8', [
        oneDrive,
        another,
      ], oneDriveId: 'drive'),
      [oneDrive.id],
    );
    expect(
      importM3u8(exportM3u8('lista', [oneDrive, another]), 'lista.m3u8', [
        oneDrive,
        another,
      ]),
      [oneDrive.id, another.id],
    );
    expect(
      () => importM3u8(symfoniumPath, 'lista.m3u8', [
        oneDrive,
      ], oneDriveId: 'wrong'),
      throwsFormatException,
    );
  });
  test('nome original persiste no SQLite e na hidratação de capa', () async {
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    await store.addTracks([oneDrive]);
    final loaded = (await store.loadTracks()).single.withCover(null);
    expect(loaded.fileName, oneDrive.fileName);
    expect(oneDrivePlaylistPath(loaded), symfoniumPath);
  });
  const local = Track(
    id: 'local',
    title: 'Canção',
    artist: 'Artista',
    localPath: r'C:\Música\canção.mp3',
  );
  const cloud = Track(id: 'drive:a/b', title: 'Nuvem', artist: 'Artista');
  test(
    'M3U8 UTF-8 preserva ordem, repetições e referências sem URL assinada',
    () {
      final content = exportM3u8('Minha seleção', [local, cloud, local]);
      expect(content, startsWith('#EXTM3U\n#PLAYLIST:Minha seleção\n'));
      expect(content, contains('Canção'));
      expect(content, contains('musictime://track/'));
      expect(importM3u8(content, r'C:\playlists\teste.m3u8', [local, cloud]), [
        'local',
        'drive:a/b',
        'local',
      ]);
    },
  );
  test('M3U8 rejeita referência ausente e URL remota', () {
    expect(
      () =>
          importM3u8('#EXTM3U\nC:\\missing.mp3', r'C:\playlist.m3u8', [local]),
      throwsFormatException,
    );
    expect(
      () => importM3u8(
        '#EXTM3U\nhttps://example.com/song?secret=abc',
        r'C:\playlist.m3u8',
        [local],
      ),
      throwsFormatException,
    );
  });
  test('M3U8 aceita BOM, comentários e caminhos relativos', () {
    expect(
      importM3u8(
        '\uFEFF#EXTM3U\r\n#EXTINF:10,Canção\r\ncanção.mp3\r\n',
        r'C:\Música\lista.m3u8',
        [local],
      ),
      ['local'],
    );
  });
}
