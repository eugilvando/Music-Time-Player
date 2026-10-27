import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_card.dart';
import 'ui_language.dart';

const musicTimeVersion = '2.5.3+55';
const musicTimeRepository = 'https://github.com/eugilvando/Music-Time-Player';

class MusicTimeAbout extends StatelessWidget {
  const MusicTimeAbout({super.key});

  Future<void> open(BuildContext context, String path) async {
    try {
      if (await launchUrl(
        Uri.parse('$musicTimeRepository$path'),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      /* Keep the page usable when no external browser is available. */
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: UiText('Não foi possível abrir o navegador.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Music Time',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const SelectableText(
              musicTimeVersion,
              key: ValueKey('about.version'),
            ),
            const SizedBox(height: 16),
            const UiText(
              'Player pessoal para arquivos locais, nuvens e servidores de mídia.',
            ),
            const SizedBox(height: 12),
            const UiText('Design e desenvolvimento: Gilvando Souza'),
            const SizedBox(height: 8),
            const UiText(
              'Projeto pessoal desenvolvido com design engineering e assistência de IA.',
            ),
          ],
        ),
      ),
      SettingsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GitHub',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const SelectableText(musicTimeRepository),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => open(context, ''),
                  child: const UiText('Código no GitHub'),
                ),
                OutlinedButton(
                  onPressed: () => open(context, '/releases'),
                  child: const UiText('Versões e notas'),
                ),
                OutlinedButton(
                  onPressed: () => open(context, '/issues'),
                  child: const UiText('Relatar um problema'),
                ),
              ],
            ),
          ],
        ),
      ),
      SettingsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const UiText(
              'Licença MIT · componentes de terceiros possuem suas próprias licenças.',
            ),
            const SizedBox(height: 12),
            const UiText(
              'Construído com Flutter, Dart, MediaKit/libmpv e SQLite.',
            ),
            const SizedBox(height: 12),
            const UiText(
              'Dados e biblioteca ficam no seu dispositivo. Conexões opcionais consultam os serviços configurados; backups não são enviados ao GitHub.',
            ),
            const SizedBox(height: 12),
            const UiText(
              'OneDrive e Google Drive exigem seu próprio ID de aplicativo e autorização. A disponibilidade depende das regras de cada provedor.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Music Time',
                    applicationVersion: musicTimeVersion,
                  ),
                  child: const UiText('Licenças de terceiros'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      open(context, '/blob/main/THIRD_PARTY_NOTICES.md'),
                  child: const UiText('Avisos legais'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      open(context, '/blob/main/docs/provider-setup.md'),
                  child: const UiText('Configurar provedores'),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}
