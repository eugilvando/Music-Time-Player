import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Original Figma vector, scaled as a unit without changing its SVG geometry.
class ArtworkPlaceholder extends StatelessWidget {
  const ArtworkPlaceholder({super.key, this.artist = false});
  final bool artist;
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.cover,
    child: SizedBox.square(
      dimension: 48,
      child: SvgPicture.asset(
        'assets/design/${artist ? 'artist' : 'album'}-placeholder.svg',
      ),
    ),
  );
}
