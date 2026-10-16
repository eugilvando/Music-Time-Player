import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

bool attributesHaveLocalData(int attributes) =>
    attributes != 0xffffffff &&
    (attributes & (0x1000 | 0x40000 | 0x400000)) == 0;

/// Metadata only: never hydrate OneDrive placeholders just to draw an offline badge.
bool fileHasLocalData(File file) {
  if (!Platform.isWindows) return file.existsSync();
  var value = file.absolute.path.replaceAll('/', r'\');
  if (!value.startsWith(r'\\?\')) {
    value = value.startsWith(r'\\')
        ? r'\\?\UNC\' + value.substring(2)
        : r'\\?\' + value;
  }
  final name = value.toPcwstr(allocator: calloc);
  try {
    return attributesHaveLocalData(GetFileAttributes(name).value);
  } finally {
    calloc.free(name);
  }
}
