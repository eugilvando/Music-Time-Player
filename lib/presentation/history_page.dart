import 'item_action_region.dart';
import 'ui_language.dart';

import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../persistence/library_store.dart';
import 'now_playing_artwork.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.store,
    required this.onPlay,
    required this.trackActions,
  });
  final LibraryStore store;
  final Future<void> Function(List<Track>, int) onPlay;
  final Widget Function(Track) trackActions;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<Map<String, Object?>>> rows = widget.store.history();
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: rows,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(() => rows = widget.store.history()),
            child: const UiText('Tentar carregar o histórico novamente'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      if (data.isEmpty) {
        return const Center(
          child: UiText('Ouça músicas para preencher o histórico.'),
        );
      }
      return ListView.builder(
        itemCount: data.length,
        itemBuilder: (context, i) {
          final track = widget.store.trackFromRow(data[i]);
          return ItemActionRegion(
            child: ListTile(
              leading: SizedBox.square(
                dimension: 48,
                child: TrackCover(track: track),
              ),
              title: Text(track.title),
              subtitle: Text('${track.artist} · ${data[i]['started_at']}'),
              trailing: widget.trackActions(track),
              onTap: () => widget.onPlay([track], 0),
            ),
          );
        },
      );
    },
  );
}
