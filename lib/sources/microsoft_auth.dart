import '../domain/onedrive_identity.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../domain/ports.dart';

abstract interface class SecretVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SystemVault implements SecretVault {
  const SystemVault({this.prefix = 'music_time.'});
  final String prefix;
  static const storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: '$prefix$key');
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: '$prefix$key', value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: '$prefix$key');
}

String secureRandomString() =>
    base64UrlEncode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
String pkceChallenge(String verifier) =>
    base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');

typedef OpenBrowser = Future<bool> Function(Uri uri);
Future<bool> openSystemBrowser(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class MicrosoftAuthFailure implements Exception {
  const MicrosoftAuthFailure(
    this.message, {
    this.code = 'unknown',
    this.stage = 'oauth',
  });
  final String message;
  final String code, stage;
}

class MicrosoftDeviceCode {
  MicrosoftDeviceCode({
    required this.userCode,
    required this.verificationUri,
    required this._deviceCode,
    required this.expiresAt,
    required this.interval,
  });
  final String userCode, _deviceCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final Duration interval;
}

class MicrosoftAuth implements RefreshableAccessTokenProvider {
  MicrosoftAuth(
    this.client,
    this.vault, {
    required this.clientId,
    this.sessionKey = 'microsoft.session',
    this.browser = openSystemBrowser,
    this.wait = Future<void>.delayed,
  });
  final http.Client client;
  final SecretVault vault;
  final String clientId;
  final String sessionKey;

  Future<String?> boundDriveId() async {
    try {
      final data = _decodeSession(await vault.read(sessionKey));
      return data['client_id'] == clientId &&
              data['access_token'] is String &&
              (data['access_token'] as String).isNotEmpty &&
              data['drive_id'] is String &&
              (data['drive_id'] as String).isNotEmpty
          ? oneDriveIdentity(data['drive_id'] as String)
          : null;
    } on MicrosoftAuthFailure {
      return null;
    }
  }

  /// Commit verified browser login only if the previous credentials are intact.
  Future<void> adoptSession(String encoded, {String? expectedSnapshot}) =>
      _writeSession(() async {
        if (await vault.read(sessionKey) != expectedSnapshot) {
          throw const MicrosoftAuthFailure(
            'A sessão mudou durante o login. Tente novamente.',
            code: 'session_changed',
            stage: 'session',
          );
        }
        final data = _decodeSession(encoded);
        if (data['client_id'] != clientId ||
            data['access_token'] is! String ||
            (data['access_token'] as String).isEmpty ||
            data['drive_id'] is! String) {
          throw const MicrosoftAuthFailure(
            'O login não identificou um OneDrive válido.',
            code: 'session_invalid',
            stage: 'session',
          );
        }
        await vault.write(sessionKey, encoded);
      });
  final OpenBrowser browser;
  final Future<void> Function(Duration) wait;
  final _cancelled = Completer<void>();
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  static const scope = 'https://graph.microsoft.com/Files.Read offline_access';
  static final redirect = Uri.parse('http://localhost:42813/oauth');
  static final tokenEndpoint = Uri.parse(
    'https://login.microsoftonline.com/consumers/oauth2/v2.0/token',
  );
  Future<String>? _refresh;
  String? _usedSession;
  static final _sessionWrites = Expando<Future<void>>();
  Future<T> _writeSession<T>(Future<T> Function() action) async {
    final previous = _sessionWrites[vault] ?? Future<void>.value();
    final done = Completer<void>();
    _sessionWrites[vault] = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Map<String, dynamic> _decodeSession(String? saved) {
    if (saved == null) return {};
    try {
      return jsonDecode(saved) as Map<String, dynamic>;
    } catch (_) {
      throw const MicrosoftAuthFailure(
        'A sessão Microsoft salva está inválida. Reconecte pelo navegador.',
        code: 'session_invalid',
        stage: 'session',
      );
    }
  }

  String _identity(Map<String, dynamic> data) =>
      data['session_id'] is String && (data['session_id'] as String).isNotEmpty
      ? data['session_id'] as String
      : sha256
            .convert(
              utf8.encode('${data['client_id']}:${data['access_token']}'),
            )
            .toString();
  Future<String> sessionIdentity() async {
    final data = _decodeSession(await vault.read(sessionKey));
    if (data['client_id'] != clientId ||
        data['access_token'] is! String ||
        (data['access_token'] as String).isEmpty) {
      throw const MicrosoftAuthFailure(
        'Conecte novamente a conta Microsoft pelo navegador.',
        code: 'session_missing',
        stage: 'session',
      );
    }
    return _identity(data);
  }

  Future<void> bindDrive(String driveId, String expectedSession) =>
      _writeSession(() async {
        final data = _decodeSession(await vault.read(sessionKey));
        if (data['client_id'] != clientId ||
            _identity(data) != expectedSession) {
          throw const MicrosoftAuthFailure(
            'A sessão Microsoft mudou durante a operação. Tente novamente.',
            code: 'session_changed',
            stage: 'session',
          );
        }
        if (data['drive_id'] != null &&
            !sameOneDrive(data['drive_id'] as String, driveId)) {
          throw const MicrosoftAuthFailure(
            'O OneDrive retornado não corresponde à sessão salva. Reconecte a conta pelo navegador.',
            code: 'account_mismatch',
            stage: 'account',
          );
        }
        data['session_id'] = expectedSession;
        data['drive_id'] = oneDriveIdentity(driveId);
        await vault.write(sessionKey, jsonEncode(data));
      });

  Uri authorizationUri(String state, String verifier) => Uri.https(
    'login.microsoftonline.com',
    '/consumers/oauth2/v2.0/authorize',
    {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirect.toString(),
      'response_mode': 'query',
      'scope': scope,
      'state': state,
      'code_challenge': pkceChallenge(verifier),
      'code_challenge_method': 'S256',
      'prompt': 'select_account',
    },
  );

  void validateClientId() {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(clientId)) {
      throw const MicrosoftAuthFailure(
        'O login Microsoft não está configurado corretamente nesta instalação do Music Time.',
      );
    }
  }

  MicrosoftAuthFailure failure(String? code) =>
      MicrosoftAuthFailure(switch (code) {
        'invalid_client' || 'unauthorized_client' => 'O registro Microsoft não permite este login. Confira o Client ID, o suporte a contas pessoais e habilite fluxos de cliente público em Autenticação.',
        'invalid_scope' => 'O registro Microsoft precisa da permissão delegada Files.Read do Microsoft Graph.',
        'authorization_declined' || 'access_denied' => 'A autorização foi recusada. Inicie novamente e permita a leitura dos seus arquivos.',
        'expired_token' =>
          'O código expirou. Clique em Conectar para gerar outro.',
        'bad_verification_code' =>
          'O código não é mais válido. Inicie uma nova conexão.',
        'invalid_grant' =>
          'A sessão expirou ou foi revogada. Conecte novamente a conta.',
        'interaction_required' || 'login_required' || 'consent_required' => 'A Microsoft exige uma nova autorização. Conecte novamente pelo navegador.',
        'temporarily_unavailable' || 'server_error' => 'A Microsoft está temporariamente indisponível. Tente novamente mais tarde.',
        _ => 'A Microsoft não concluiu o login. Confira o registro do aplicativo e tente novamente.',
      }, code: code ?? 'unknown');

  MicrosoftAuthFailure responseFailure(Map<String, dynamic> data) {
    final codes = data['error_codes'] as List? ?? [];
    for (final code in codes) {
      final message = switch (code) {
        50011 => 'O retorno do navegador não corresponde ao registro. Registre http://localhost:42813/oauth em Aplicativos móveis e desktop.',
        700016 => 'O registro do Music Time não foi encontrado. Confira a configuração do aplicativo.',
        50020 => 'Este registro não aceita a conta escolhida. Use uma conta Microsoft pessoal e um registro que aceite contas pessoais.',
        53003 => 'Uma política da organização bloqueou o acesso. Use a conta pessoal ou consulte o administrador.',
        7000218 => 'O registro exige segredo de cliente. Configure o Music Time como aplicativo público/nativo.',
        _ => null,
      };
      if (message != null) {
        return MicrosoftAuthFailure(message, code: 'AADSTS$code');
      }
    }
    return failure(data['error'] as String?);
  }

  Map<String, dynamic> responseData(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const MicrosoftAuthFailure(
        'A Microsoft retornou uma resposta inválida. Tente novamente.',
      );
    }
  }

  Future<MicrosoftDeviceCode> requestDeviceCode() async {
    validateClientId();
    final response = await client
        .post(
          Uri.parse(
            'https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode',
          ),
          body: {'client_id': clientId, 'scope': scope},
        )
        .timeout(const Duration(seconds: 30));
    final data = responseData(response);
    if (response.statusCode != 200) throw responseFailure(data);
    final uri = Uri.tryParse(data['verification_uri'] as String? ?? '');
    final code = data['device_code'], userCode = data['user_code'];
    final seconds = (data['expires_in'] as num? ?? 0).toInt();
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        !{
          'microsoft.com',
          'www.microsoft.com',
          'login.microsoftonline.com',
        }.contains(uri.host) ||
        code is! String ||
        code.isEmpty ||
        userCode is! String ||
        userCode.isEmpty ||
        seconds <= 0) {
      throw const MicrosoftAuthFailure(
        'A Microsoft não retornou um código válido. Tente novamente.',
      );
    }
    return MicrosoftDeviceCode(
      userCode: userCode,
      verificationUri: uri,
      deviceCode: code,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
      interval: Duration(
        seconds: ((data['interval'] as num? ?? 5).toInt()).clamp(1, 2147483647),
      ),
    );
  }

  void checkCancellation() {
    if (_cancelled.isCompleted) {
      throw const MicrosoftAuthFailure('Conexão cancelada.');
    }
  }

  Future<void> completeDeviceLogin(MicrosoftDeviceCode code) async {
    var interval = code.interval;
    while (true) {
      checkCancellation();
      final remaining = code.expiresAt.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) throw failure('expired_token');
      await Future.any<void>([
        wait(interval < remaining ? interval : remaining),
        _cancelled.future,
      ]);
      checkCancellation();
      if (!DateTime.now().toUtc().isBefore(code.expiresAt)) {
        throw failure('expired_token');
      }
      final response = await client
          .post(
            tokenEndpoint,
            body: {
              'client_id': clientId,
              'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
              'device_code': code._deviceCode,
            },
          )
          .timeout(const Duration(seconds: 30));
      checkCancellation();
      final data = responseData(response);
      if (response.statusCode == 200) {
        await storeToken(data);
        return;
      }
      final error = data['error'] as String?;
      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        interval += const Duration(seconds: 5);
        continue;
      }
      throw failure(error);
    }
  }

  Future<void> login() async {
    validateClientId();
    final verifier = secureRandomString();
    final state = secureRandomString();
    final callback = Completer<Map<String, String>>();
    checkCancellation();
    final HttpServer server;
    try {
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        redirect.port,
      );
    } on SocketException {
      throw const MicrosoftAuthFailure(
        'Não foi possível receber o retorno do navegador. A porta local pode estar em uso. Feche outras tentativas de conexão e tente novamente pelo navegador.',
      );
    }
    final subscription = server.listen((request) async {
      if (request.method != 'GET' ||
          request.uri.path != redirect.path ||
          request.uri.queryParameters['state'] != state ||
          request.uri.queryParametersAll['state']?.length != 1 ||
          (request.uri.queryParametersAll['code']?.length ?? 0) > 1 ||
          (request.uri.queryParameters.containsKey('code') &&
              request.uri.queryParameters.containsKey('error'))) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Resposta de autenticação inválida.');
        await request.response.close();
        return;
      }
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.headers.set(
        'Content-Security-Policy',
        "default-src 'none'",
      );
      request.response.write(
        'Music Time: pode fechar esta janela e voltar ao aplicativo.',
      );
      await request.response.close();
      if (!callback.isCompleted) callback.complete(request.uri.queryParameters);
    });
    try {
      if (!await browser(authorizationUri(state, verifier))) {
        throw const MicrosoftAuthFailure(
          'Não foi possível abrir o navegador. Feche outras tentativas de conexão e tente novamente pelo navegador.',
        );
      }
      final parameters =
          await Future.any<Map<String, String>>([
            callback.future,
            _cancelled.future.then<Map<String, String>>(
              (_) => throw const MicrosoftAuthFailure('Conexão cancelada.'),
            ),
          ]).timeout(
            const Duration(minutes: 5),
            onTimeout: () => throw const MicrosoftAuthFailure(
              'O login demorou demais. Feche outras tentativas de conexão e tente novamente pelo navegador.',
            ),
          );
      checkCancellation();
      final code = parameters['code'];
      if (code == null || code.isEmpty) throw failure(parameters['error']);
      await _token({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirect.toString(),
        'code_verifier': verifier,
      });
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<String> _token(
    Map<String, String> fields, {
    String? expectedSession,
  }) async {
    final response = await client
        .post(
          tokenEndpoint,
          body: {'client_id': clientId, 'scope': scope, ...fields},
        )
        .timeout(const Duration(seconds: 30));
    final data = responseData(response);
    if (response.statusCode != 200) {
      final code = data['error'] as String?;
      if (fields['grant_type'] == 'refresh_token' &&
          {
            'invalid_grant',
            'interaction_required',
            'login_required',
            'consent_required',
          }.contains(code)) {
        await disconnect(expectedSession: expectedSession);
      }
      throw responseFailure(data);
    }
    checkCancellation();
    return storeToken(
      data,
      allowPreviousRefresh: fields['grant_type'] == 'refresh_token',
      expectedSession: expectedSession,
    );
  }

  Future<String> storeToken(
    Map<String, dynamic> data, {
    bool allowPreviousRefresh = false,
    String? expectedSession,
  }) => _writeSession(() async {
    if (data['access_token'] is! String ||
        (data['access_token'] as String).isEmpty) {
      throw const MicrosoftAuthFailure(
        'Microsoft não retornou uma sessão válida.',
      );
    }
    final previous = await vault.read(sessionKey);
    final old = allowPreviousRefresh
        ? _decodeSession(previous)
        : <String, dynamic>{};
    if (expectedSession != null &&
        (old['client_id'] != clientId || _identity(old) != expectedSession)) {
      throw const MicrosoftAuthFailure(
        'A sessão Microsoft mudou. A renovação anterior foi descartada; tente novamente.',
        code: 'session_changed',
        stage: 'session',
      );
    }
    final renewing = allowPreviousRefresh && old['client_id'] == clientId;
    await vault.write(
      sessionKey,
      jsonEncode({
        'client_id': clientId,
        'session_id': renewing ? _identity(old) : secureRandomString(),
        if (renewing && old['drive_id'] is String) 'drive_id': old['drive_id'],
        'access_token': data['access_token'],
        'refresh_token':
            data['refresh_token'] ??
            (allowPreviousRefresh && old['client_id'] == clientId
                ? old['refresh_token']
                : null),
        'expires_at': DateTime.now()
            .toUtc()
            .add(
              Duration(seconds: (data['expires_in'] as num? ?? 3600).toInt()),
            )
            .toIso8601String(),
      }),
    );
    return data['access_token'] as String;
  });

  @override
  Future<String> accessToken() async {
    final saved = await vault.read(sessionKey);
    if (saved == null) {
      throw const MicrosoftAuthFailure(
        'Conecte o OneDrive pelo navegador em Configurações → Fontes.',
        code: 'session_missing',
        stage: 'session',
      );
    }
    final data = _decodeSession(saved);
    if (data['client_id'] != clientId) {
      throw const MicrosoftAuthFailure(
        'O registro Microsoft mudou. Reconecte a conta.',
        code: 'client_changed',
        stage: 'session',
      );
    }
    _usedSession = _identity(data);
    final expires = DateTime.tryParse(data['expires_at'] as String? ?? '');
    if (expires != null &&
        expires.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        )) {
      return data['access_token'] as String;
    }
    final refresh = data['refresh_token'];
    if (refresh is! String || refresh.isEmpty) {
      throw const MicrosoftAuthFailure(
        'Reconecte a conta Microsoft pelo navegador.',
        code: 'refresh_missing',
        stage: 'session',
      );
    }
    if (_refresh != null) return _refresh!;
    final pending = _token({
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
    }, expectedSession: _identity(data));
    _refresh = pending;
    try {
      return await pending;
    } finally {
      _refresh = null;
    }
  }

  @override
  Future<void> invalidateAccessToken() => _writeSession(() async {
    final saved = await vault.read(sessionKey);
    if (saved == null) return;
    final data = _decodeSession(saved);
    if (data['client_id'] != clientId ||
        (_usedSession != null && _identity(data) != _usedSession)) {
      return;
    }
    data['expires_at'] = '2000-01-01T00:00:00Z';
    await vault.write(sessionKey, jsonEncode(data));
  });

  Future<void> disconnect({String? expectedSession}) => _writeSession(() async {
    if (expectedSession != null) {
      final data = _decodeSession(await vault.read(sessionKey));
      if (data['client_id'] != clientId || _identity(data) != expectedSession) {
        return;
      }
    }
    await vault.delete(sessionKey);
  });
}

/// A request already started must not silently switch to a replacement login.
class MicrosoftSessionTokens implements RefreshableAccessTokenProvider {
  MicrosoftSessionTokens(this.auth, this.identity);
  final MicrosoftAuth auth;
  final String identity;
  Future<void> requireCurrent() async {
    if (await auth.sessionIdentity() != identity) {
      throw const MicrosoftAuthFailure(
        'A conta Microsoft mudou durante a operação. Tente novamente.',
        code: 'session_changed',
        stage: 'session',
      );
    }
  }

  @override
  Future<String> accessToken() async {
    await requireCurrent();
    final token = await auth.accessToken();
    await requireCurrent();
    return token;
  }

  @override
  Future<void> invalidateAccessToken() async {
    await requireCurrent();
    await auth.invalidateAccessToken();
    await requireCurrent();
  }
}
