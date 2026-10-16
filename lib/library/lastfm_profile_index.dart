import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/lastfm.dart';
import '../persistence/library_store.dart';

/// Disposable, read-only service data, separate from local favorites/history.
class LastFmProfileIndex extends ChangeNotifier {
  LastFmProfileIndex(this.preferences, this.store, {required this.api});
  final SharedPreferences preferences;
  final LibraryStore store;
  final Future<LastFmClient> Function() api;
  Timer? _timer;
  Future<void>? _pending;
  bool _disposed = false;
  bool running = false;
  bool suspended = false;
  String status = 'Aguardando inicialização';
  DateTime? updatedAt;
  Map<String, int> counts = {};
  String get user =>
      (preferences.getString('lastfm.profile_user') ?? '').trim();
  bool get offline => preferences.getBool('visual.offline_only') ?? false;
  bool get automatic => preferences.getBool('lastfm.index_auto') ?? true;
  int get delaySeconds =>
      (preferences.getInt('lastfm.index_delay_seconds') ?? 30).clamp(10, 300);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void schedule({Duration? delay}) {
    _timer?.cancel();
    if (_disposed || suspended) return;
    if (!automatic || user.isEmpty) {
      status = automatic
          ? 'Informe seu usuário Last.fm para atualizar os índices.'
          : 'Atualização automática desativada';
      _notify();
      return;
    }
    status = 'Atualização agendada após a inicialização';
    _notify();
    _timer = Timer(delay ?? Duration(seconds: delaySeconds), () {
      if (offline) {
        schedule(delay: const Duration(minutes: 1));
        status = 'Atualização adiada: modo offline ativo';
        _notify();
      } else {
        unawaited(refresh());
      }
    });
  }

  Future<void> _schema() => store.database.execute(
    'CREATE TABLE IF NOT EXISTS lastfm_profile_cache (user TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(user,kind))',
  );

  Future<List<LastFmTrack>?> cached(String kind) async {
    await _schema();
    final rows = await store.database.query(
      'lastfm_profile_cache',
      where: 'user=? AND kind=?',
      whereArgs: [user.toLowerCase(), kind],
    );
    if (rows.isEmpty) return null;
    return [
      for (final row in jsonDecode(rows.single['payload'] as String) as List)
        LastFmTrack(
          row['title'] as String,
          row['artist'] as String,
          row['album'] as String,
          row['playedAt'] == null
              ? null
              : DateTime.parse(row['playedAt'] as String),
        ),
    ];
  }

  Future<List<LastFmTrack>> tracks(String kind) async {
    if (!{'loved', 'recent', 'overall', '1month'}.contains(kind)) {
      throw ArgumentError('Índice inválido');
    }
    final saved = await cached(kind);
    if (saved != null) return saved;
    await refresh();
    final result = await cached(kind);
    if (result == null) {
      throw StateError(
        'Índice Last.fm indisponível. Confira usuário, chave e conexão.',
      );
    }
    return result;
  }

  Future<void> refresh() {
    if (_disposed || suspended) return Future.value();
    if (_pending != null) return _pending!;
    _timer?.cancel();
    late final Future<void> job;
    job = _refresh().whenComplete(() {
      if (identical(_pending, job)) _pending = null;
    });
    _pending = job;
    return job;
  }

  Future<void> _refresh() async {
    if (offline || user.isEmpty) {
      status = offline
          ? 'Índices preservados; modo offline ativo.'
          : 'Informe seu usuário Last.fm.';
      _notify();
      return;
    }
    final profile = user;
    running = true;
    status = 'Atualizando índices Last.fm…';
    _notify();
    try {
      final client = await api();
      if (_disposed || suspended || offline) return;
      final snapshots = <String, List<LastFmTrack>>{};
      for (final kind in ['loved', 'recent', 'overall', '1month']) {
        if (_disposed || suspended || offline || user != profile) return;
        status =
            'Atualizando Last.fm: ${switch (kind) {
              'loved' => 'favoritos',
              'recent' => 'recentes',
              'overall' => 'mais ouvidas',
              _ => 'último mês',
            }}';
        _notify();
        snapshots[kind] = kind == 'loved' || kind == 'recent'
            ? await client.profileTracks(profile, loved: kind == 'loved')
            : await client.topTracks(profile, kind);
      }
      if (_disposed || suspended || offline || user != profile) return;
      await _schema();
      final now = DateTime.now().toUtc();
      await store.database.transaction((txn) async {
        for (final entry in snapshots.entries) {
          await txn.rawInsert(
            'INSERT OR REPLACE INTO lastfm_profile_cache(user,kind,payload,updated_at) VALUES(?,?,?,?)',
            [
              profile.toLowerCase(),
              entry.key,
              jsonEncode([
                for (final track in entry.value)
                  {
                    'title': track.title,
                    'artist': track.artist,
                    'album': track.album,
                    'playedAt': track.playedAt?.toUtc().toIso8601String(),
                  },
              ]),
              now.toIso8601String(),
            ],
          );
        }
      });
      updatedAt = now;
      counts = snapshots.map((key, value) => MapEntry(key, value.length));
      status = 'Índices Last.fm atualizados';
    } catch (_) {
      status = 'Não foi possível atualizar os índices Last.fm. Confira usuário, chave e conexão; os dados anteriores foram preservados.';
    } finally {
      running = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
