/// Personal OneDrive CIDs are hexadecimal. Opaque/organizational IDs retain case.
String? oneDriveIdentity(String? value) =>
    value != null && RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(value)
    ? value.toUpperCase()
    : value;

bool sameOneDrive(String? a, String? b) =>
    a != null && b != null && oneDriveIdentity(a) == oneDriveIdentity(b);
