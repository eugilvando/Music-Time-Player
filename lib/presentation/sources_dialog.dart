import 'settings_card.dart';
import 'ui_language.dart';
import 'additional_source_settings.dart';
import '../sources/additional_sources.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../sources/provider_connections.dart';
import '../sources/microsoft_auth.dart' show openSystemBrowser;
import '../library/lastfm_profile.dart';
import 'playlist_import_review.dart';

class ProviderSettingsPage extends StatefulWidget {
  const ProviderSettingsPage({
    super.key,
    required this.providers,
    required this.onImported,
    required this.onlyMicrosoft,
    this.localSources,
    this.onAddFolder,
    this.onAddFiles,
    this.sourceOnly = false,
  });
  final VoidCallback? onAddFolder, onAddFiles;
  final Widget? localSources;
  final ProviderConnections providers;
  final VoidCallback onImported;
  final bool onlyMicrosoft;
  final bool sourceOnly;
  @override
  State<ProviderSettingsPage> createState() => _ProviderSettingsPageState();
}

class _ProviderSettingsPageState extends State<ProviderSettingsPage> {
  bool addingMicrosoft = false;
  final clientId = TextEditingController();
  final apiKey = TextEditingController(), secret = TextEditingController();
  final lastfmUser = TextEditingController();
  String syncDate(Object? value) {
    final date = DateTime.tryParse(value is String ? value : '')?.toLocal();
    if (date == null) return ui(context, 'Data indisponível');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${ui(context, 'às')} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  void initState() {
    super.initState();
    lastfmUser.text =
        widget.providers.preferences.getString('lastfm.profile_user') ?? '';
    if (!widget.sourceOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.providers.run(widget.providers.refreshStatus);
      });
    }
  }

  @override
  void dispose() {
    apiKey.dispose();
    clientId.dispose();
    secret.dispose();
    lastfmUser.dispose();
    super.dispose();
  }

  Future<void> chooseFolder([
    Map<String, dynamic>? current,
    List<Map<String, dynamic>> ancestors = const [],
  ]) async {
    List<Map<String, dynamic>> folders = [];
    await widget.providers.run(() async {
      folders = await widget.providers.folders(
        itemId: current?['id'] as String?,
      );
    });
    if (!mounted || widget.providers.error != null) return;
    final location = current == null
        ? 'Raiz do OneDrive'
        : ProviderConnections.folderCatalogPath(current)
              .split(':')
              .skip(1)
              .join(':');
    for (final folder in folders) {
      folder['catalogPath'] =
          '${current == null ? "/drive/root:" : ProviderConnections.folderCatalogPath(current)}/${folder['name']}';
    }
    final result = await showDialog<Object>(
      context: context,
      builder: (context) => AlertDialog(
        title: const UiText('Selecionar pasta musical'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UiText(
                'Selecionada: ${uiSourceFolder(context, widget.providers.selectedFolderLabel)}',
              ),
              const SizedBox(height: 12),
              UiText('Navegando: ${uiSourceFolder(context, location)}'),
              const UiText(
                'Só arquivos de áudio desta pasta e de suas subpastas.',
              ),
              const Divider(),
              Expanded(
                child: folders.isEmpty
                    ? const Center(
                        child: UiText('Esta pasta não contém subpastas.'),
                      )
                    : ListView.builder(
                        itemCount: folders.length,
                        itemBuilder: (context, index) => ListTile(
                          selected: widget.providers.folderIsSelected(
                            folders[index],
                          ),
                          leading: Icon(
                            widget.providers.folderIsSelected(folders[index])
                                ? Icons.check_circle
                                : widget.providers.folderIsIncluded(
                                    folders[index],
                                  )
                                ? Icons.check_circle_outline
                                : Icons.folder,
                          ),
                          title: Text(folders[index]['name'] as String),
                          subtitle:
                              widget.providers.folderIsSelected(folders[index])
                              ? const UiText('Pasta selecionada')
                              : widget.providers.folderIsIncluded(
                                  folders[index],
                                )
                              ? const UiText('Subpasta incluída na seleção')
                              : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, folders[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'back'),
              child: const UiText('Voltar'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'selected'),
            child: Text(
              current == null
                  ? 'Selecionar todas as pastas'
                  : 'Selecionar esta pasta',
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result == 'selected') {
      await widget.providers.run(() => widget.providers.selectFolder(current));
    } else if (result == 'back') {
      await chooseFolder(
        ancestors.isEmpty ? null : ancestors.last,
        ancestors.isEmpty
            ? const []
            : ancestors.sublist(0, ancestors.length - 1),
      );
    } else if (result is Map<String, dynamic>) {
      await chooseFolder(result, [...ancestors, if (current != null) current]);
    }
  }

  Future<void> showOutbox() async {
    final rows = await widget.providers.store.scrobbleStatus();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const UiText('Envios Last.fm'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: rows.isEmpty
              ? const Center(child: UiText('Nenhum envio registrado.'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(
                      '${rows[index]['title']} • ${rows[index]['artist']}',
                    ),
                    subtitle: Text(
                      '${rows[index]['status']} • ${rows[index]['error'] ?? ''}',
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UiText('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> connect() async {
    final p = widget.providers;
    await p.connectMicrosoft(useCode: false);
    if (!mounted || p.error != null || !p.microsoftConnected) return;
    await p.checkMicrosoftDrive();
    if (mounted && p.error == null) await chooseFolder();
  }

  Future<void> renameSource() async {
    final controller = TextEditingController(
      text: widget.providers.microsoftSourceLabel,
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const UiText('Nome da fonte OneDrive'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UiText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const UiText('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) {
      await widget.providers.run(
        () => widget.providers.renameMicrosoftSource(value),
      );
    }
  }

  Widget microsoftContent() {
    final p = widget.providers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UiText(
          'Conecte seu OneDrive pessoal',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const UiText(
          'Entre na sua conta Microsoft pelo navegador e autorize o acesso às músicas. Depois, escolha a pasta musical. A conexão será concluída automaticamente no Music Time.',
        ),
        if (!p.microsoftConfigured)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: UiText(
              'O login Microsoft ainda precisa ser configurado nesta instalação do Music Time.',
            ),
          ),
        ExpansionTile(
          title: const UiText('Avançado'),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: clientId,
              decoration: InputDecoration(
                labelText: ui(context, 'Client ID público do Music Time'),
                helperText: ui(
                  context,
                  'Registro Microsoft de aplicativo desktop. Não use senha ou segredo.',
                ),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: p.busy || p.anyMicrosoftLoginPending
                  ? null
                  : () async {
                      if (!p.microsoftConfigured) {
                        await p.run(() => p.configure(clientId.text, '', ''));
                        if (p.error != null || !p.microsoftConfigured) return;
                      }
                      await connect();
                    },
              icon: const Icon(Icons.login),
              label: const UiText('Conectar pelo navegador'),
            ),
            TextButton(
              onPressed:
                  p.busy || (!p.microsoftConnected && p.sourceId == 'legacy')
                  ? null
                  : () async {
                      await p.removeMicrosoftSource();
                      widget.onImported();
                    },
              child: const UiText('Remover fonte'),
            ),
            TextButton.icon(
              onPressed: p.busy ? null : renameSource,
              icon: const Icon(Icons.edit),
              label: const UiText('Renomear fonte'),
            ),
          ],
        ),
        if (p.microsoftLoginPending)
          TextButton(
            onPressed: p.cancelMicrosoftLogin,
            child: const UiText('Cancelar conexão'),
          ),
        UiText(
          p.microsoftConnected
              ? 'OneDrive conectado'
              : p.microsoftLoginPending
              ? 'Aguardando autorização no navegador…'
              : 'OneDrive desconectado',
        ),
        const Divider(height: 32),
        UiText('Pasta musical', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const UiText('Mostrar esta fonte na biblioteca'),
          subtitle: const UiText(
            'Ocultar não remove músicas, playlists ou downloads.',
          ),
          value: p.microsoftVisible,
          onChanged: p.busy
              ? null
              : (value) => p.run(() async {
                  await p.setMicrosoftVisible(value);
                  widget.onImported();
                }),
        ),
        Text(uiSourceFolder(context, p.selectedFolderLabel)),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: p.busy || !p.microsoftConnected ? null : chooseFolder,
              icon: const Icon(Icons.folder),
              label: const UiText('Escolher pasta'),
            ),
            FilledButton.icon(
              onPressed:
                  p.busy || !p.microsoftConnected || !p.microsoftFolderSelected
                  ? null
                  : () async {
                      await p.importMicrosoft();
                      if (p.error == null) widget.onImported();
                    },
              icon: const Icon(Icons.sync),
              label: const UiText('Sincronizar músicas'),
            ),
          ],
        ),
        if (p.microsoftConnected)
          TextButton.icon(
            onPressed: p.busy ? null : p.checkMicrosoftConnection,
            icon: const Icon(Icons.cloud_done),
            label: const UiText('Verificar conexão, pasta e leitura'),
          ),
        if (p.microsoftChecks.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final check in p.microsoftChecks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(check),
            ),
          if (p.microsoftCheckedAt != null)
            Text(syncDate(p.microsoftCheckedAt!.toIso8601String())),
          const SizedBox(height: 12),
        ],
        const UiText(
          'Desconectar remove apenas a sessão desta conta. Catálogo e downloads locais são preservados.',
        ),
        const UiText(
          'Inclui todas as subpastas. Lê tags e capas MP3/FLAC em trechos limitados da nuvem, sem baixar músicas inteiras.',
        ),
        if (p.syncingMicrosoft) ...[
          const LinearProgressIndicator(),
          Text(
            uiFormat(
              context,
              '${p.cancelSync ? "Cancelando" : "Sincronizando"}: ${p.syncPages} páginas, ${p.syncExamined} itens examinados, ${p.imported} músicas processadas.',
              '${p.cancelSync ? "Cancelling" : "Synchronizing"}: ${p.syncPages} pages, ${p.syncExamined} items checked, ${p.imported} tracks processed.',
            ),
          ),
          Text(
            uiFormat(
              context,
              'Tags embutidas: ${p.syncTagsRead}; sem leitura embutida: ${p.syncTagsSkipped}.',
              'Embedded tags: ${p.syncTagsRead}; metadata fallback: ${p.syncTagsSkipped}.',
            ),
          ),
          if (p.syncCurrentFile.isNotEmpty)
            Text(
              uiFormat(
                context,
                'Lendo metadados: ${p.syncCurrentFile}',
                'Reading metadata: ${p.syncCurrentFile}',
              ),
            ),
          TextButton(
            onPressed: p.cancelSync ? null : p.cancelMicrosoftSync,
            child: const UiText('Cancelar sincronização'),
          ),
        ],
        if (p.syncStatus == 'failed')
          const UiText(
            'Sincronização interrompida por erro. Tente novamente; o último resumo concluído permanece abaixo.',
          ),
        if (p.syncStatus == 'cancelled')
          const UiText(
            'Sincronização cancelada. Algumas páginas podem ter sido catalogadas; execute novamente para concluir.',
          ),
        if (p.syncSummary case final summary?) ...[
          const SizedBox(height: 12),
          Text(
            uiFormat(
              context,
              'Última sincronização concluída — ${summary['folder']}',
              'Last completed synchronization — ${summary['folder']}',
            ),
          ),
          Text(
            uiFormat(
              context,
              '${summary['total']} músicas disponíveis no catálogo; ${summary['processed']} processadas nessa sincronização.',
              '${summary['total']} tracks available in the catalog; ${summary['processed']} processed in this synchronization.',
            ),
          ),
          Text(syncDate(summary['completedAt'])),
          if (summary['covers'] is int)
            Text(
              uiFormat(
                context,
                '${summary['covers']} músicas com capa; ${(summary['total'] as int) - (summary['covers'] as int)} sem capa disponibilizada.',
                '${summary['covers']} tracks with artwork; ${(summary['total'] as int) - (summary['covers'] as int)} without available artwork.',
              ),
            ),
          if (summary['tagsRead'] is int)
            Text(
              uiFormat(
                context,
                '${summary['tagsRead']} faixas com tags embutidas lidas ou reutilizadas; ${summary['tagsSkipped']} usando informações do serviço ou do catálogo.',
                '${summary['tagsRead']} tracks with embedded tags read or reused; ${summary['tagsSkipped']} using service or catalog metadata.',
              ),
            ),
          if (summary['unknownArtists'] is int)
            Text(
              uiFormat(
                context,
                '${summary['unknownArtists']} sem artista identificado; ${summary['unknownAlbums']} sem álbum informado.',
                '${summary['unknownArtists']} without an identified artist; ${summary['unknownAlbums']} without an album.',
              ),
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> importLastfmProfile(bool loved) async {
    final p = widget.providers;
    await p.run(() async {
      await p.configure('', apiKey.text, secret.text);
      final api = await p.lastfm();
      final remote = await api.profileTracks(lastfmUser.text, loved: loved);
      final tracks = await p.store.loadTracks(
        includeCovers: false,
        includeHidden: true,
      );
      final report = await compute(matchLastFmProfile, (remote, tracks));
      if (!mounted) return;
      if (report.entries.isEmpty) {
        throw StateError('Nenhuma faixa retornada pelo Last.fm');
      }
      if (report.unresolved > 0) {
        final accepted = await showDialog<List<String>>(
          context: context,
          builder: (_) => PlaylistImportReview(report: report, tracks: tracks),
        );
        if (accepted == null || !mounted) return;
      }
      if (report.ids.isEmpty) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const UiText('Importar dados do Last.fm?'),
          content: Text(
            loved
                ? uiFormat(
                    context,
                    '${report.ids.toSet().length} faixas serão adicionadas aos favoritos locais. Seus favoritos existentes serão preservados.',
                    '${report.ids.toSet().length} tracks will be added to your local favorites. Existing favorites are preserved.',
                  )
                : uiFormat(
                    context,
                    '${report.ids.length} reproduções serão salvas na playlist Last.fm — Últimas tocadas, da mais recente para a mais antiga. Não altera histórico, contagem local nem envia scrobbles.',
                    '${report.ids.length} recent plays will be saved as a playlist, newest first. Local history and play counts are preserved; no scrobbles are sent.',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const UiText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const UiText('Importar'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      if (loved) {
        await p.store.setFavorites(report.ids, true);
      } else {
        await p.store.importPlaylist('Last.fm — Últimas tocadas', report.ids);
      }
      await p.preferences.setString(
        'lastfm.profile_user',
        lastfmUser.text.trim(),
      );
      widget.onImported();
    });
  }

  Widget lastfmContent() {
    final p = widget.providers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UiText('Last.fm', style: Theme.of(context).textTheme.titleLarge),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: UiText(
            'Conexão',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: p.busy
                  ? null
                  : () async {
                      await p.run(
                        () => p.configure('', apiKey.text, secret.text),
                      );
                      if (p.error == null) await p.beginLastfm();
                    },
              child: const UiText('Autorizar Last.fm'),
            ),
            TextButton(
              onPressed: p.busy || p.pendingLastfmToken == null
                  ? null
                  : p.finishLastfm,
              child: const UiText('Concluir após autorizar no navegador'),
            ),
            TextButton(
              onPressed: p.busy || !p.lastfmConnected
                  ? null
                  : p.disconnectLastfm,
              child: const UiText('Desconectar'),
            ),
          ],
        ),
        UiText(
          p.lastfmConnected
              ? 'Sessão Last.fm salva no cofre'
              : 'Last.fm desconectado',
        ),
        const Divider(height: 32),
        UiText(
          'Dados do perfil',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const UiText(
          'Importe favoritos e até 200 reproduções recentes usando a chave da API e seu nome de usuário. Não exige conexão para scrobbling; perfis privados podem restringir a consulta.',
        ),
        TextField(
          controller: lastfmUser,
          decoration: InputDecoration(
            labelText: ui(context, 'Usuário Last.fm'),
          ),
        ),
        const Divider(height: 32),
        UiText(
          'Sincronização e índices',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const UiText('Atualizar índices após iniciar'),
          subtitle: const UiText(
            'Favoritos, recentes e rankings ficam disponíveis para consulta. A importação para favoritos e playlists continua separada.',
          ),
          value: p.profileIndex.automatic,
          onChanged: (value) async {
            await p.preferences.setBool('lastfm.index_auto', value);
            await p.preferences.setString(
              'lastfm.profile_user',
              lastfmUser.text.trim(),
            );
            p.profileIndex.schedule();
          },
        ),
        Text(
          uiFormat(
            context,
            'Atraso após iniciar: ${p.profileIndex.delaySeconds} s',
            'Delay after startup: ${p.profileIndex.delaySeconds} s',
          ),
        ),
        Slider(
          value: p.profileIndex.delaySeconds.toDouble(),
          min: 10,
          max: 300,
          divisions: 29,
          onChanged: (value) async {
            await p.preferences.setInt(
              'lastfm.index_delay_seconds',
              value.round(),
            );
            p.profileIndex.schedule();
          },
        ),
        UiText(p.profileIndex.status),
        if (p.profileIndex.updatedAt != null)
          Text(
            uiFormat(
              context,
              'Atualizado em ${p.profileIndex.updatedAt!.toLocal()}',
              'Updated ${p.profileIndex.updatedAt!.toLocal()}',
            ),
          ),
        if (p.profileIndex.counts.isNotEmpty)
          Text(
            uiFormat(
              context,
              '${p.profileIndex.counts['loved'] ?? 0} favoritos • ${p.profileIndex.counts['recent'] ?? 0} recentes • ${p.profileIndex.counts['overall'] ?? 0} mais ouvidas • ${p.profileIndex.counts['1month'] ?? 0} no último mês',
              '${p.profileIndex.counts['loved'] ?? 0} loved tracks • ${p.profileIndex.counts['recent'] ?? 0} recent plays • ${p.profileIndex.counts['overall'] ?? 0} top tracks • ${p.profileIndex.counts['1month'] ?? 0} last month',
            ),
          ),
        TextButton.icon(
          icon: const Icon(Icons.sync),
          label: UiText(
            p.profileIndex.running
                ? 'Atualizando índices'
                : 'Atualizar índices agora',
          ),
          onPressed: p.profileIndex.running || p.busy
              ? null
              : () async {
                  await p.run(() async {
                    await p.configure('', apiKey.text, secret.text);
                    await p.preferences.setString(
                      'lastfm.profile_user',
                      lastfmUser.text.trim(),
                    );
                  });
                  if (p.error == null) await p.profileIndex.refresh();
                },
        ),
        const Divider(height: 32),
        UiText(
          'Importação',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: p.busy ? null : () => importLastfmProfile(true),
              child: const UiText('Importar favoritos'),
            ),
            OutlinedButton(
              onPressed: p.busy ? null : () => importLastfmProfile(false),
              child: const UiText('Importar últimas tocadas'),
            ),
          ],
        ),
        const Divider(height: 32),
        UiText(
          'Scrobbling',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const UiText('Enviar música atual'),
          value: p.preferences.getBool('lastfm.now_playing') ?? false,
          onChanged: p.busy
              ? null
              : (value) => p.run(() async {
                  await p.preferences.setBool('lastfm.now_playing', value);
                }),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const UiText('Ativar scrobbling'),
          subtitle: const UiText(
            'Registra as reproduções elegíveis e processa a fila offline.',
          ),
          value: p.preferences.getBool('lastfm.scrobbling') ?? false,
          onChanged: p.busy
              ? null
              : (value) => p.run(() async {
                  await p.preferences.setBool('lastfm.scrobbling', value);
                }),
        ),
        const Divider(height: 32),
        UiText(
          'Pendências',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: showOutbox,
              child: const UiText('Consultar fila de envios'),
            ),
            TextButton(
              onPressed: p.busy ? null : p.flushScrobbles,
              child: const UiText('Processar pendentes'),
            ),
          ],
        ),
        const Divider(height: 32),
        ExpansionTile(
          title: const UiText('Avançado'),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const UiText('Obter chave da API Last.fm'),
                  onPressed: p.busy
                      ? null
                      : () => p.run(() async {
                          if (!await openSystemBrowser(
                            Uri.parse('https://www.last.fm/api/account/create'),
                          )) {
                            throw StateError('Navegador indisponível');
                          }
                        }),
                ),
                TextButton(
                  onPressed: p.busy
                      ? null
                      : () => p.run(() async {
                          if (!await openSystemBrowser(
                            Uri.parse('https://www.last.fm/api/account'),
                          )) {
                            throw StateError('Navegador indisponível');
                          }
                        }),
                  child: const UiText('Consultar minhas chaves'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: apiKey,
              decoration: InputDecoration(
                labelText: ui(context, 'API key Last.fm'),
                helperText: ui(
                  context,
                  'Deixe vazio para manter a chave salva',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: secret,
              obscureText: true,
              decoration: InputDecoration(
                labelText: ui(context, 'API secret Last.fm'),
                helperText: ui(context, 'Salvo no cofre do sistema'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.providers,
    builder: (context, _) => widget.sourceOnly
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.providers.error != null)
                UiText(
                  widget.providers.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              microsoftContent(),
            ],
          )
        : ListView(
            padding: const EdgeInsets.all(32),
            children: [
              SizedBox(
                height: widget.providers.busy ? 4 : 0,
                child: widget.providers.busy
                    ? const LinearProgressIndicator()
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: UiText(
                  widget.providers.error ?? '',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.onlyMicrosoft)
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: UiText(
                    'Active sources',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              if (widget.onlyMicrosoft && widget.localSources != null)
                SettingsCard(child: widget.localSources!),
              if (widget.onlyMicrosoft) ...[
                AdditionalSourceSettings(
                  sources: widget.providers.additional,
                  onChanged: widget.onImported,
                ),
                for (final source in widget.providers.microsoftSources)
                  if (source.microsoftConnected ||
                      source.microsoftFolderSelected ||
                      source.sourceId != 'legacy')
                    SettingsCard(
                      padding: 0,
                      child: ExpansionTile(
                        key: ValueKey(source.sourceId),
                        leading: const Icon(Icons.cloud),
                        title: Text(source.microsoftSourceLabel),
                        subtitle: Text(
                          '${ui(context, source.microsoftConnected ? "Conectado" : "Reconectar conta")} · ${uiSourceFolder(context, source.selectedFolderLabel)}',
                        ),
                        initiallyExpanded:
                            widget.providers.microsoftSources.length == 1,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: ProviderSettingsPage(
                              providers: source,
                              onImported: widget.onImported,
                              onlyMicrosoft: true,
                              sourceOnly: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 24),
                SettingsCard(
                  child: Align(
                    key: const ValueKey('sources.add'),
                    alignment: Alignment.centerLeft,
                    child: PopupMenuButton<String>(
                      tooltip: ui(context, 'Adicionar fonte'),
                      enabled: !widget.providers.anyMicrosoftBusy,
                      onSelected: (value) async {
                        if (value == 'local') {
                          widget.onAddFolder?.call();
                        } else if (value == 'files') {
                          widget.onAddFiles?.call();
                        } else if (additionalSourceTypes.containsKey(value)) {
                          await addAdditionalSource(
                            context,
                            widget.providers.additional,
                            value,
                            widget.onImported,
                          );
                        } else {
                          if (!widget.providers.microsoftConnected &&
                              widget.providers.microsoftSources.length == 1) {
                            setState(() => addingMicrosoft = true);
                          } else {
                            await widget.providers.run(() async {
                              await widget.providers.createMicrosoftSource();
                            });
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        for (final type in additionalSourceTypes.entries)
                          PopupMenuItem(
                            value: type.key,
                            child: Text(type.value),
                          ),
                        if (widget.onAddFolder != null)
                          const PopupMenuItem(
                            value: 'local',
                            child: UiText('Pasta deste computador'),
                          ),
                        if (widget.onAddFiles != null)
                          const PopupMenuItem(
                            value: 'files',
                            child: UiText('Arquivos deste computador'),
                          ),
                        const PopupMenuItem(
                          value: 'onedrive',
                          child: UiText('OneDrive pessoal'),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add),
                            SizedBox(width: 8),
                            UiText('Adicionar fonte'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!widget.providers.microsoftConnected && addingMicrosoft)
                  SettingsCard(child: microsoftContent()),
              ] else
                ...settingsSections((lastfmContent() as Column).children),
            ],
          ),
  );
}
