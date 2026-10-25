import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Decode only the physical pixels required by this view. Buckets let nearby
/// card sizes share a decoded image instead of caching every individual size.
class BoundedArtwork extends StatelessWidget {
  const BoundedArtwork(
    this.bytes, {
    super.key,
    this.errorBuilder,
    this.gaplessPlayback = false,
  });
  final Uint8List bytes;
  final ImageErrorWidgetBuilder? errorBuilder;
  final bool gaplessPlayback;

  static int decodeEdge(BoxConstraints constraints, double pixelRatio) {
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : 256.0;
    final height = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : width;
    final desired = (width > height ? width : height) * pixelRatio;
    return const [
      64,
      128,
      256,
      512,
      1024,
      2048,
    ].firstWhere((edge) => edge >= desired, orElse: () => 2048);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final edge = decodeEdge(
        constraints,
        MediaQuery.devicePixelRatioOf(context),
      );
      return Image(
        image: ResizeImage(
          MemoryImage(bytes),
          width: edge,
          height: edge,
          policy: ResizeImagePolicy.fit,
        ),
        fit: BoxFit.cover,
        width: constraints.hasBoundedWidth ? double.infinity : null,
        height: constraints.hasBoundedHeight ? double.infinity : null,
        gaplessPlayback: gaplessPlayback,
        errorBuilder: errorBuilder,
      );
    },
  );
}
