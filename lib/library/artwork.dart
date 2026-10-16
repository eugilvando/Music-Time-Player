import 'dart:typed_data';

bool isSupportedArtwork(List<int> bytes) =>
    bytes.length >= 8 &&
    (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff ||
        bytes[0] == 137 &&
            bytes[1] == 80 &&
            bytes[2] == 78 &&
            bytes[3] == 71 &&
            bytes[4] == 13 &&
            bytes[5] == 10 &&
            bytes[6] == 26 &&
            bytes[7] == 10);
const maxArtworkBytes = 4 * 1024 * 1024;
Uint8List? validatedArtwork(Uint8List bytes) =>
    bytes.length <= maxArtworkBytes && isSupportedArtwork(bytes) ? bytes : null;
