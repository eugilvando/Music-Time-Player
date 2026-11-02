import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../library/smart_play.dart';
import 'ui_language.dart';

class PlaybackSettingField<T> extends StatelessWidget {
  const PlaybackSettingField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      UiText(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      DropdownButtonFormField<T>(
        key: ValueKey('$label:$value'),
        initialValue: value,
        isExpanded: true,
        isDense: false,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: items,
        onChanged: onChanged,
      ),
    ],
  );
}

class CrossfadeSettings extends StatelessWidget {
  const CrossfadeSettings({super.key, required this.settings});
  final AppSettings settings;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final mode = settings.crossfadeSetting;
      final effect = settings.visualChoice('crossfade_mode', 'fixed');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UiText('Suavize a passagem de uma música para a próxima.'),
          const SizedBox(height: 20),
          PlaybackSettingField<String>(
            label: 'Transição entre faixas',
            value: mode,
            items: const [
              DropdownMenuItem(value: 'off', child: UiText('Desativado')),
              DropdownMenuItem(value: 'auto', child: UiText('Automático')),
              DropdownMenuItem(value: 'manual', child: UiText('Manual')),
            ],
            onChanged: settings.saving
                ? null
                : (value) {
                    if (value != null) {
                      settings.updateVisual('crossfade_setting', value);
                    }
                  },
          ),
          if (mode == 'manual') ...[
            const SizedBox(height: 24),
            PlaybackSettingField<int>(
              label: 'Duração da transição',
              value: settings.crossfadeDuration,
              items: [
                for (var n = 1; n <= 12; n++)
                  DropdownMenuItem(value: n, child: Text('$n s')),
              ],
              onChanged: settings.saving
                  ? null
                  : (value) {
                      if (value != null) {
                        settings.updateVisual(
                          'crossfade_seconds',
                          value.toDouble(),
                        );
                      }
                    },
            ),
            const SizedBox(height: 24),
            PlaybackSettingField<String>(
              label: 'Estilo da transição',
              value: effect,
              items: const [
                DropdownMenuItem(value: 'fixed', child: UiText('Suave')),
                DropdownMenuItem(value: 'smart', child: Text('Smart fades')),
                DropdownMenuItem(value: 'mix', child: Text('Mix only')),
              ],
              onChanged: settings.saving
                  ? null
                  : (value) {
                      if (value != null) {
                        settings.updateVisual('crossfade_mode', value);
                      }
                    },
            ),
          ],
          const SizedBox(height: 16),
          UiText(
            mode == 'off'
                ? 'Cada música termina antes de a próxima começar.'
                : mode == 'auto'
                ? 'O app escolhe uma transição de até 6 segundos conforme a duração das faixas e ajusta o ponto quando a análise está disponível.'
                : effect == 'mix'
                ? 'Sobrepõe as músicas sem alterar o volume. Exige análise compatível e equalizador desativado.'
                : effect == 'smart'
                ? 'Ajusta o ponto da transição quando possível. Nos demais casos, usa a duração escolhida.'
                : 'Reduz o volume da música atual enquanto a próxima entra.',
          ),
          if (mode != 'off') ...[
            const SizedBox(height: 12),
            const UiText(
              'Álbuns em ordem sequencial mantêm a passagem original entre faixas.',
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const UiText('Como funciona'),
              children: const [
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: UiText(
                    'A análise de início e final está disponível para arquivos WAV locais compatíveis. O automático usa a duração das músicas quando não pode analisá-las. Mix only é ignorado quando a sobreposição não pode ser validada.',
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );
}

class ContinuousPlaybackSettings extends StatelessWidget {
  const ContinuousPlaybackSettings({super.key, required this.settings});
  final AppSettings settings;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final enabled = settings.visualBool('smart_play', fallback: false);
      final count = settings
          .visualNumber('continuous_count', 5)
          .round()
          .clamp(1, 100);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const UiText('Continuar após o fim da fila'),
            subtitle: const UiText(
              'Acrescenta músicas da sua biblioteca conforme o modo escolhido.',
            ),
            value: enabled,
            onChanged: settings.saving
                ? null
                : (value) => settings.updateVisual('smart_play', value),
          ),
          const SizedBox(height: 20),
          PlaybackSettingField<String>(
            label: 'Modo do play contínuo',
            value: settings.visualChoice('continuous_mode', 'related'),
            items: [
              for (final mode in continuousModes.entries)
                DropdownMenuItem(
                  value: mode.key,
                  child: Text(ui(context, mode.value)),
                ),
            ],
            onChanged: !enabled || settings.saving
                ? null
                : (value) {
                    if (value != null) {
                      settings.updateVisual('continuous_mode', value);
                    }
                  },
          ),
          const SizedBox(height: 24),
          PlaybackSettingField<int>(
            label: 'Faixas a adicionar',
            value: count,
            items: [
              for (final n in ({1, 5, 10, 20, 50, 100, count}.toList()..sort()))
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: !enabled || settings.saving
                ? null
                : (value) {
                    if (value != null) {
                      settings.updateVisual(
                        'continuous_count',
                        value.toDouble(),
                      );
                    }
                  },
          ),
          const SizedBox(height: 16),
          const UiText(
            'Você também pode trocar o modo pelo botão Play contínuo na barra de reprodução.',
          ),
        ],
      );
    },
  );
}
