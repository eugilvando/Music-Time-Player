import 'package:flutter/material.dart';

import '../sources/provider_connections.dart';
import 'ui_language.dart';

class SourceVisibilitySettings extends StatefulWidget {
  const SourceVisibilitySettings({
    super.key,
    required this.providers,
    required this.onChanged,
  });
  final ProviderConnections providers;
  final VoidCallback onChanged;
  @override
  State<SourceVisibilitySettings> createState() =>
      _SourceVisibilitySettingsState();
}

class _SourceVisibilitySettingsState extends State<SourceVisibilitySettings> {
  List<Map<String, Object?>> local = [];
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final values = await widget.providers.store.localSources();
    if (mounted) setState(() => local = values);
  }

  Future<void> update(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      await load();
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: UiText('Não foi possível atualizar a fonte.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const UiText(
        'Ocultar afeta a visualização; não remove fontes, arquivos, playlists ou downloads.',
      ),
      for (final row in local)
        SwitchListTile(
          title: Text(row['label'] as String),
          value: row['visible'] != 0,
          onChanged: busy
              ? null
              : (value) => update(() async {
                  await widget.providers.store.database.update(
                    'local_sources',
                    {'visible': value ? 1 : 0},
                    where: 'id=?',
                    whereArgs: [row['id']],
                  );
                }),
        ),
      for (final source in widget.providers.microsoftSources)
        if (source.microsoftFolderSelected)
          SwitchListTile(
            title: Text(source.microsoftSourceLabel),
            subtitle: Text(uiSourceFolder(context, source.selectedFolderLabel)),
            value: source.microsoftVisible,
            onChanged: busy
                ? null
                : (value) => update(() => source.setMicrosoftVisible(value)),
          ),
      for (final source in widget.providers.additional.connections)
        SwitchListTile(
          title: Text(source.label),
          subtitle: Text(source.type),
          value: source.visible,
          onChanged: busy
              ? null
              : (v) => update(
                  () => widget.providers.additional.setVisible(source, v),
                ),
        ),
    ],
  );
}
