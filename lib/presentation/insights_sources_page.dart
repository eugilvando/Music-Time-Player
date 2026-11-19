import 'package:flutter/material.dart';

import '../sources/provider_connections.dart';
import '../domain/track.dart';
import '../infrastructure/brainz.dart';
import '../infrastructure/lastfm.dart';
import '../library/alternative_insights.dart';
import '../library/listening_insights.dart';
import '../library/catalog.dart';
import '../persistence/library_store.dart';
import '../settings/app_settings.dart';
import 'listening_insights_page.dart';

Map<String, String> availableInsightSources({
  required bool lastfm,
  required bool listenbrainz,
}) => {
  if (lastfm) 'lastfm': 'Last.fm',
  if (listenbrainz) 'listenbrainz': 'ListenBrainz',
  'local': 'Local',
};

class InsightsSourcesPage extends StatefulWidget {
  const InsightsSourcesPage({
    super.key,
    required this.providers,
    required this.repository,
    required this.settings,
    required this.store,
    required this.catalog,
    required this.catalogRevision,
    required this.availableOffline,
    required this.onPlay,
    required this.onSaved,
    required this.onConfigure,
    required this.onOpen,
  });
  final ProviderConnections providers;
  final ListeningInsightsRepository repository;
  final AppSettings settings;
  final LibraryStore store;
  final List<Track> catalog;
  final int catalogRevision;
  final Future<Set<String>> Function() availableOffline;
  final Future<void> Function(List<Track>, int, String) onPlay;
  final VoidCallback onSaved, onConfigure;
  final void Function(String, CatalogGroup) onOpen;
  @override
  State<InsightsSourcesPage> createState() => _InsightsSourcesPageState();
}

class _InsightsSourcesPageState extends State<InsightsSourcesPage> {
  String? selected;
  @override
  void initState() {
    super.initState();
    selected = widget.settings.preferences.getString('visual.insights_source');
  }

  Future<LastFmClient> localApi() async => LastFmClient(
    widget.providers.client,
    apiKey: '',
    apiSecret: '',
    allowReads: () => false,
  );
  late final local = AlternativeInsights(
    widget.store,
    localApi,
    source: 'local',
  );
  late final brainz = AlternativeInsights(
    widget.store,
    localApi,
    source: 'listenbrainz',
    transport: BrainzTransport(
      widget.providers.client,
      'api.listenbrainz.org',
      allowed: () =>
          widget.providers.integrationReadsAllowed &&
          widget.providers.listenBrainz.user.isNotEmpty,
    ),
    allowed: () =>
        widget.providers.integrationReadsAllowed &&
        widget.providers.listenBrainz.user.isNotEmpty,
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.providers,
    builder: (context, _) {
      final p = widget.providers;
      final lastUser = (p.preferences.getString('lastfm.profile_user') ?? '')
          .trim();
      final available = availableInsightSources(
        lastfm:
            p.lastfmConnected &&
            (p.preferences.getBool('lastfm.recommendations') ?? true),
        listenbrainz: p.listenBrainz.user.isNotEmpty,
      );
      final source = available.containsKey(selected)
          ? selected!
          : available.keys.first;
      final user = source == 'local'
          ? 'Music Time'
          : source == 'lastfm'
          ? lastUser
          : p.listenBrainz.user;
      final repository = source == 'local'
          ? local
          : source == 'lastfm'
          ? widget.repository
          : brainz;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                if (available.length > 1)
                  DropdownButton<String>(
                    key: const ValueKey('insights.source'),
                    value: source,
                    items: [
                      for (final item in available.entries)
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(item.value),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => selected = value);
                      if (value != null) {
                        widget.settings.preferences.setString(
                          'visual.insights_source',
                          value,
                        );
                      }
                    },
                  )
                else
                  Text(
                    'Insights locais',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onConfigure,
                  child: const Text('Integrações'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListeningInsightsPage(
              key: ValueKey('$source:$user'),
              repository: repository,
              profileUser: user,
              sourceLabel: available[source]!,
              settings: widget.settings,
              store: widget.store,
              catalog: widget.catalog,
              catalogRevision: widget.catalogRevision,
              availableOffline: widget.availableOffline,
              onPlay: widget.onPlay,
              onSaved: widget.onSaved,
              onConfigure: widget.onConfigure,
              onOpen: widget.onOpen,
            ),
          ),
        ],
      );
    },
  );
}
