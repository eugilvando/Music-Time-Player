import '../library/local_metadata.dart' show albumKey, legacyAlbumKey;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../library/catalog.dart';
import 'ui_language.dart';

class MediaIndicatorScope extends InheritedWidget {
  const MediaIndicatorScope({
    super.key,
    required super.child,
    required this.favorites,
    required this.collections,
    this.currentId,
    this.currentTrack,
    this.playing = false,
  });
  final Set<String> favorites, collections;
  final String? currentId;
  final Track? currentTrack;
  final bool playing;
  static MediaIndicatorScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaIndicatorScope>();
  bool albumFavorite(Track t) => [
    'album:${albumKey(t)}',
    'album:${legacyAlbumKey(t)}',
    if (t.albumId.isNotEmpty) 'album:id:${t.albumId}',
  ].any(collections.contains);
  bool artistFavorite(String name) =>
      collections.contains('artist:$name') ||
      collections.contains('artist:${artistNameKey(name)}');
  @override
  bool updateShouldNotify(MediaIndicatorScope old) =>
      old.currentId != currentId ||
      old.playing != playing ||
      !setEquals(old.favorites, favorites) ||
      !setEquals(old.collections, collections);
}

class MediaBadges extends StatelessWidget {
  const MediaBadges({
    super.key,
    required this.child,
    this.favorite = false,
    this.playing = false,
  });
  final Widget child;
  final bool favorite, playing;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      if (favorite || playing)
        Positioned.fill(
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (context, size) {
                final small = size.maxWidth < 60 || size.maxHeight < 60;
                Widget badge(IconData icon, String label) => Tooltip(
                  message: ui(context, label),
                  child: Semantics(
                    label: ui(context, label),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .76),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(small ? 2 : 5),
                        child: Icon(
                          icon,
                          size: small ? 12 : 18,
                          color: icon == Icons.favorite
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
                return Stack(
                  children: [
                    if (favorite)
                      Positioned(
                        top: 2,
                        left: 2,
                        child: badge(Icons.favorite, 'Favorito'),
                      ),
                    if (playing)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: badge(Icons.graphic_eq, 'Em reprodução'),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
    ],
  );
}
