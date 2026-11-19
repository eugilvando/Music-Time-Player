import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scrobble_policy.dart';
import '../infrastructure/brainz.dart';
import '../persistence/library_store.dart';
import '../sources/microsoft_auth.dart';

class ListenBrainzSync {
  ListenBrainzSync(
    this.store,
    this.preferences,
    this.vault,
    this.transport, {
    required this.allowed,
    required this.changed,
  });
  final LibraryStore store;
  final SharedPreferences preferences;
  final SecretVault vault;
  final BrainzTransport transport;
  final bool Function() allowed;
  final void Function() changed;
  String user = '', status = 'ListenBrainz desconectado';
  String? _token, _current;
  bool _disposed = false;
  Future<void>? _flushJob;
  Future<void>? _ready;
  final _observed = <String>{}, _now = <String>{};
  Future<void> initialize() => _ready ??= _initialize();
  Future<void> _initialize() async {
    await store.database.execute(
      'CREATE TABLE IF NOT EXISTS listenbrainz_outbox('
      'account TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,status TEXT NOT NULL,'
      'next_attempt INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(account,id))',
    );
    await store.database.update(
      'listenbrainz_outbox',
      {'status': 'ambiguous'},
      where: 'status=?',
      whereArgs: ['sending'],
    );
    try {
      final raw = await vault.read('listenbrainz.session');
      if (raw != null) {
        final session = jsonDecode(raw) as Map;
        user = session['user'] as String;
        _token = session['token'] as String;
      }
      status = user.isEmpty
          ? 'ListenBrainz desconectado'
          : 'Conectado como $user';
    } catch (_) {
      status = 'Não foi possível ler a conexão ListenBrainz.';
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) changed();
  }

  Future<void> connect(String token) async {
    await initialize();
    if (token.trim().isEmpty) {
      throw StateError('Informe seu token ListenBrainz.');
    }
    if (!allowed()) throw StateError('Saia do modo offline para conectar.');
    final name = await ListenBrainzClient(transport, token.trim()).validate();
    await vault.write(
      'listenbrainz.session',
      jsonEncode({'user': name, 'token': token.trim()}),
    );
    if (user.toLowerCase() != name.toLowerCase()) {
      await preferences.setBool('listenbrainz.scrobbling', false);
      await preferences.setBool('listenbrainz.now_playing', false);
    }
    user = name;
    _token = token.trim();
    _observed.clear();
    _now.clear();
    await store.database.update(
      'listenbrainz_outbox',
      {'status': 'pending'},
      where: 'account=? AND status=?',
      whereArgs: [user.toLowerCase(), 'auth_required'],
    );
    status = 'Conectado como $user. Ative os envios abaixo.';
    _notify();
  }

  Future<void> disconnect() async {
    await initialize();
    await vault.delete('listenbrainz.session');
    user = '';
    _token = null;
    status = 'Desconectado. As pendências foram preservadas.';
    _observed.clear();
    _now.clear();
    _notify();
  }

  Future<void> observe(ListeningSession session) async {
    try {
      await initialize();
      if (_disposed ||
          _token == null ||
          session.listened <= Duration.zero ||
          !session.track.hasScrobbleMetadata) {
        return;
      }
      final id =
          '${session.track.id}|${session.startedAt.toUtc().toIso8601String()}';
      _current = id;
      // Bounded session guards; the persistent primary key also deduplicates listens.
      if (_now.length > 2000) _now.clear();
      if (_observed.length > 2000) _observed.clear();
      final duration = session.duration > Duration.zero
          ? session.duration
          : session.track.duration;
      if ((preferences.getBool('listenbrainz.scrobbling') ?? false) &&
          session.eligible &&
          _observed.add(id)) {
        try {
          await store.database.rawInsert(
            'INSERT OR IGNORE INTO listenbrainz_outbox(account,id,payload,status) VALUES(?,?,?,?)',
            [
              user.toLowerCase(),
              id,
              jsonEncode(
                ListenBrainzClient.payload(
                  session.track,
                  session.startedAt,
                  duration,
                ),
              ),
              'pending',
            ],
          );
        } catch (_) {
          _observed.remove(id);
          rethrow;
        }
        unawaited(flush());
      }
      if (allowed() &&
          (preferences.getBool('listenbrainz.now_playing') ?? false) &&
          _now.add(id)) {
        final token = _token!;
        await ListenBrainzClient(transport, token).send(
          ListenBrainzClient.payload(session.track, null, duration),
          nowPlaying: true,
          guard: () =>
              !_disposed &&
              allowed() &&
              _token == token &&
              _current == id &&
              (preferences.getBool('listenbrainz.now_playing') ?? false),
        );
      }
    } catch (_) {
      status = 'Não foi possível enviar ao ListenBrainz. Confira a conexão.';
      _notify();
    }
  }

  Future<List<Map<String, Object?>>> outbox() async {
    await initialize();
    return store.database.query(
      'listenbrainz_outbox',
      columns: ['id', 'status'],
      where: 'account=?',
      whereArgs: [user.toLowerCase()],
      orderBy: 'id DESC',
      limit: 100,
    );
  }

  Future<void> flush() =>
      _flushJob ??= _flush().whenComplete(() => _flushJob = null);
  Future<void> _flush() async {
    if (_disposed) return;
    try {
      await initialize();
      if (!allowed() ||
          _token == null ||
          !(preferences.getBool('listenbrainz.scrobbling') ?? false)) {
        return;
      }
      final account = user.toLowerCase(), token = _token!;
      final rows = await store.database.query(
        'listenbrainz_outbox',
        where: 'account=? AND status=? AND next_attempt<=?',
        whereArgs: [account, 'pending', DateTime.now().millisecondsSinceEpoch],
        limit: 25,
        orderBy: 'id',
      );
      for (final row in rows) {
        if (_disposed ||
            !allowed() ||
            token != _token ||
            !(preferences.getBool('listenbrainz.scrobbling') ?? false)) {
          break;
        }
        Future<void> mark(String state, {int delay = 0}) async {
          await store.database.update(
            'listenbrainz_outbox',
            {
              'status': state,
              'next_attempt': DateTime.now()
                  .add(Duration(seconds: delay))
                  .millisecondsSinceEpoch,
            },
            where: 'account=? AND id=?',
            whereArgs: [account, row['id']],
          );
        }

        await mark('sending');
        try {
          await ListenBrainzClient(transport, token).send(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            guard: () =>
                !_disposed &&
                allowed() &&
                _token == token &&
                (preferences.getBool('listenbrainz.scrobbling') ?? false),
          );
          await mark('sent');
          status = 'Último envio: ${DateTime.now()}';
        } on BrainzFailure catch (e) {
          if (e.code == 401 || e.code == 403) {
            await mark('auth_required');
            status = 'Reconecte o ListenBrainz.';
            break;
          }
          if (e.code == 0 || e.code == 429 || e.code >= 500) {
            await mark('pending', delay: 60);
            status = 'Envio adiado. As reproduções continuam salvas.';
            break;
          }
          await mark('rejected');
          status = 'ListenBrainz recusou um envio (${e.code}).';
        } catch (_) {
          await mark('ambiguous');
          status = 'Resposta desconhecida; envio não repetido para evitar duplicação.';
          break;
        }
      }
    } catch (_) {
      status = 'Fila ListenBrainz indisponível. Tente novamente.';
    } finally {
      _notify();
    }
  }

  void dispose() {
    _disposed = true;
  }
}
