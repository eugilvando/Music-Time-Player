import 'package:path/path.dart' as p;

import '../domain/track.dart';

/// Persistent playlist locations. HTTP playback URLs are never permanent IDs.
abstract final class PlaylistReference {
  static String track(Track t) => t.provider == 'local' && t.localPath != null
      ? Uri.file(
          t.localPath!,
          windows: p.windows.isAbsolute(t.localPath!),
        ).toString()
      : 'musictime://track/${Uri.encodeComponent(t.id)}';
  static bool isTransient(String value) {
    if (p.windows.isAbsolute(value)) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        ({'http', 'https'}.contains(uri.scheme) ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment);
  }

  static String safe(String value) => isTransient(value)
      ? 'musictime://unresolved/unsupported-remote-reference'
      : value.replaceAll(RegExp(r'[\r\n]'), ' ');

  static p.Context context(String value) => p.Context(
    style: p.windows.isAbsolute(value) ? p.Style.windows : p.Style.posix,
  );

  static String? local(String reference, String playlistPath) {
    if (p.windows.isAbsolute(reference)) return p.windows.normalize(reference);
    final uri = Uri.tryParse(reference);
    if (uri?.scheme == 'file') {
      try {
        return uri!.toFilePath(
          windows:
              uri.host.isNotEmpty || RegExp(r'^/[A-Za-z]:').hasMatch(uri.path),
        );
      } catch (_) {
        return null;
      }
    }
    if (uri?.hasScheme == true) return null;
    final ctx = context(playlistPath);
    return ctx.normalize(
      ctx.join(
        ctx.dirname(playlistPath),
        reference.replaceAll(r'\', ctx.separator),
      ),
    );
  }

  static String rebase(
    String reference,
    String originalPath,
    String targetPath, {
    bool driveRoot = false,
  }) {
    if (isTransient(reference)) {
      throw const FormatException('Temporary URLs cannot be exported.');
    }
    if (driveRoot ||
        p.windows.isAbsolute(reference) ||
        p.posix.isAbsolute(reference) ||
        Uri.tryParse(reference)?.hasScheme == true) {
      return reference;
    }
    final absolute = local(reference, originalPath);
    if (absolute == null) return reference;
    final ctx = context(originalPath);
    if (context(targetPath).style != ctx.style) return absolute;
    return ctx.relative(absolute, from: ctx.dirname(targetPath));
  }
}
