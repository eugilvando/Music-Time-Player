import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;
void registerIconLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Solar Icons — 480 Design'],
      'Solar Icons © 480 Design. CC BY 4.0.\n'
      'Source: https://solar-icons.dev/\n'
      'Bundled SVG subset from Iconify; container and color adapted for Music Time.\n\n'
      '${await rootBundle.loadString('assets/icons/licenses/Solar-CC-BY-4.0.txt')}',
    );
    yield LicenseEntryWithLineBreaks(const [
      'Phosphor Icons',
    ], await rootBundle.loadString('assets/icons/licenses/Phosphor-MIT.txt'));
  });
}
