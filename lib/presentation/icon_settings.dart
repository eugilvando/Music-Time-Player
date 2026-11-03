import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'design_icon.dart';
import 'ui_language.dart';

class IconSettings extends StatelessWidget {
  const IconSettings({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('icons.pack.${settings.iconPack}'),
          initialValue: settings.iconPack,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: ui(context, 'Pacote de ícones'),
          ),
          items: [
            DropdownMenuItem(
              value: 'current',
              child: UiText('Atual · Material Symbols'),
            ),
            DropdownMenuItem(value: 'solar', child: Text('Solar')),
            DropdownMenuItem(value: 'phosphor', child: Text('Phosphor')),
          ],
          onChanged: settings.saving
              ? null
              : (value) {
                  if (value != null) settings.updateVisual('icon_pack', value);
                },
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<String>(
          key: ValueKey('icons.style.${settings.iconStyle}'),
          initialValue: settings.iconStyle,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: ui(context, 'Estilo dos ícones'),
          ),
          items: const [
            DropdownMenuItem(value: 'filled', child: UiText('Preenchido')),
            DropdownMenuItem(value: 'outlined', child: UiText('Contorno')),
          ],
          onChanged: settings.saving
              ? null
              : (value) {
                  if (value != null) settings.updateVisual('icon_style', value);
                },
        ),
        const SizedBox(height: 24),
        const UiText('Prévia dos ícones'),
        const SizedBox(height: 16),
        MtIconTheme(
          pack: settings.iconPack,
          style: settings.iconStyle,
          child: Wrap(
            spacing: 20,
            runSpacing: 16,
            children: [
              for (final entry in <IconData, String>{
                Icons.home: 'Início',
                Icons.library_music: 'Biblioteca',
                Icons.favorite: 'Favoritos',
                Icons.play_arrow: 'Reproduzir',
                Icons.shuffle: 'Aleatório',
                Icons.settings: 'Configurações',
              }.entries)
                Tooltip(
                  message: ui(context, entry.value),
                  child: MtIcon(
                    entry.key,
                    size: 26,
                    semanticLabel: ui(context, entry.value),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UiText(
          'A escolha se aplica imediatamente e fica salva neste dispositivo.',
        ),
      ],
    ),
  );
}
