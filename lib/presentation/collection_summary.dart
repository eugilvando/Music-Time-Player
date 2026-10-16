import 'ui_language.dart';

import 'package:flutter/material.dart';

import '../persistence/library_store.dart';
import 'information_cards.dart';

class CollectionSummary extends StatefulWidget {
  const CollectionSummary({super.key, required this.store});
  final LibraryStore store;
  @override
  State<CollectionSummary> createState() => _CollectionSummaryState();
}

class _CollectionSummaryState extends State<CollectionSummary> {
  late Future<Map<String, String>> data = load();
  Future<Map<String, String>> load() async {
    final db = widget.store.database;
    final base = (await db.rawQuery(
      'SELECT COUNT(*) AS tracks, COUNT(DISTINCT album_identity) AS albums, COALESCE(SUM(duration_ms),0) AS duration FROM catalog_search',
    )).single;
    final artists = (await db.rawQuery(
      'SELECT COUNT(DISTINCT lower(j.value)) AS count FROM catalog_search c,json_each(c.artists) j',
    )).single['count'];
    final genres = (await db.rawQuery(
      'SELECT COUNT(DISTINCT lower(j.value)) AS count FROM catalog_search c,json_each(c.genres) j',
    )).single['count'];
    final lists = (await db.rawQuery('SELECT COUNT(*) AS count FROM playlists'))
        .single['count'];
    final favorites = (await widget.store.favoriteIds()).length;
    final duration = Duration(milliseconds: (base['duration'] as num).toInt());
    return {
      'Catalogued tracks': '${base['tracks']}',
      'Albums': '${base['albums']}',
      'Artists': '$artists',
      'Genres': '$genres',
      'Playlists': '$lists',
      'Favorite tracks': '$favorites',
      'Total duration': '${duration.inHours} h ${duration.inMinutes % 60} min',
    };
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, String>>(
    future: data,
    builder: (context, snapshot) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snapshot.hasData) InformationCards(values: snapshot.data!),
        if (snapshot.connectionState != ConnectionState.done)
          const LinearProgressIndicator(),
        if (snapshot.hasError)
          const UiText('Could not calculate collection summary.'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => data = load()),
            icon: const Icon(Icons.refresh),
            label: const UiText('Refresh summary'),
          ),
        ),
      ],
    ),
  );
}
