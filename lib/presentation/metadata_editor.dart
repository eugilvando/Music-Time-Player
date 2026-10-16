import 'ui_language.dart';

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../domain/track.dart';
import '../persistence/library_store.dart';
import '../library/local_metadata.dart';

Future<bool> editCatalogMetadata(
  BuildContext context,
  LibraryStore store,
  Track track,
) async {
  final text = {
    'title': TextEditingController(text: track.title),
    'artist': TextEditingController(text: track.artistNames.join('; ')),
    'album': TextEditingController(text: track.album),
    'albumArtist': TextEditingController(
      text: track.albumArtistNames.join('; '),
    ),
    'genre': TextEditingController(text: track.genreNames.join('; ')),
    'year': TextEditingController(text: track.year?.toString() ?? ''),
    'trackNumber': TextEditingController(
      text: track.trackNumber?.toString() ?? '',
    ),
    'discNumber': TextEditingController(
      text: track.discNumber?.toString() ?? '',
    ),
    'edition': TextEditingController(text: track.edition),
  };
  final form = GlobalKey<FormState>();
  final originalLists = {
    'artist': track.artistNames,
    'albumArtist': track.albumArtistNames,
    'genre': track.genreNames,
  };
  final originalText = {for (final e in text.entries) e.key: e.value.text};
  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const UiText('Editar informações no Music Time'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: form,
          child: Column(
            children: [
              const UiText(
                'Salvo apenas no catálogo. Artistas aceitam ; , : & feat. e ft. como separadores. Gêneros usam ;. A barra / é preservada.',
              ),
              for (final entry in {
                'title': 'Título',
                'artist': 'Artistas',
                'album': 'Álbum',
                'albumArtist': 'Artistas de álbum',
                'genre': 'Gêneros',
                'year': 'Ano',
                'trackNumber': 'Número da faixa',
                'discNumber': 'Disco',
                'edition': 'Edição',
              }.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextFormField(
                    controller: text[entry.key],
                    decoration: InputDecoration(
                      labelText: ui(context, entry.value),
                    ),
                    validator: (value) {
                      if (entry.key == 'title' &&
                          (value ?? '').trim().isEmpty) {
                        return ui(context, 'Informe um título');
                      }
                      if ({
                            'year',
                            'trackNumber',
                            'discNumber',
                          }.contains(entry.key) &&
                          (value ?? '').isNotEmpty) {
                        final number = int.tryParse(value!);
                        if (number == null || number < 1 || number > 9999) {
                          return ui(context, 'Use um número de 1 a 9999');
                        }
                      }
                      return null;
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'reset'),
          child: const UiText('Restaurar tags originais'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const UiText('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(context, 'save');
          },
          child: const UiText('Salvar no catálogo'),
        ),
      ],
    ),
  );
  try {
    if (action == null) return false;
    if (action == 'reset') {
      await store.setUserMetadata([track.id], {}, clear: true);
      return true;
    }
    List<String> names(String key) => text[key]!.text == originalText[key]
        ? originalLists[key]!
        : text[key]!.text
              .split(';')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
    final artists = names('artist'),
        albumArtists = names('albumArtist'),
        genres = names('genre');
    await store.setUserMetadata(
      [track.id],
      {
        'title': text['title']!.text.trim(),
        'artist': artists.join('; '),
        'artists': artists,
        'album': text['album']!.text.trim(),
        if (text['album']!.text != originalText['album'] ||
            text['albumArtist']!.text != originalText['albumArtist'] ||
            text['edition']!.text != originalText['edition'])
          'albumId': '',
        'albumArtist': albumArtists.join('; '),
        'albumArtists': albumArtists,
        'genre': genres.join('; '),
        'genres': genres,
        'edition': text['edition']!.text.trim(),
        for (final key in ['year', 'trackNumber', 'discNumber'])
          key: int.tryParse(text[key]!.text),
      },
    );
    return true;
  } finally {
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final c in text.values) {
        c.dispose();
      }
    });
  }
}

Future<bool> mergeCatalogCollection(
  BuildContext context,
  LibraryStore store,
  List<Track> source, {
  required bool album,
  bool albumArtistRole = false,
  String? originName,
}) async {
  if (source.isEmpty) return false;
  final all = await store.loadTracks(includeCovers: false, includeHidden: true);
  if (!context.mounted) return false;
  final input = TextEditingController();
  final choices = <String, Track>{};
  for (final track in all) {
    if (album && track.album.isNotEmpty) {
      choices.putIfAbsent(albumKey(track), () => track);
    } else if (!album) {
      for (final artist
          in albumArtistRole ? track.albumArtistNames : track.artistNames) {
        choices.putIfAbsent(artist, () => track);
      }
    }
  }
  final target = await showDialog<MapEntry<String, Track>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(
          album ? 'Mesclar com outro álbum' : 'Mesclar com outro artista',
        ),
        content: SizedBox(
          width: 560,
          height: 420,
          child: Column(
            children: [
              const UiText(
                'Escolha o destino. Apenas os metadados do catálogo serão unificados; arquivos e referências serão preservados.',
              ),
              TextField(
                controller: input,
                onChanged: (_) => update(() {}),
                decoration: InputDecoration(
                  labelText: ui(context, 'Pesquisar destino'),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final entry
                        in choices.entries
                            .where(
                              (e) =>
                                  (album
                                          ? '${e.value.album} ${e.value.albumArtist}'
                                          : e.key)
                                      .toLowerCase()
                                      .contains(input.text.toLowerCase()),
                            )
                            .take(80))
                      ListTile(
                        title: Text(album ? entry.value.album : entry.key),
                        subtitle: album
                            ? Text(
                                '${entry.value.albumArtistNames.join('; ')} • ${entry.value.year ?? ui(context, 'Ano não informado')} • ${entry.value.edition}',
                              )
                            : null,
                        onTap: () => Navigator.pop(context, entry),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UiText('Cancelar'),
          ),
        ],
      ),
    ),
  );
  Future<void>.delayed(const Duration(seconds: 1), input.dispose);
  if (target == null || !context.mounted) return false;
  final ids = source.map((t) => t.id).toSet();
  if (album) {
    ids.addAll(all.where((t) => albumKey(t) == target.key).map((t) => t.id));
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const UiText('Confirmar mesclagem no catálogo?'),
      content: Text(
        uiFormat(
          context,
          '${ids.length} arquivos manterão seus IDs e serão apresentados com ${album ? target.value.album : target.key}. As tags originais podem ser restauradas pelo editor.',
          '${ids.length} tracks will keep their IDs and appear under ${album ? target.value.album : target.key}. Original tags can be restored in the editor.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const UiText('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const UiText('Mesclar'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  if (album) {
    final t = target.value;
    await store.setUserMetadata(ids.toList(), {
      'album': t.album,
      'albumArtist': t.albumArtist,
      'albumArtists': t.albumArtistNames,
      'year': t.year,
      'edition': t.edition,
      'albumId': t.albumId.isNotEmpty
          ? t.albumId
          : 'app-merge:${sha256.convert(utf8.encode(target.key))}',
    });
  } else {
    final changes = <String, Map<String, Object?>>{};
    for (final t in source) {
      String normalized(String v) =>
          v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      List<String> replace(List<String> names) => names
          .map(
            (name) =>
                originName == null || normalized(name) == normalized(originName)
                ? target.key
                : name,
          )
          .toSet()
          .toList();
      final artists = replace(
        albumArtistRole ? t.albumArtistNames : t.artistNames,
      );
      changes[t.id] = albumArtistRole
          ? {'albumArtist': artists.join('; '), 'albumArtists': artists}
          : {'artist': artists.join('; '), 'artists': artists};
    }
    await store.setUserMetadataBatch(changes);
  }
  return true;
}
