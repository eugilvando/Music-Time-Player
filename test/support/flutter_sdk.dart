import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Resolve the SDK used by this checkout, without a maintainer-specific path.
String materialIconFontPath() {
  final config = File('.dart_tool/package_config.json');
  final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
  final flutter = packages.firstWhere((p) => p['name'] == 'flutter') as Map;
  final packageUri = config.absolute.uri.resolve(flutter['rootUri'] as String);
  final sdk = Directory.fromUri(packageUri).parent.parent.path;
  return path.join(
    sdk,
    'bin',
    'cache',
    'artifacts',
    'material_fonts',
    'MaterialIcons-Regular.otf',
  );
}
