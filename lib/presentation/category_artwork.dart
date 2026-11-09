import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Offline category art; deterministic colors keep categories recognizable.
class CategoryArtwork extends StatelessWidget {
  const CategoryArtwork({super.key, required this.label, required this.kind});
  final String label, kind;

  @override
  Widget build(BuildContext context) {
    final hash = '$kind:$label'.runes.fold<int>(
      0,
      (n, c) => (n * 31 + c) & 0x7fffffff,
    );
    final hue = ((hash * 137) % 360).toDouble();
    final color = HSLColor.fromAHSL(1, hue, .55, .28).toColor();
    final end = HSLColor.fromAHSL(1, (hue + 35) % 360, .50, .16).toColor();
    return Semantics(
      label: label,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
          builder: (context, size) {
            final edge = math
                .min(
                  size.maxWidth.isFinite ? size.maxWidth : 120,
                  size.maxHeight.isFinite ? size.maxHeight : 120,
                )
                .toDouble();
            final longest = label
                .split(RegExp(r'\s+'))
                .fold<int>(1, (n, word) => math.max(n, word.runes.length));
            final fontSize = math
                .min(
                  edge * (kind == 'genres' ? .19 : .27),
                  edge * .8 / (longest * .68),
                )
                .clamp(6.0, 64.0);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, end],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    right: -edge * .3,
                    bottom: -edge * .3,
                    child: Container(
                      width: edge,
                      height: edge,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .10),
                          width: edge * .12,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(edge * .10),
                    child: Center(
                      child: ExcludeSemantics(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: fontSize,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
