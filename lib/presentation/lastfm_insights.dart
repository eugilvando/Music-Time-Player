import 'package:flutter/material.dart';

import '../sources/provider_connections.dart';
import '../domain/track.dart';
import '../library/catalog.dart';
import 'artist_portrait.dart';
import 'ui_language.dart';

class LastFmInsights extends StatefulWidget {
  const LastFmInsights({
    super.key,
    required this.providers,
    required this.artist,
    required this.catalog,
    this.album,
    this.onArtist,
  });
  final ProviderConnections providers;
  final String artist;
  final String? album;
  final List<Track> catalog;
  final void Function(String)? onArtist;
  @override
  State<LastFmInsights> createState() => _LastFmInsightsState();
}

class _LastFmInsightsState extends State<LastFmInsights> {
  Future<Map<String, dynamic>>? data;
  @override
  void initState() {
    super.initState();
    if (widget.album == null) data = load();
  }

  Future<Map<String, dynamic>> load() async {
    if (widget.providers.preferences.getBool('visual.offline_only') ?? false) {
      throw StateError('Offline');
    }
    final api = await widget.providers.lastfm();
    if (widget.album == null) {
      return api.readProfile('artist.getSimilar', {
        'artist': widget.artist,
        'limit': '100',
        'autocorrect': '0',
      });
    }
    final album = await api.readProfile('album.getInfo', {
      'artist': widget.artist,
      'album': widget.album!,
      'autocorrect': '0',
    });
    final top = await api.readProfile('artist.getTopTracks', {
      'artist': widget.artist,
      'limit': '200',
      'autocorrect': '0',
    });
    return {...album, ...top};
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    initiallyExpanded: widget.album == null,
    title: UiText(
      widget.album == null
          ? 'Artistas similares · Last.fm'
          : 'Popularidade do álbum · Last.fm',
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    onExpansionChanged: (open) {
      if (open && data == null) setState(() => data = load());
    },
    children: [
      if (data != null)
        FutureBuilder<Map<String, dynamic>>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListTile(
                title: const UiText(
                  'Dados Last.fm indisponíveis. Confira a chave e a conexão.',
                ),
                trailing: IconButton(
                  tooltip: ui(context, 'Tentar novamente'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(() => data = load()),
                ),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final body = snapshot.data!;
            if (widget.album == null) {
              final raw = body['similarartists']?['artist'];
              final rows = raw is List ? raw : [];
              final names = widget.catalog
                  .expand((t) => [...t.artistNames, ...t.albumArtistNames])
                  .map(searchKey)
                  .toSet();
              final known = rows
                  .where(
                    (row) =>
                        row is Map &&
                        row['name'] is String &&
                        names.contains(searchKey(row['name'] as String)),
                  )
                  .take(12)
                  .toList();
              if (known.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: UiText('No similar artists found in your library.'),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    for (final row in known)
                      SizedBox(
                        width: 168,
                        child: InkWell(
                          onTap: () =>
                              widget.onArtist?.call(row['name'] as String),
                          child: Column(
                            children: [
                              SizedBox.square(
                                dimension: 168,
                                child: ArtistPortrait(
                                  artist: row['name'] as String,
                                  enabled:
                                      widget.providers.preferences.getBool(
                                        'visual.artist_photos',
                                      ) ??
                                      true,
                                  cachedOnly:
                                      widget.providers.preferences.getBool(
                                        'visual.offline_only',
                                      ) ??
                                      false,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                row['name'] as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }
            final album = body['album'] is Map ? body['album'] as Map : {};
            final plays = int.tryParse('${album['playcount']}'),
                listeners = int.tryParse('${album['listeners']}');
            final raw = body['toptracks']?['track'];
            final rows = raw is List ? raw : [];
            final titles = widget.catalog
                .map((t) => searchKey(t.title))
                .toSet();
            final known = rows
                .where(
                  (r) => r is Map && titles.contains(searchKey('${r['name']}')),
                )
                .take(5)
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (plays != null)
                  Text('${ui(context, 'Community album plays')}: $plays'),
                if (listeners != null)
                  Text('${ui(context, 'Community listeners')}: $listeners'),
                const SizedBox(height: 16),
                const UiText(
                  'Faixas presentes neste álbum entre as mais ouvidas do artista',
                ),
                const UiText(
                  'Contagens globais por faixa; não representam suas reproduções locais ou uma edição específica.',
                ),
                for (final row in known)
                  ListTile(
                    title: Text('${row['name']}'),
                    subtitle: UiText(
                      int.tryParse('${row['playcount']}') == null
                          ? 'Contagem não informada'
                          : '${row['playcount']} ${ui(context, 'Global plays')}',
                    ),
                  ),
                if (known.isEmpty)
                  const UiText(
                    'Nenhuma faixa correspondente no ranking retornado.',
                  ),
              ],
            );
          },
        ),
    ],
  );
}
