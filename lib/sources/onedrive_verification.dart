import 'dart:async';

import 'package:http/http.dart' as http;

import 'microsoft_auth.dart';
import '../infrastructure/onedrive.dart';

/// Reads only a small range; neither audio bytes nor temporary URLs are saved.
Future<int> verifyOneDriveContent(http.Client client, Uri uri) async {
  for (var redirects = 0; redirects < 4; redirects++) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw const MicrosoftAuthFailure(
        'O endereço do arquivo musical não é válido. Tente novamente.',
        code: 'content_url_invalid',
        stage: 'content',
      );
    }
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers['Range'] = 'bytes=0-4095';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 20));
    if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
      await response.stream.listen((_) {}).cancel();
      final location = response.headers['location'];
      if (location == null) break;
      uri = uri.resolve(location);
      continue;
    }
    if (response.statusCode != 206) {
      await response.stream.listen((_) {}).cancel();
      if (response.statusCode == 200) {
        throw const MicrosoftAuthFailure(
          'O servidor não aceitou a leitura parcial. O teste foi interrompido para evitar baixar o arquivo inteiro; a reprodução ainda pode funcionar.',
          code: 'range_unsupported',
          stage: 'content',
        );
      }
      throw GraphException(response.statusCode, operation: 'content');
    }
    final range = RegExp(r'^bytes 0-(\d+)/(\d+|\*)$')
        .firstMatch(response.headers['content-range'] ?? '');
    final expected = range == null ? 0 : int.parse(range.group(1)!) + 1;
    final type = (response.headers['content-type'] ?? '').toLowerCase();
    if (expected < 1 ||
        expected > 4096 ||
        (response.contentLength ?? 0) > 4096 ||
        type.startsWith('text/') ||
        type.contains('json')) {
      await response.stream.listen((_) {}).cancel();
      throw const MicrosoftAuthFailure(
        'A leitura parcial retornou uma resposta inválida. Tente novamente.',
        code: 'content_range_invalid',
        stage: 'content',
      );
    }
    var bytes = 0;
    final chunks = StreamIterator(
      response.stream.timeout(const Duration(seconds: 20)),
    );
    try {
      while (await chunks.moveNext()) {
        bytes += chunks.current.length;
        if (bytes > 4096) break;
      }
    } finally {
      await chunks.cancel();
    }
    if (bytes != expected) {
      throw const MicrosoftAuthFailure(
        'O arquivo musical não retornou a amostra esperada. Tente novamente.',
        code: 'content_sample_invalid',
        stage: 'content',
      );
    }
    return bytes;
  }
  throw const MicrosoftAuthFailure(
    'O endereço do arquivo musical não pôde ser acessado. Tente novamente.',
    code: 'content_redirect_failed',
    stage: 'content',
  );
}
