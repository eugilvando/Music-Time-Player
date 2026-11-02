import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../library/local_metadata.dart';

/// Album payloads preserve disc/track order without changing the catalog list.
class AlbumQueueDrag extends StatelessWidget {
  const AlbumQueueDrag({
    super.key,
    required this.tracks,
    required this.title,
    required this.child,
  });
  final List<Track>? tracks;
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (tracks == null || tracks!.isEmpty) return child;
    final ordered = List<Track>.of(tracks!)..sort(compareAlbumTracks);
    return Draggable<List<Track>>(
      data: ordered,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('$title · ${ordered.length} ♪'),
        ),
      ),
      child: child,
    );
  }
}
