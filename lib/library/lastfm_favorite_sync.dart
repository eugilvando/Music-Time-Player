import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/track.dart';
import '../infrastructure/lastfm.dart';
import '../persistence/library_store.dart';

/// Durable, additive exports scoped to the authorized session, never the
/// separately editable public profile username. No credentials enter SQLite.
class LastFmFavoriteSync {
  LastFmFavoriteSync(
    this.store, {
    required this.api,
    required this.allowed,
    required this.online,
    required this.changed,
  });
  final LibraryStore store;
  final Future<LastFmClient> Function() api;
  final bool Function() allowed, online;
  final void Function() changed;
  bool _running = false;
  String status = 'Novos favoritos serão enviados ao Last.fm conectado.';

  void _status(String value) {
    status = value;
    changed();
  }

  String _account(LastFmClient client) => sha256
      .convert(utf8.encode('${client.apiKey}|${client.sessionKey}'))
      .toString();
  bool _connected(LastFmClient client) =>
      (client.sessionKey?.isNotEmpty ?? false) &&
      client.apiKey.isNotEmpty &&
      client.apiSecret.isNotEmpty;
  Future<void> _schema() => store.database.execute(
    'CREATE TABLE IF NOT EXISTS lastfm_favorite_outbox ('
    'account TEXT NOT NULL, track_id TEXT NOT NULL, title TEXT NOT NULL, '
    'artist TEXT NOT NULL, PRIMARY KEY(account,track_id))',
  );

  Future<void> enqueue(Iterable<Track> tracks) async {
    if (!allowed()) return;
    try {
      final client = await api();
      if (!allowed()) return;
      if (!_connected(client)) {
        _status(
          'Favorito salvo no app. Conecte o Last.fm para enviar novos favoritos.',
        );
        return;
      }
      await _schema();
      final account = _account(client);
      var skipped = false;
      await store.database.transaction((txn) async {
        for (final track in tracks) {
          if (!track.hasScrobbleMetadata) {
            skipped = true;
            continue;
          }
          await txn.insert('lastfm_favorite_outbox', {
            'account': account,
            'track_id': track.id,
            'title': track.title,
            'artist': track.artist,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      _status(
        skipped
            ? 'Faixas sem artista ou título não foram enviadas ao Last.fm.'
            : 'Favoritos aguardando envio ao Last.fm.',
      );
    } catch (_) {
      _status(
        'Favorito salvo no app; não foi possível agendar o envio ao Last.fm.',
      );
    }
  }

  Future<void> flush() async {
    if (_running || !allowed() || !online()) return;
    _running = true;
    try {
      final client = await api();
      if (!_connected(client) || !allowed() || !online()) return;
      final account = _account(client);
      await _schema();
      final rows = await store.database.query(
        'lastfm_favorite_outbox',
        where: 'account=?',
        whereArgs: [account],
        limit: 20,
      );
      for (final row in rows) {
        if (!allowed() || !online()) return;
        // Recheck authorization after every await/between requests.
        final current = await api();
        if (!_connected(current) ||
            _account(current) != account ||
            !allowed() ||
            !online()) {
          return;
        }
        final favorites = await store.database.query(
          'favorites',
          where: 'track_id=?',
          whereArgs: [row['track_id']],
          limit: 1,
        );
        if (favorites.isNotEmpty) {
          await current.love(
            Track(
              id: row['track_id'] as String,
              title: row['title'] as String,
              artist: row['artist'] as String,
            ),
          );
        }
        await store.database.delete(
          'lastfm_favorite_outbox',
          where: 'account=? AND track_id=? AND title=? AND artist=?',
          whereArgs: [account, row['track_id'], row['title'], row['artist']],
        );
      }
      if (rows.isNotEmpty) {
        final pending = await store.database.query(
          'lastfm_favorite_outbox',
          where: 'account=?',
          whereArgs: [account],
          limit: 1,
        );
        _status(
          pending.isEmpty
              ? 'Favoritos enviados ao Last.fm.'
              : 'Favoritos aguardando envio ao Last.fm.',
        );
      }
    } on LastFmException catch (error) {
      _status(
        error.requiresLogin
            ? 'Reconecte o Last.fm para enviar os favoritos pendentes.'
            : 'Envio ao Last.fm pendente; uma nova tentativa será feita.',
      );
    } catch (_) {
      _status('Envio ao Last.fm pendente; uma nova tentativa será feita.');
    } finally {
      _running = false;
    }
  }
}
