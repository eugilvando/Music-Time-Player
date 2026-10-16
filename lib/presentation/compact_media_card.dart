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
  });
  final Widget artwork, actions;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ItemActionRegion(
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 52 * MediaCardSizeScope.scale(context),
                child: artwork,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
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
  );
}
