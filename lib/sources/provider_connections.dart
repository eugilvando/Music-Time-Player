import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';

import '../domain/scrobble_policy.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ports.dart';
import '../domain/track.dart';
import '../infrastructure/onedrive.dart';
import '../infrastructure/lastfm.dart';
import '../persistence/library_store.dart';
import 'microsoft_auth.dart';
import 'onedrive_verification.dart';
import '../library/cloud_metadata.dart';
import '../library/lastfm_profile_index.dart';
import 'microsoft_sources.dart';
import 'additional_sources.dart';

class ProviderConnections extends ChangeNotifier
    implements MediaSourceResolver, AuthenticatedMediaResolver {
  ProviderConnections(
    this.preferences,
    this.store, {
    SecretVault? vault,
    http.Client? client,
    this.sourceId = 'legacy',
    this.accountRoot,
  }) : vault = vault ?? const SystemVault(),
       client = client ?? http.Client() {
    _worker = accountRoot == null
        ? Timer.periodic(
            const Duration(seconds: 30),
            (_) => unawaited(flushScrobbles()),
          )
        : null;
    if (accountRoot == null) {
      _profileIndex = LastFmProfileIndex(preferences, store, api: lastfm)
        ..addListener(_notify);
      _loadMicrosoftSources();
      _additional = AdditionalSources(
        preferences,
        store,
        this.vault,
        this.client,
      )..addListener(_notify);
      unawaited(restoreLastfmStatus());
    }
  }
  final SharedPreferences preferences;
  AdditionalSources? _additional;
  AdditionalSources get additional => microsoftAccountRoot._additional!;
  @override
  Future<Map<String, String>> mediaHeaders(Track track, Uri uri) =>
      additionalSourceTypes.containsKey(track.provider)
      ? additional.mediaHeaders(track, uri)
      : Future.value({});
  @override
  bool allowsInsecureMedia(Uri uri) => additional.allowsInsecureMedia(uri);
  LastFmProfileIndex? _profileIndex;
  LastFmProfileIndex get profileIndex => microsoftAccountRoot._profileIndex!;
  final LibraryStore store;
  final SecretVault vault;
  final http.Client client;
  final String sourceId;
  final ProviderConnections? accountRoot;
  ProviderConnections get microsoftAccountRoot => accountRoot ?? this;
  final _microsoftSources = <String, ProviderConnections>{};
  ProviderConnections? _loginOwner;
  String get microsoftSessionKey => microsoftSourceSessionKey(sourceId);
  String _sourceKey(String key) => sourceId == 'legacy'
      ? key
      : 'microsoft.source.$sourceId.${key.substring(10)}';
  List<ProviderConnections> get microsoftSources => [
    this,
    ..._microsoftSources.values,
  ];
  bool get anyMicrosoftBusy => microsoftSources.any((source) => source.busy);
  bool get anyMicrosoftLoginPending => microsoftAccountRoot._loginOwner != null;
  String get microsoftSourceLabel =>
      preferences.getString(_sourceKey('microsoft.label')) ??
      'OneDrive pessoal';

  void _loadMicrosoftSources() {
    for (final id
        in preferences.getStringList(microsoftSourcesPreference) ??
            const <String>[]) {
      if (!validMicrosoftSourceId(id)) continue;
      _microsoftSources.putIfAbsent(id, () {
        final source = ProviderConnections(
          preferences,
          store,
          vault: vault,
          client: client,
          sourceId: id,
          accountRoot: this,
        );
        source.addListener(_notify);
        return source;
      });
    }
  }

  Future<ProviderConnections> createMicrosoftSource() async {
    final root = microsoftAccountRoot;
    final id = secureRandomString();
    final ids = [...root._microsoftSources.keys, id];
    if (!await preferences.setStringList(microsoftSourcesPreference, ids)) {
      throw StateError('Fonte não salva');
    }
    root._loadMicrosoftSources();
    final source = root._microsoftSources[id]!;
    await source.renameMicrosoftSource(
      'OneDrive pessoal ${root.microsoftSources.length}',
    );
    root._notify();
    return source;
  }

  Future<void> renameMicrosoftSource(String value) async {
    final label = value.trim();
    if (label.isEmpty || label.length > 80) {
      throw const FormatException('Use um nome de 1 a 80 caracteres.');
    }
    if (!await preferences.setString(_sourceKey('microsoft.label'), label)) {
      throw StateError('Nome não salvo');
    }
    await registerMicrosoftFolder();
    _notify();
  }

  Future<void> removeMicrosoftSource() async {
    if (busy) return;
    await store.removeCloudSource('onedrive:$sourceId');
    await store.clearCloudCheckpoint(microsoftSessionKey);
    await disconnectMicrosoft();
    if (error != null || sourceId == 'legacy') return;
    final root = microsoftAccountRoot;
    final ids = root._microsoftSources.keys
        .where((id) => id != sourceId)
        .toList();
    if (!await preferences.setStringList(microsoftSourcesPreference, ids)) {
      throw StateError('Fonte não removida');
    }
    for (final key
        in preferences
            .getKeys()
            .where((key) => key.startsWith('microsoft.source.$sourceId.'))
            .toList()) {
      await preferences.remove(key);
    }
    root._microsoftSources.remove(sourceId);
    removeListener(root._notify);
    dispose();
    root._notify();
  }

  bool busy = false, microsoftConnected = false, lastfmConnected = false;
  bool lastfmStatusLoading = true, lastfmStatusError = false;
  int _lastfmEpoch = 0;
  Future<void>? _lastfmStatusFuture;
  Future<void> restoreLastfmStatus() {
    if (accountRoot != null) return accountRoot!.restoreLastfmStatus();
    if (_lastfmStatusFuture != null) return _lastfmStatusFuture!;
    final epoch = _lastfmEpoch;
    late final Future<void> job;
    job =
        (() async {
          lastfmStatusLoading = true;
          try {
            final session = await vault.read('lastfm.session');
            if (_disposed || epoch != _lastfmEpoch) return;
            lastfmConnected = session != null && session.isNotEmpty;
            lastfmStatusError = false;
          } catch (_) {
            if (!_disposed && epoch == _lastfmEpoch) lastfmStatusError = true;
          } finally {
            if (!_disposed && epoch == _lastfmEpoch) {
              lastfmStatusLoading = false;
              _notify();
            }
          }
        })().whenComplete(() {
          if (identical(_lastfmStatusFuture, job)) _lastfmStatusFuture = null;
        });
    _lastfmStatusFuture = job;
    return job;
  }

  String? error, pendingLastfmToken;
  int imported = 0;
  bool syncingMicrosoft = false;
  int syncPages = 0, syncExamined = 0;
  int syncTagsRead = 0, syncTagsSkipped = 0;
  String syncCurrentFile = '';
  String syncStatus = 'idle';
  Map<String, dynamic>? get syncSummary {
    try {
      final value = preferences.getString(_sourceKey('microsoft.sync_summary'));
      return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  MicrosoftDeviceCode? pendingMicrosoftCode;
  MicrosoftAuth? _loginAuth;
  bool get microsoftLoginPending => _loginAuth != null;
  bool cancelSync = false;
  void cancelMicrosoftSync() {
    cancelSync = true;
    _notify();
  }

  bool _disposed = false, _flushing = false;
  bool suspended = false;
  bool get flushingScrobbles => _flushing;
  late final Timer? _worker;
  final _observed = <String>{}, _nowPlaying = <String>{};
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String get microsoftClientId =>
      const String.fromEnvironment('MUSIC_TIME_MICROSOFT_CLIENT_ID').isNotEmpty
      ? const String.fromEnvironment('MUSIC_TIME_MICROSOFT_CLIENT_ID')
      : preferences.getString('microsoft.client_id') ?? '';
  bool get microsoftConfigured {
    try {
      MicrosoftAuth(
        client,
        vault,
        clientId: microsoftClientId,
      ).validateClientId();
      return true;
    } on MicrosoftAuthFailure {
      return false;
    }
  }

  MicrosoftAuth? _microsoft;
  String? microsoftDriveName, errorStage, errorCode;
  List<String> microsoftChecks = [];
  DateTime? microsoftCheckedAt;
  Map<String, dynamic>? _driveCache;
  String? _driveSession, _pendingDriveSession;
  Future<Map<String, dynamic>>? _pendingDrive;

  Future<
    ({
      OneDriveClient graph,
      MicrosoftSessionTokens tokens,
      Map<String, dynamic> drive,
    })
  >
  _microsoftContext({bool force = false}) async {
    final auth = microsoft;
    final identity = await auth.sessionIdentity();
    final tokens = MicrosoftSessionTokens(auth, identity);
    final graph = OneDriveClient(client, tokens);
    Map<String, dynamic> drive;
    if (!force && _driveSession == identity && _driveCache != null) {
      drive = _driveCache!;
    } else if (_pendingDriveSession == identity && _pendingDrive != null) {
      drive = await _pendingDrive!;
    } else {
      final request = () async {
        final value = await graph.drive();
        final id = value['id'];
        if (id is! String || id.isEmpty) {
          throw const MicrosoftAuthFailure(
            'O OneDrive retornou uma identificação inválida. Tente novamente.',
            code: 'drive_response_invalid',
            stage: 'graph_drive',
          );
        }
        await auth.bindDrive(id, identity);
        await tokens.requireCurrent();
        _driveSession = identity;
        _driveCache = value;
        microsoftDriveName = value['name'] as String? ?? 'OneDrive';
        return value;
      }();
      _pendingDrive = request;
      _pendingDriveSession = identity;
      try {
        drive = await request;
      } finally {
        if (identical(_pendingDrive, request)) {
          _pendingDrive = null;
          _pendingDriveSession = null;
        }
      }
    }
    await tokens.requireCurrent();
    return (graph: graph, tokens: tokens, drive: drive);
  }

  void _checkFolderDrive(String driveId) {
    final selectedDrive = preferences.getString(
      _sourceKey('microsoft.folder_drive_id'),
    );
    if (selectedDrive != null && selectedDrive != driveId) {
      throw const MicrosoftAuthFailure(
        'A pasta selecionada pertence a outra conta. Escolha a pasta musical desta conta antes de sincronizar.',
        code: 'folder_account_mismatch',
        stage: 'account',
      );
    }
  }

  Future<void> _clearMicrosoftFolder() async {
    for (final key in [
      'folder_path',
      'folder_id',
      'folder_name',
      'folder_selected',
      'folder_drive_id',
      'sync_summary',
    ]) {
      await preferences.remove(_sourceKey('microsoft.$key'));
    }
    microsoftChecks = [];
    microsoftCheckedAt = null;
  }

  MicrosoftAuth get microsoft {
    if (_microsoft?.clientId != microsoftClientId) {
      _microsoft = MicrosoftAuth(
        client,
        vault,
        clientId: microsoftClientId,
        sessionKey: microsoftSessionKey,
      );
    }
    return _microsoft!;
  }

  Future<void> refreshStatus() async {
    if (accountRoot == null) await restoreLastfmStatus();
    final saved = await vault.read(microsoftSessionKey);
    try {
      final data = saved == null
          ? null
          : jsonDecode(saved) as Map<String, dynamic>;
      microsoftConnected =
          data != null &&
          data['client_id'] == microsoftClientId &&
          data['access_token'] is String &&
          (data['access_token'] as String).isNotEmpty;
    } catch (_) {
      microsoftConnected = false;
    }
    if (accountRoot == null) {
      _loadMicrosoftSources();
      for (final source in _microsoftSources.values) {
        await source.refreshStatus();
      }
    }
    if (!microsoftConnected) {
      _driveCache = null;
      _driveSession = null;
      microsoftDriveName = null;
    }
    await registerMicrosoftFolder();
    _notify();
  }

  bool get microsoftVisible =>
      preferences.getBool(_sourceKey('microsoft.visible')) ?? true;
  Future<void> registerMicrosoftFolder() async {
    final drive = preferences.getString(
      _sourceKey('microsoft.folder_drive_id'),
    );
    if (drive == null || !microsoftFolderSelected) return;
    await store.saveCloudSource(
      'onedrive:$sourceId',
      drive,
      preferences.getString(_sourceKey('microsoft.folder_path')) ?? '',
      microsoftSourceLabel,
      microsoftVisible,
    );
  }

  Future<void> setMicrosoftVisible(bool value) async {
    if (!await preferences.setBool(_sourceKey('microsoft.visible'), value)) {
      throw StateError('Preferência não salva');
    }
    await registerMicrosoftFolder();
    _notify();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    errorStage = null;
    errorCode = null;
    _notify();
    try {
      await action();
      await refreshStatus();
    } on MicrosoftAuthFailure catch (failure) {
      error = failure.message;
      errorStage = failure.stage;
      errorCode = failure.code;
      await refreshStatus();
    } on GraphException catch (failure) {
      errorStage = failure.operation == 'content'
          ? 'content'
          : 'graph_${failure.operation}';
      errorCode = 'http_${failure.status}';
      error = switch (failure.status) {
        401 =>
          'O acesso ao OneDrive expirou. Conecte novamente pelo navegador.',
        403 => 'O OneDrive negou a leitura. Confira o consentimento Files.Read e as permissões da pasta.',
        404 =>
          failure.operation == 'drive'
              ? 'Esta conta não possui um OneDrive disponível. Abra o OneDrive no navegador para configurar o drive.'
              : 'A pasta ou arquivo não foi encontrado. Escolha novamente a pasta musical.',
        429 => 'O OneDrive limitou as consultas. Aguarde um minuto e tente novamente.',
        _ =>
          'O OneDrive não respondeu corretamente. Tente novamente mais tarde.',
      };
      if (failure.operation == 'content') {
        error =
            'O conteúdo musical não pôde ser lido (HTTP ${failure.status}). Tente novamente para renovar o endereço temporário.';
      }
    } on LastFmException catch (failure) {
      errorStage = 'lastfm';
      errorCode = '${failure.code}';
      error = switch (failure.code) {
        10 || 26 => 'Chave Last.fm inválida ou suspensa. Consulte suas chaves no site e atualize a configuração.',
        6 || 7 => 'Perfil Last.fm não encontrado. Confira o nome de usuário.',
        4 || 17 => 'Last.fm negou a consulta. Confira a privacidade do perfil ou autorize a conta.',
        9 => 'Sessão Last.fm expirada. Autorize novamente pelo navegador.',
        29 => 'Last.fm limitou as consultas. Aguarde e tente novamente.',
        _ =>
          'Last.fm indisponível (erro ${failure.code}). Tente novamente mais tarde.',
      };
    } on SocketException {
      errorStage = 'network';
      errorCode = 'offline';
      error = 'Sem conexão. Confira a internet e tente novamente.';
    } on http.ClientException {
      errorStage = 'network';
      errorCode = 'transport';
      error = 'Falha de conexão. Confira a internet e tente novamente.';
    } on TimeoutException {
      errorStage = 'network';
      errorCode = 'timeout';
      error = 'A conexão demorou demais. Tente novamente.';
    } catch (_) {
      error = 'Operação não concluída. Confira a configuração e a conexão; tente novamente.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> configure(
    String clientId,
    String apiKey,
    String apiSecret,
  ) async {
    if (clientId.isNotEmpty) {
      MicrosoftAuth(
        client,
        vault,
        clientId: clientId.trim(),
      ).validateClientId();
      if (!await preferences.setString(
        'microsoft.client_id',
        clientId.trim(),
      )) {
        throw const MicrosoftAuthFailure(
          'Não foi possível salvar o Client ID. Tente novamente.',
        );
      }
    }
    if (apiKey.isNotEmpty) await vault.write('lastfm.api_key', apiKey.trim());
    if (apiSecret.isNotEmpty) {
      await vault.write('lastfm.api_secret', apiSecret.trim());
    }
  }

  Future<void> connectMicrosoft({bool useCode = false}) => run(() async {
    final root = microsoftAccountRoot;
    if (root._loginOwner != null) {
      throw const MicrosoftAuthFailure(
        'Outra conta está fazendo login. Conclua ou cancele antes de iniciar novamente.',
        code: 'login_in_progress',
        stage: 'callback',
      );
    }
    final destination = microsoft;
    final snapshot = await vault.read(microsoftSessionKey);
    final expectedDrive =
        await destination.boundDriveId() ??
        preferences.getString(_sourceKey('microsoft.folder_drive_id'));
    final pending = PendingMicrosoftVault();
    final auth = MicrosoftAuth(client, pending, clientId: microsoftClientId);
    if (root._loginOwner != null) {
      throw const MicrosoftAuthFailure(
        'Outra conta está fazendo login.',
        code: 'login_in_progress',
        stage: 'callback',
      );
    }
    root._loginOwner = this;
    _loginAuth = auth;
    _notify();
    try {
      if (useCode) {
        pendingMicrosoftCode = await auth.requestDeviceCode();
        _notify();
        await auth.completeDeviceLogin(pendingMicrosoftCode!);
      } else {
        await auth.login();
      }
      final identity = await auth.sessionIdentity();
      final drive = await OneDriveClient(
        client,
        MicrosoftSessionTokens(auth, identity),
      ).drive();
      final id = drive['id'];
      if (id is! String || id.isEmpty) {
        throw const MicrosoftAuthFailure(
          'A conta não retornou um OneDrive válido.',
          code: 'drive_response_invalid',
          stage: 'graph_drive',
        );
      }
      if (expectedDrive != null && expectedDrive != id) {
        throw const MicrosoftAuthFailure(
          'Esta fonte pertence a outra conta. Reconecte a conta original ou use Adicionar fonte para uma nova conta.',
          code: 'account_mismatch',
          stage: 'account',
        );
      }
      if (_disposed) {
        throw const MicrosoftAuthFailure(
          'A fonte foi removida durante o login.',
          code: 'source_removed',
          stage: 'account',
        );
      }
      await auth.bindDrive(id, identity);
      await destination.adoptSession(
        (await pending.read('microsoft.session'))!,
        expectedSnapshot: snapshot,
      );
      if (expectedDrive == null) await _clearMicrosoftFolder();
      _driveCache = drive;
      _driveSession = await destination.sessionIdentity();
      microsoftDriveName = drive['name'] as String? ?? 'OneDrive';
    } finally {
      pending.clear();
      root._loginOwner = null;
      pendingMicrosoftCode = null;
      _loginAuth = null;
      _notify();
      root._notify();
    }
  });

  void cancelMicrosoftLogin() {
    _loginAuth?.cancel();
  }

  Future<bool> openMicrosoftVerification() async {
    final code = pendingMicrosoftCode;
    if (code == null) return false;
    try {
      return await openSystemBrowser(code.verificationUri);
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnectMicrosoft() => run(() async {
    await microsoft.disconnect();
    _microsoft = null;
    microsoftDriveName = null;
    _driveCache = null;
    _driveSession = null;
    await _clearMicrosoftFolder();
  });
  bool get microsoftFolderSelected =>
      preferences.getBool(_sourceKey('microsoft.folder_selected')) ??
      preferences.getString(_sourceKey('microsoft.folder_name')) != null;
  Future<void> checkMicrosoftDrive() => run(() async {
    final drive = (await _microsoftContext(force: true)).drive;
    microsoftDriveName = drive['name'] as String? ?? 'OneDrive';
  });
  void _addMicrosoftCheck(String value) {
    microsoftChecks.add(value);
    _notify();
  }

  Future<void> checkMicrosoftConnection() => run(() async {
    microsoftChecks = [];
    microsoftCheckedAt = null;
    _notify();
    final context = await _microsoftContext(force: true);
    _addMicrosoftCheck('Sessão Microsoft e OneDrive: acesso confirmado.');
    final driveId = context.drive['id'] as String;
    if (!microsoftFolderSelected) {
      _addMicrosoftCheck(
        'Escolha a pasta musical para verificar a leitura de músicas.',
      );
      return;
    }
    _checkFolderDrive(driveId);
    final folder =
        preferences.getString(_sourceKey('microsoft.folder_path')) ?? '';
    final metadata = await context.graph.folderMetadata(
      itemId: preferences.getString(_sourceKey('microsoft.folder_id')),
      folderPath: folder,
    );
    if (metadata['folder'] == null) {
      throw const MicrosoftAuthFailure(
        'A seleção não corresponde a uma pasta. Escolha novamente a pasta musical.',
        code: 'folder_invalid',
        stage: 'folder',
      );
    }
    final parentDrive = (metadata['parentReference'] as Map?)?['driveId'];
    if (parentDrive != null && parentDrive != driveId) {
      throw const MicrosoftAuthFailure(
        'A pasta não pertence ao OneDrive desta sessão. Escolha novamente a pasta musical.',
        code: 'folder_account_mismatch',
        stage: 'account',
      );
    }
    await context.tokens.requireCurrent();
    await preferences.setString(
      _sourceKey('microsoft.folder_drive_id'),
      driveId,
    );
    _addMicrosoftCheck('Pasta selecionada: leitura autorizada.');
    final sample = (await store.loadTracks(includeCovers: false))
        .where(
          (t) =>
              t.localPath == null &&
              t.driveId == driveId &&
              t.available &&
              (folder.isEmpty ||
                  t.sourcePath == folder ||
                  t.sourcePath.startsWith('$folder/')),
        )
        .firstOrNull;
    if (sample == null) {
      _addMicrosoftCheck(
        'Nenhuma música indexada nesta pasta. Sincronize e repita a verificação.',
      );
      return;
    }
    final uri = await context.graph.resolve(sample);
    await context.tokens.requireCurrent();
    final bytes = await verifyOneDriveContent(client, uri);
    await context.tokens.requireCurrent();
    _addMicrosoftCheck(
      'Arquivo musical: leitura inicial confirmada ($bytes bytes, sem salvar o áudio).',
    );
    microsoftCheckedAt = DateTime.now();
    _addMicrosoftCheck(
      'Agora teste reproduzir e avançar na música. Repita após fechar e abrir o aplicativo.',
    );
  });

  Future<void> importMicrosoft() async {
    if (busy) return;
    syncingMicrosoft = true;
    syncStatus = 'running';
    syncPages = syncExamined = 0;
    syncTagsRead = syncTagsSkipped = 0;
    syncCurrentFile = '';
    await run(() async {
      imported = 0;
      cancelSync = false;
      final context = await _microsoftContext(force: true);
      final graph = OneDriveClient(
        client,
        context.tokens,
        cancelled: () => cancelSync || _disposed,
      );
      final drive = context.drive;
      final driveId = drive['id'] as String;
      _checkFolderDrive(driveId);
      final existing = {
        for (final row in await store.database.query(
          'tracks',
          columns: [
            ...LibraryStore.metadataColumns,
            '(cover IS NOT NULL OR cover_hash IS NOT NULL) AS has_cover',
          ],
          where: "json_extract(metadata,'\$.driveId')=?",
          whereArgs: [driveId],
        ))
          row['id'] as String: decodeTrackRow(row, applyUser: false),
      };
      final folder =
          preferences.getString(_sourceKey('microsoft.folder_path')) ?? '';
      if (!microsoftFolderSelected) throw StateError('Selecione uma pasta');
      final checkpointKey = microsoftSessionKey;
      var checkpoint = await store.cloudCheckpoint(checkpointKey);
      if (checkpoint != null &&
          (checkpoint['drive'] != driveId || checkpoint['folder'] != folder)) {
        await store.clearCloudCheckpoint(checkpointKey);
        checkpoint = null;
      }
      final pending = <({String? id, String path, String? next})>[
        (
          id: preferences.getString(_sourceKey('microsoft.folder_id')),
          path: folder,
          next: null,
        ),
      ];
      if (checkpoint != null) {
        pending.clear();
        for (final row in checkpoint['pending'] as List) {
          final value = row as Map;
          pending.add((
            id: value['id'] as String?,
            path: value['path'] as String,
            next: value['next'] as String?,
          ));
        }
        syncPages = checkpoint['pages'] as int? ?? 0;
        syncExamined = checkpoint['examined'] as int? ?? 0;
      }
      final visited = ((checkpoint?['visited'] as List?) ?? [])
          .cast<String>()
          .toSet();
      final processed = checkpoint == null
          ? <String>{}
          : await store.cloudSeen(checkpointKey);
      imported = processed.length;
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        if (current.next == null && !visited.add(current.id ?? current.path)) {
          continue;
        }
        final currentPath = current.path.isEmpty
            ? '/drive/root:'
            : current.path;
        Uint8List? folderCover;
        Uri? next = current.next == null ? null : Uri.parse(current.next!);
        do {
          if (cancelSync) throw StateError('Sincronização cancelada');
          final page = await graph.childrenPage(
            itemId: current.id,
            folderPath: current.path,
            next: next,
          );
          final tracks = <Track>[];
          final pageSeen = <String>[];
          if (preferences.getString(_sourceKey('microsoft.folder_drive_id')) ==
              null) {
            await preferences.setString(
              _sourceKey('microsoft.folder_drive_id'),
              driveId,
            );
          }
          syncPages++;
          syncExamined += page.items.length;
          _notify();
          if (folderCover == null) {
            for (final coverName in [
              'cover.jpg',
              'folder.jpg',
              'front.jpg',
              'cover.jpeg',
              'folder.jpeg',
              'front.jpeg',
              'cover.png',
              'folder.png',
              'front.png',
            ]) {
              final coverItem = page.items
                  .where(
                    (item) =>
                        (item['name'] as String? ?? '').toLowerCase() ==
                            coverName &&
                        item['remoteItem'] == null &&
                        ((item['parentReference'] as Map?)?['driveId'] ??
                                driveId) ==
                            driveId,
                  )
                  .firstOrNull;
              if (coverItem != null) {
                folderCover = await graph.folderArtwork(coverItem, driveId);
              }
              if (folderCover != null) break;
            }
          }
          Future<void> processItem(Map<String, dynamic> item) async {
            if (item['deleted'] != null) return;
            if (item['folder'] != null) {
              if (item['remoteItem'] == null) {
                pending.add((
                  id: item['id'] as String,
                  next: null,
                  path:
                      '${current.path.isEmpty ? "/drive/root:" : current.path}/${item['name'] as String}',
                ));
              }
              return;
            }
            final name = item['name'] as String? ?? '';
            if (!RegExp(
              r'\.(mp3|flac|m4a|ogg|opus|wav)$',
              caseSensitive: false,
            ).hasMatch(name)) {
              return;
            }
            final audio = item['audio'] as Map<String, dynamic>? ?? {};
            final parent =
                item['parentReference'] as Map<String, dynamic>? ?? {};
            final parentPath = current.path.isEmpty
                ? '/drive/root:'
                : current.path;
            if (cancelSync) throw StateError('Sincronização cancelada');
            final drive = parent['driveId'] as String? ?? driveId;
            if (drive != driveId || item['remoteItem'] != null) return;
            final id = item['id'] as String?;
            if (id == null) return;
            final previous = existing['onedrive:$drive:$id'];
            final revision = item['eTag'] as String? ?? '';
            syncCurrentFile = name;
            if (processed.length % 25 == 0) _notify();
            CloudTags? embedded;
            if (previous?.cloudTagsVersion == 1 &&
                revision.isNotEmpty &&
                previous?.revision == revision) {
              embedded = CloudTags(
                title: previous!.title,
                artists: previous.hasScrobbleMetadata
                    ? previous.artistNames
                    : const [],
                album: previous.album,
                albumArtists: previous.albumArtists.isEmpty
                    ? (previous.albumArtist.isEmpty
                          ? []
                          : [previous.albumArtist])
                    : previous.albumArtists,
                genres: previous.genreNames,
                year: previous.year,
                trackNumber: previous.trackNumber,
                discNumber: previous.discNumber,
                duration: previous.duration,
                cover: null,
                albumId: previous.albumId,
                edition: previous.edition,
              );
            } else if (RegExp(
              r'\.(mp3|flac)$',
              caseSensitive: false,
            ).hasMatch(name)) {
              try {
                final uri = await graph.resolve(
                  Track(
                    id: 'onedrive:$drive:$id',
                    title: '',
                    artist: '',
                    driveId: drive,
                    itemId: id,
                  ),
                );
                await context.tokens.requireCurrent();
                embedded = await CloudMetadataReader(
                  client,
                  cancelled: () => cancelSync || _disposed,
                ).read(uri, name, fileSize: (item['size'] as num?)?.toInt());
              } catch (_) {
                // Optional tags do not erase a track or its known metadata.
              }
            }
            if (embedded != null) {
              syncTagsRead++;
            } else {
              syncTagsSkipped++;
            }
            final cover =
                (previous?.cloudCoverEmbedded == true &&
                    revision.isNotEmpty &&
                    previous?.revision == revision)
                ? null
                : embedded?.cover ??
                      folderCover ??
                      (previous?.hasArtwork == true &&
                              revision.isNotEmpty &&
                              previous?.revision == revision
                          ? null
                          : await graph.thumbnail(item) ??
                                folderCover ??
                                previous?.cover);
            if (cancelSync) throw StateError('Sincronização cancelada');
            String tag(String key, String fallback) {
              final valueFromFile = switch (key) {
                'title' => embedded?.title,
                'artist' => embedded?.artists.firstOrNull,
                'album' => embedded?.album,
                'albumArtist' => embedded?.albumArtists.firstOrNull,
                'genre' => embedded?.genres.join('; '),
                _ => null,
              };
              if (valueFromFile != null && valueFromFile.trim().isNotEmpty) {
                return valueFromFile;
              }
              final value = audio[key] as String?;
              return value == null || value.trim().isEmpty
                  ? fallback
                  : value.trim();
            }

            int? positiveTag(String key, int? fallback) {
              final valueFromFile = switch (key) {
                'duration' => embedded?.duration?.inMilliseconds,
                'year' => embedded?.year,
                'track' => embedded?.trackNumber,
                'disc' => embedded?.discNumber,
                _ => null,
              };
              if (valueFromFile != null && valueFromFile > 0) {
                return valueFromFile;
              }
              final value = audio[key] as num?;
              return value != null && value > 0 ? value.toInt() : fallback;
            }

            List<String> relations(
              List<String>? fromFile,
              String key,
              List<String>? known,
            ) {
              if (fromFile != null && fromFile.isNotEmpty) return fromFile;
              final value = audio[key] as String?;
              return value != null && value.trim().isNotEmpty
                  ? const []
                  : known ?? const [];
            }

            processed.add('onedrive:$drive:$id');
            pageSeen.add('onedrive:$drive:$id');
            tracks.add(
              Track(
                id: 'onedrive:$drive:$id',
                title: tag(
                  'title',
                  previous?.title ?? name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
                ),
                artist: tag(
                  'artist',
                  previous?.artist ?? 'Artista desconhecido',
                ),
                album: tag('album', previous?.album ?? ''),
                albumArtist: tag('albumArtist', previous?.albumArtist ?? ''),
                genre: tag('genre', previous?.genre ?? ''),
                artists: relations(
                  embedded?.artists,
                  'artist',
                  previous?.artists,
                ),
                albumArtists: relations(
                  embedded?.albumArtists,
                  'albumArtist',
                  previous?.albumArtists,
                ),
                genres: relations(embedded?.genres, 'genre', previous?.genres),
                albumId: embedded?.albumId.isNotEmpty == true
                    ? embedded!.albumId
                    : previous?.albumId ?? '',
                edition: embedded?.edition.isNotEmpty == true
                    ? embedded!.edition
                    : previous?.edition ?? '',
                cover: cover,
                format: name.split('.').last.toUpperCase(),
                sourceProvider: 'onedrive',
                sourceAccount: driveId,
                duration: Duration(
                  milliseconds:
                      positiveTag(
                        'duration',
                        previous?.duration.inMilliseconds,
                      ) ??
                      0,
                ),
                year: positiveTag('year', previous?.year),
                trackNumber: positiveTag('track', previous?.trackNumber),
                discNumber: positiveTag('disc', previous?.discNumber),
                sourcePath: parentPath,
                fileName: name,
                cloudTagsVersion: embedded == null ? 0 : 1,
                cloudCoverEmbedded:
                    embedded?.cover != null ||
                    (previous?.cloudCoverEmbedded == true &&
                        previous?.revision == revision),
                revision: revision,
                driveId: drive,
                itemId: id,
              ),
            );
            if (tracks.length >= 12) {
              final chunk = List<Track>.of(tracks);
              tracks.clear();
              await context.tokens.requireCurrent();
              await store.addTracks(chunk, preserveCovers: true);
            }
          }

          var itemIndex = 0;
          Future<void> worker() async {
            while (itemIndex < page.items.length) {
              if (cancelSync || _disposed) {
                throw StateError('Sincroniza??o cancelada');
              }
              final item = page.items[itemIndex++];
              await processItem(item);
            }
          }

          await Future.wait(List.generate(3, (_) => worker()));
          await context.tokens.requireCurrent();
          await store.addTracks(tracks, preserveCovers: true);
          final remaining = [
            ...pending,
            if (page.nextLink != null)
              (
                id: current.id,
                path: current.path,
                next: page.nextLink.toString(),
              ),
          ];
          await store.saveCloudCheckpoint(checkpointKey, {
            'drive': driveId,
            'folder': folder,
            'pending': [
              for (final node in remaining)
                {'id': node.id, 'path': node.path, 'next': node.next},
            ],
            'visited': visited.toList(),
            'pages': syncPages,
            'examined': syncExamined,
          }, pageSeen);
          imported = processed.length;
          _notify();
          next = page.nextLink;
          if (cancelSync) throw StateError('Sincronização cancelada');
        } while (next != null);
        if (folderCover != null) {
          await context.tokens.requireCurrent();
          await store.setMissingFolderCover(driveId, currentPath, folderCover);
        }
      }
      if (cancelSync) throw StateError('Sincronização cancelada');
      await context.tokens.requireCurrent();
      await store.finishOneDriveFolder(driveId, folder, processed);
      final catalog = await store.loadTracks(
        includeCovers: false,
        includeHidden: true,
      );
      final scoped = catalog
          .where(
            (track) =>
                track.sourceProvider == 'onedrive' &&
                track.sourceAccount == driveId &&
                track.available &&
                (folder.isEmpty ||
                    track.sourcePath == folder ||
                    track.sourcePath.startsWith('$folder/')),
          )
          .toList();
      final total = scoped.length;
      final saved = await preferences.setString(
        _sourceKey('microsoft.sync_summary'),
        jsonEncode({
          'folder':
              preferences.getString(_sourceKey('microsoft.folder_name')) ??
              'Toda a conta',
          'completedAt': DateTime.now().toIso8601String(),
          'processed': imported,
          'total': total,
          'covers': scoped.where((t) => t.hasArtwork).length,
          'tagsRead': syncTagsRead,
          'tagsSkipped': syncTagsSkipped,
          'unknownArtists': scoped.where((t) => !t.hasScrobbleMetadata).length,
          'unknownAlbums': scoped.where((t) => t.album.isEmpty).length,
          'pages': syncPages,
        }),
      );
      if (!saved) throw StateError('Resumo não salvo');
      await store.clearCloudCheckpoint(checkpointKey);
    });
    if (errorCode == 'http_400' || errorCode == 'http_410') {
      await store.clearCloudCheckpoint(microsoftSessionKey);
    }
    syncingMicrosoft = false;
    syncCurrentFile = '';
    syncStatus = error == null
        ? 'completed'
        : cancelSync
        ? 'cancelled'
        : 'failed';
    _notify();
  }

  Future<List<Map<String, dynamic>>> folders({String? itemId}) async {
    final context = await _microsoftContext();
    final result = await context.graph.folders(itemId: itemId);
    await context.tokens.requireCurrent();
    return result;
  }

  static String folderCatalogPath(Map<String, dynamic> folder) =>
      folder['catalogPath'] as String? ??
      '${Uri.decodeComponent((folder['parentReference'] as Map?)?['path'] as String? ?? '/drive/root:')}/${folder['name'] as String}';
  String get selectedFolderLabel {
    if (!microsoftFolderSelected) return 'Nenhuma pasta selecionada';
    final value =
        preferences.getString(_sourceKey('microsoft.folder_path')) ?? '';
    return value.isEmpty
        ? 'Raiz do OneDrive (todas as pastas)'
        : value.substring(value.indexOf(':') + 1);
  }

  bool folderIsSelected(Map<String, dynamic> folder) =>
      microsoftFolderSelected &&
      (preferences.getString(_sourceKey('microsoft.folder_id')) ==
              folder['id'] ||
          preferences.getString(_sourceKey('microsoft.folder_path')) ==
              folderCatalogPath(folder));
  bool folderIsIncluded(Map<String, dynamic> folder) {
    if (!microsoftFolderSelected) return false;
    final selected =
        preferences.getString(_sourceKey('microsoft.folder_path')) ?? '';
    final candidate = folderCatalogPath(folder);
    return selected.isEmpty ||
        candidate == selected ||
        candidate.startsWith('$selected/');
  }

  Future<void> selectFolder(Map<String, dynamic>? folder) async {
    final context = await _microsoftContext();
    final driveId = context.drive['id'] as String;
    final parentDrive = (folder?['parentReference'] as Map?)?['driveId'];
    if (parentDrive != null && parentDrive != driveId) {
      throw const MicrosoftAuthFailure(
        'Esta pasta pertence a outra conta. Abra o seletor novamente.',
        code: 'folder_account_mismatch',
        stage: 'account',
      );
    }
    await context.tokens.requireCurrent();
    await preferences.setString(
      _sourceKey('microsoft.folder_drive_id'),
      driveId,
    );
    await preferences.setBool(_sourceKey('microsoft.folder_selected'), true);
    if (folder == null) {
      await preferences.remove(_sourceKey('microsoft.folder_id'));
      await preferences.setString(_sourceKey('microsoft.folder_path'), '');
      await preferences.setString(
        _sourceKey('microsoft.folder_name'),
        'Raiz do OneDrive (todas as pastas)',
      );
      _notify();
      await registerMicrosoftFolder();
      return;
    }
    await preferences.setString(
      _sourceKey('microsoft.folder_id'),
      folder['id'] as String,
    );
    await preferences.setString(
      _sourceKey('microsoft.folder_path'),
      folderCatalogPath(folder),
    );
    await preferences.setString(
      _sourceKey('microsoft.folder_name'),
      folder['name'] as String,
    );
    _notify();
    await registerMicrosoftFolder();
  }

  Future<LastFmClient> lastfm() async => LastFmClient(
    client,
    apiKey: await vault.read('lastfm.api_key') ?? '',
    apiSecret: await vault.read('lastfm.api_secret') ?? '',
    sessionKey: await vault.read('lastfm.session'),
  );
  Future<void> beginLastfm() => run(() async {
    final api = await lastfm();
    pendingLastfmToken = await api.requestToken();
    if (!await openSystemBrowser(api.authorizationUrl(pendingLastfmToken!))) {
      throw StateError('Navegador indisponível');
    }
  });
  Future<void> finishLastfm() => run(() async {
    if (pendingLastfmToken == null) {
      throw StateError('Inicie a autorização primeiro');
    }
    final api = await lastfm();
    await vault.write(
      'lastfm.session',
      await api.exchangeToken(pendingLastfmToken!),
    );
    pendingLastfmToken = null;
    await store.reconnectScrobbles();
  });
  Future<void> disconnectLastfm() => run(() async {
    _lastfmEpoch++;
    _lastfmStatusFuture = null;
    await vault.delete('lastfm.session');
    lastfmConnected = false;
    lastfmStatusLoading = false;
    pendingLastfmToken = null;
    await store.reconnectScrobbles();
  });
  void observe(ListeningSession session) {
    if (_disposed ||
        session.listened <= Duration.zero ||
        !session.track.hasScrobbleMetadata) {
      return;
    }
    final id = '${session.track.id}|${session.startedAt.toIso8601String()}';
    if (!(preferences.getBool('visual.offline_only') ?? false) &&
        (preferences.getBool('lastfm.now_playing') ?? false) &&
        _nowPlaying.add(id)) {
      unawaited(
        lastfm().then((api) => api.nowPlaying(session.track)).catchError((
          Object _,
        ) {
          error = 'Now playing não foi enviado. Confira a sessão Last.fm.';
          _notify();
        }),
      );
    }
    if (!(preferences.getBool('lastfm.scrobbling') ?? false) ||
        !session.eligible ||
        !_observed.add(id)) {
      return;
    }
    final duration = session.duration > Duration.zero
        ? session.duration
        : session.track.duration;
    unawaited(
      store
          .enqueueScrobble(session.track, session.startedAt, duration)
          .then((_) => flushScrobbles())
          .catchError((Object _) {
            _observed.remove(id);
            error = 'Não foi possível registrar scrobble localmente.';
            _notify();
          }),
    );
  }

  Future<void> flushScrobbles() async {
    if (_disposed ||
        suspended ||
        (preferences.getBool('visual.offline_only') ?? false) ||
        _flushing ||
        !(preferences.getBool('lastfm.scrobbling') ?? false)) {
      return;
    }
    _flushing = true;
    try {
      final api = await lastfm();
      if (api.sessionKey == null || api.sessionKey!.isEmpty) return;
      for (final row in await store.pendingScrobbles()) {
        if (_disposed ||
            suspended ||
            (preferences.getBool('visual.offline_only') ?? false)) {
          break;
        }
        final id = row['id'] as String;
        final attempts = (row['attempts'] as int) + 1;
        await store.updateScrobble(id, 'sending', attempts);
        try {
          await api.submit(
            Track(
              id: row['track_id'] as String,
              title: row['title'] as String,
              artist: row['artist'] as String,
              album: row['album'] as String,
            ),
            DateTime.parse(row['started_at'] as String),
            Duration(milliseconds: row['duration_ms'] as int),
          );
          await store.updateScrobble(id, 'sent', attempts);
        } on LastFmIgnoredException {
          await store.updateScrobble(
            id,
            'rejected',
            attempts,
            error: 'Scrobble ignorado pelo Last.fm.',
          );
        } on LastFmException catch (failure) {
          if (failure.requiresLogin) {
            await store.updateScrobble(
              id,
              'auth_required',
              attempts,
              error: 'Reconecte o Last.fm.',
            );
            break;
          }
          if (failure.retryable) {
            final delay = min(3600, 30 * pow(2, min(attempts, 7)).toInt());
            await store.updateScrobble(
              id,
              'pending',
              attempts,
              error: 'Serviço temporariamente indisponível.',
              nextAttempt: DateTime.now().toUtc().add(Duration(seconds: delay)),
            );
          } else {
            await store.updateScrobble(
              id,
              'rejected',
              attempts,
              error: 'Last.fm rejeitou o envio (código ${failure.code}).',
            );
          }
        } catch (_) {
          await store.updateScrobble(
            id,
            'ambiguous',
            attempts,
            error: 'Resposta desconhecida. Envio não será repetido automaticamente.',
          );
        }
      }
    } on MicrosoftAuthFailure catch (failure) {
      error = failure.message;
    } catch (_) {
      error = 'Fila Last.fm não processada. Confira conexão e sessão.';
    } finally {
      _flushing = false;
      _notify();
    }
  }

  @override
  Future<Uri> resolve(Track track) async {
    if (additionalSourceTypes.containsKey(track.provider)) {
      return additional.resolve(track);
    }
    if (track.localPath != null) {
      return Uri.file(track.localPath!);
    }
    if (accountRoot == null) {
      for (final source in microsoftSources) {
        final drive = await source.microsoft.boundDriveId();
        if (drive == track.driveId) {
          return source._resolveMicrosoft(track);
        }
      }
      if (await microsoft.boundDriveId() == null) {
        var legacySession = false;
        try {
          await microsoft.sessionIdentity();
          legacySession = true;
        } on MicrosoftAuthFailure {
          // No credentials: never fall back to another account's session.
        }
        if (legacySession) return _resolveMicrosoft(track);
      }
      if (_microsoftSources.isNotEmpty) {
        throw const MediaSourceFailure(
          'A conta desta música não está conectada. Reconecte a fonte correspondente; downloads locais continuam disponíveis.',
        );
      }
    }
    return _resolveMicrosoft(track);
  }

  Future<String?> lyrics(Track track) async {
    if (track.provider != 'onedrive') return null;
    if (preferences.getBool('visual.offline_only') ?? false) return null;
    if (accountRoot == null) {
      for (final source in microsoftSources) {
        if (await source.microsoft.boundDriveId() == track.driveId) {
          return source.lyrics(track);
        }
      }
    }
    final context = await _microsoftContext();
    if (context.drive['id'] != track.driveId) {
      throw const MediaSourceFailure(
        'Reconnect the source account for this track.',
      );
    }
    final result = await context.graph.lyrics(track);
    await context.tokens.requireCurrent();
    return result;
  }

  Future<Uri> _resolveMicrosoft(Track track) async {
    try {
      final context = await _microsoftContext();
      if (track.driveId != context.drive['id']) {
        throw const MicrosoftAuthFailure(
          'Esta música pertence a outra conta OneDrive. Conecte a conta correspondente para reproduzi-la; os downloads locais continuam disponíveis.',
          code: 'track_account_mismatch',
          stage: 'account',
        );
      }
      final uri = await context.graph.resolve(track);
      await context.tokens.requireCurrent();
      return uri;
    } on MicrosoftAuthFailure catch (failure) {
      throw MediaSourceFailure(failure.message);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _profileIndex?.dispose();
    _additional?.dispose();
    _worker?.cancel();
    _loginAuth?.cancel();
    for (final source in _microsoftSources.values) {
      source.dispose();
    }
    if (accountRoot == null) client.close();
    super.dispose();
  }
}
