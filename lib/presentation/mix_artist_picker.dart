import 'package:flutter/material.dart';

import '../library/catalog.dart';
import 'ui_language.dart';

Future<String?> pickMixArtist(BuildContext context, List<String> artists) =>
    showDialog<String>(
      context: context,
      builder: (_) => _MixArtistPicker(artists),
    );

class _MixArtistPicker extends StatefulWidget {
  const _MixArtistPicker(this.artists);
  final List<String> artists;
  @override
  State<_MixArtistPicker> createState() => _MixArtistPickerState();
}

class _MixArtistPickerState extends State<_MixArtistPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final values = widget.artists
        .where((a) => searchKey(a).contains(searchKey(query)))
        .toList();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      title: const UiText('Choose an artist'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            const UiText(
              'Library artists, ordered by favorites and listening history when available.',
            ),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: ui(context, 'Search artists'),
              ),
              onChanged: (s) => setState(() => query = s),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: values.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(values[i]),
                  onTap: () => Navigator.pop(context, values[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const UiText('Close'),
        ),
      ],
    );
  }
}
