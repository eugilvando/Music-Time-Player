import 'microsoft_auth.dart';

const microsoftSourcesPreference = 'microsoft.sources';
bool validMicrosoftSourceId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{16,80}$').hasMatch(value);
String microsoftSourceSessionKey(String id) =>
    id == 'legacy' ? 'microsoft.session' : 'microsoft.source.$id.session';

/// Browser login stays in memory until the drive and target source are verified.
class PendingMicrosoftVault implements SecretVault {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  void clear() => _values.clear();
}
