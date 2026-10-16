import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_time/presentation/startup_gate.dart';
import 'package:music_time/persistence/library_store.dart';
import 'package:music_time/domain/track.dart';
import 'package:music_time/sources/provider_connections.dart';

import 'provider_auth_test.dart' show MemoryVault;

class UnreadableSessionVault extends MemoryVault {
  @override
  Future<String?> read(String key) async {
    if (key == 'lastfm.session') throw StateError('cofre indisponível');
    return super.read(key);
  }
}

void main() {
  testWidgets(
    'primeiro frame e progresso aparecem enquanto banco demora, sem autoplay',
    (tester) async {
      final opening = Completer<Widget>();
      late ValueChanged<String> status;
      await tester.pumpWidget(
        StartupGate(
          initialize: (progress) {
            status = progress;
            return opening.future;
          },
        ),
      );
      await tester.pump();
      expect(find.text('Opening Music Time'), findsOneWidget);
      status('Atualizando busca: 500 faixas processadas…');
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.text('Updating search: 500 tracks processed…'),
        findsOneWidget,
      );
      opening.complete(const MaterialApp(home: Text('Biblioteca pronta')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Biblioteca pronta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'erro antes da biblioteca mostra recuperação e não tela branca ou detalhes privados',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        StartupGate(
          initialize: (_) async {
            if (attempts++ == 0) throw StateError('PRIVATE_FIXTURE');
            return const MaterialApp(home: Text('Recuperado'));
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Could not start Music Time'), findsOneWidget);
      expect(find.textContaining('PRIVATE_FIXTURE'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Recuperado'), findsOneWidget);
      expect(attempts, 2);
    },
  );
  test('migração com capas usa leitura de índice sem BLOB e reindexa em lotes', () async {
    final dir = await Directory.systemTemp.createTemp(
      'music-time-startup-covers-',
    );
    final dbPath = '${dir.path}/fixture.db';
    var store = await LibraryStore.open(dbPath);
    try {
      final cover = Uint8List(32768)..fillRange(0, 32768, 7);
      await store.addTracks(
        List.generate(
          1100,
          (i) => Track(
            id: 'id${i.toString().padLeft(5, '0')}',
            title: 'Faixa $i',
            artist: 'Artista',
            localPath: 'C:/fixture/$i.mp3',
            cover: cover,
          ),
        ),
      );
      await store.setFavorite('id00001', true);
      await store.database.execute('DROP INDEX tracks_catalog_read_idx');
      await store.database.execute('PRAGMA user_version=9');
      await store.close();
      final stages = <String>[];
      final clock = Stopwatch()..start();
      store = await LibraryStore.open(dbPath, onProgress: stages.add);
      final loaded = await store.loadTracks(
        includeCovers: false,
        includeHidden: true,
      );
      expect(loaded.length, 1100);
      expect(loaded.every((t) => t.cover == null && t.hasArtwork), true);
      expect(stages.any((s) => s.contains('500 faixas')), true);
      expect(stages.any((s) => s.contains('1100 faixas')), true);
      expect(await store.favoriteIds(), {'id00001'});
      final root = (await store.database.rawQuery(
        "SELECT rootpage FROM sqlite_master WHERE name='tracks'",
      )).single['rootpage'];
      final instructions = await store.database.rawQuery(
        'EXPLAIN SELECT ${LibraryStore.metadataColumns.join(',')},(cover IS NOT NULL OR cover_hash IS NOT NULL) AS has_cover FROM tracks INDEXED BY tracks_catalog_read_idx ORDER BY rowid',
      );
      final tableCursors = instructions
          .where((r) => r['opcode'] == 'OpenRead' && r['p2'] == root)
          .map((r) => r['p1'])
          .toSet();
      expect(
        instructions.where(
          (r) => r['opcode'] == 'Column' && tableCursors.contains(r['p1']),
        ),
        isEmpty,
        reason: 'Metadados devem vir do índice, sem percorrer os registros com BLOBs',
      );
      expect((await store.database.query('catalog_search')).length, 1100);
      debugPrint(
        'Fixture 1100 capas/36MB: migração e leitura ${clock.elapsedMilliseconds}ms',
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
  test('Last.fm restaura sessão após recriar serviços sem abrir configurações e sem rede', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final vault = MemoryVault();
    await vault.write('lastfm.session', 'fixture-session');
    var p = ProviderConnections(prefs, store, vault: vault);
    await p.restoreLastfmStatus();
    expect(p.lastfmConnected, true);
    expect(p.lastfmStatusLoading, false);
    p.dispose();
    p = ProviderConnections(prefs, store, vault: vault);
    addTearDown(p.dispose);
    await p.restoreLastfmStatus();
    expect(p.lastfmConnected, true);
    expect(vault.values.containsKey('lastfm.session'), true);
  });
  test('falha de leitura do cofre não apaga sessão Last.fm', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LibraryStore.open(':memory:');
    addTearDown(store.close);
    final vault = UnreadableSessionVault();
    await vault.write('lastfm.session', 'preservada');
    final p = ProviderConnections(
      await SharedPreferences.getInstance(),
      store,
      vault: vault,
    );
    addTearDown(p.dispose);
    await p.restoreLastfmStatus();
    expect(p.lastfmStatusError, true);
    expect(vault.values['lastfm.session'], 'preservada');
  });
}
