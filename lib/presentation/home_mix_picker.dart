import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../settings/app_settings.dart';
import 'ui_language.dart';

const homeMixTypes = <String, String>{
  'artists': 'Artist mix',
  'artist_radio': 'Artist radio',
  'lastfm_overall': 'Last.fm · Mais ouvidas',
  'lastfm_month': 'Last.fm · Último mês',
  'favorites': 'Mix de favoritos',
  'discover': 'Descobertas da biblioteca',
  'rediscover': 'Redescobertas',
  'offline': 'Mix offline',
  'personal': 'Mix pessoal',
  'genres': 'Mixes por gênero',
  'decades': 'Mixes por década',
};

String homeMixType(String name) {
  if (name.startsWith('Artist mix · ')) return 'artists';
  if (name.startsWith('Artist radio · ')) return 'artist_radio';
  if (name == 'Mixes por artista') return 'artists';
  for (final entry in homeMixTypes.entries) {
    if (name == entry.value) return entry.key;
  }
  if (name.startsWith('Mix · ')) return 'genres';
  if (name.startsWith('Década · ')) return 'decades';
  if (name.startsWith('Artista · ')) return 'artists';
  return '';
}

Map<String, List<Track>> orderedHomeMixes(
  Map<String, List<Track>> mixes,
  AppSettings settings,
) => {
  for (final type
      in settings
          .visualList('home_mix_types', homeMixTypes.keys.toList())
          .toSet())
    for (final entry in mixes.entries)
      if (homeMixType(entry.key) == type) entry.key: entry.value,
};

String homeMixLabel(BuildContext context, String name) =>
    name.startsWith('Artist mix ')
    ? ui(context, 'Artist mix')
    : name.startsWith('Artist radio ')
    ? ui(context, 'Artist radio')
    : ui(context, name);
String homeMixReference(String name) => name.startsWith('Artist mix ')
    ? name.substring(13)
    : name.startsWith('Artist radio ')
    ? name.substring(15)
    : '';

Future<void> customizeHomeMixes(
  BuildContext context,
  AppSettings settings,
) async {
  final selected = settings
      .visualList('home_mix_types', homeMixTypes.keys.toList())
      .where(homeMixTypes.containsKey)
      .toSet();
  final order = [
    ...selected,
    ...homeMixTypes.keys.where((id) => !selected.contains(id)),
  ];
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: const UiText('Modelos do Feito para você'),
        content: SizedBox(
          width: 440,
          height: (MediaQuery.sizeOf(context).height * .5).clamp(160.0, 440.0),
          child: Column(
            children: [
              const UiText(
                'Marque os modelos desejados e arraste para mudar a ordem.',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: order.length,
                  onReorderItem: (oldIndex, newIndex) => update(
                    () => order.insert(newIndex, order.removeAt(oldIndex)),
                  ),
                  itemBuilder: (context, index) {
                    final id = order[index];
                    return CheckboxListTile(
                      key: ValueKey('mix-type.$id'),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: UiText(homeMixTypes[id]!),
                      value: selected.contains(id),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const UiText('Salvar'),
          ),
        ],
      ),
    ),
  );
  if (accepted == true) {
    await settings.updateVisual(
      'home_mix_types',
      order.where(selected.contains).toList(),
    );
  }
}
