import 'album_queue_drag.dart';
import '../domain/track.dart';
import 'media_card_size.dart';
import 'item_action_region.dart';

import 'package:flutter/material.dart';

/// Shared horizontal card for tracks and collections.
class CompactMediaCard extends StatelessWidget {
  const CompactMediaCard({
    super.key,
    required this.artwork,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.onTap,
    this.dragTracks,
  });
  final List<Track>? dragTracks;
  Widget withDrag(Widget child) =>
      AlbumQueueDrag(tracks: dragTracks, title: title, child: child);
  final Widget artwork, actions;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => withDrag(
    ItemActionRegion(
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: MediaCardSizeScope.horizontalArtwork(context),
                  child: artwork,
                ),
                SizedBox(
                  width: MediaCardSizeScope.horizontalArtwork(context) <= 48
                      ? 8
                      : 12,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize:
                              MediaCardSizeScope.horizontalArtwork(context) <=
                                  48
                              ? 12
                              : 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                actions,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
