import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../application/update_check.dart';

import 'package:url_launcher/url_launcher.dart';

import 'settings_card.dart';
import 'ui_language.dart';

const musicTimeRepository = 'https://github.com/eugilvando/Music-Time-Player';

class MusicTimeAbout extends StatefulWidget {
  const MusicTimeAbout({super.key});
  @override
  State<MusicTimeAbout> createState() => _MusicTimeAboutState();
}

class _MusicTimeAboutState extends State<MusicTimeAbout> {
  PackageInfo? info;
  bool checking = false;
  String? result;
  AppRelease? update;
  String get installedVersion => info == null
      ? 'Versão indisponível'
      : '${info!.version}${info!.buildNumber.isEmpty ? '' : '+${info!.buildNumber}'}';

  @override
  void initState() {
    super.initState();
    loadVersion();
  }

  Future<void> loadVersion() async {
    try {
      final value = await PackageInfo.fromPlatform();
      if (mounted) setState(() => info = value);
    } catch (_) {
      // Do not display a guessed or hardcoded version.
    }
  }

  Future<void> check() async {
    if (checking) return;
    setState(() {
      checking = true;
      result = null;
      update = null;
    });
    try {
      final installed = info ?? await PackageInfo.fromPlatform();
      final release = await checkForUpdate(Platform.operatingSystem);
      if (!mounted) return;
      setState(() {
        info = installed;
        if (release == null) {
          result = 'Nenhuma versão compatível encontrada.';
        } else if (compareVersions(release.version, installed.version) > 0) {
          update = release;
          result = 'Nova versão disponível: ${release.version}';
        } else {
          result =
              'Você já usa a versão mais recente disponível para este sistema.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => result = 'Não foi possível verificar. Confira sua conexão e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

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
            SelectableText(installedVersion, key: ValueKey('about.version')),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: checking ? null : check,
                  child: UiText(
                    checking ? 'Verificando…' : 'Verificar atualização',
                  ),
                ),
                if (update != null)
                  FilledButton(
                    onPressed: () => open(
                      context,
                      update!.page.toString().substring(
                        musicTimeRepository.length,
                      ),
                    ),
                    child: const UiText('Abrir download e notas'),
                  ),
              ],
            ),
            if (result != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(result!, semanticsLabel: result),
              ),
            const SizedBox(height: 8),
            const UiText(
              'Consulta as releases públicas no GitHub. O download e a instalação são manuais.',
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
            const SelectableText(
              'Solar Icons © 480 Design · CC BY 4.0\nhttps://solar-icons.dev/ · https://creativecommons.org/licenses/by/4.0/\nPhosphor Icons © Phosphor Icons · MIT\nhttps://phosphoricons.com/',
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
                    applicationVersion: installedVersion,
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
