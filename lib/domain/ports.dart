import 'track.dart';

abstract interface class AccessTokenProvider {
  Future<String> accessToken();
}

abstract interface class MediaSourceResolver {
  Future<Uri> resolve(Track track);
}

abstract interface class AuthenticatedMediaResolver {
  Future<Map<String, String>> mediaHeaders(Track track, Uri uri);
  bool allowsInsecureMedia(Uri uri);
}

Future<Map<String, String>> mediaHeaders(
  MediaSourceResolver resolver,
  Track track,
  Uri uri,
) => uri.scheme == 'file' || resolver is! AuthenticatedMediaResolver
    ? Future.value(const {})
    : (resolver as AuthenticatedMediaResolver).mediaHeaders(track, uri);

bool allowedMediaUri(MediaSourceResolver resolver, Uri uri) =>
    uri.scheme == 'https' ||
    (uri.scheme == 'http' &&
        resolver is AuthenticatedMediaResolver &&
        (resolver as AuthenticatedMediaResolver).allowsInsecureMedia(uri));

class MediaSourceFailure implements Exception {
  const MediaSourceFailure(this.message);
  final String message;
}

abstract interface class ScrobbleSink {
  Future<void> nowPlaying(Track track);
  Future<void> submit(Track track, DateTime startedAt, Duration duration);
}

abstract interface class RefreshableAccessTokenProvider
    implements AccessTokenProvider {
  Future<void> invalidateAccessToken();
}
