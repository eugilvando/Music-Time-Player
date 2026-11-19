import 'package:flutter/material.dart';

import '../sources/provider_connections.dart';
import '../sources/microsoft_auth.dart' show openSystemBrowser;
import 'settings_card.dart';
import 'ui_language.dart';

class BrainzSettings extends StatefulWidget {
  const BrainzSettings({
    super.key,
    required this.providers,
    this.policyOnly = false,
  });
  final ProviderConnections providers;
  final bool policyOnly;
  @override
  State<BrainzSettings> createState() => _BrainzSettingsState();
}

class _BrainzSettingsState extends State<BrainzSettings> {
  final token = TextEditingController();
  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  Widget toggle(
    String key,
    String title,
    String subtitle, {
    bool fallback = false,
  }) {
    final p = widget.providers;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: UiText(title),
      subtitle: UiText(subtitle),
      value: p.preferences.getBool(key) ?? fallback,
      onChanged: p.busy
          ? null
          : (value) => p.run(() async {
              await p.preferences.setBool(key, value);
              if (key == 'listenbrainz.scrobbling' && value) {
                await p.listenBrainz.flush();
              }
            }),
    );
  }

  Widget card(String title, List<Widget> children) => SettingsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiText(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.providers,
    builder: (context, _) {
      final p = widget.providers, lb = p.listenBrainz;
      if (widget.policyOnly) {
        return card('Dados e recomendações', [
          const UiText(
            'As integrações são opcionais. A biblioteca, favoritos, histórico e seleção local de faixas continuam funcionando sem contas externas.',
          ),
          const SizedBox(height: 16),
          toggle(
            'integrations.local_only',
            'Usar apenas dados locais',
            'Impede novas consultas de metadados, rankings e similaridades. Dados já salvos continuam disponíveis. Os envios de reproduções e favoritos são controlados separadamente abaixo.',
          ),
          toggle(
            'lastfm.recommendations',
            'Consultar dados do Last.fm',
            'Permite consultas de similaridades, rankings e perfil. Não altera a chave existente nem as opções de envio.',
            fallback: true,
          ),
          const UiText(
            'A seleção local usa gêneros e afinidade nas playlists; época e favoritos ajudam a ordenar. Sem informação suficiente, os modos de reprodução usam suas alternativas locais. Não há análise do áudio.',
          ),
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card('ListenBrainz', [
            const UiText(
              'Registre suas reproduções em uma conta independente do Last.fm. Conectar não ativa os envios. O histórico anterior não é exportado automaticamente.',
            ),
            const SizedBox(height: 16),
            UiText(lb.status),
            const SizedBox(height: 16),
            TextField(
              controller: token,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Token ListenBrainz',
                helperText: 'Salvo somente no cofre seguro do sistema',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: p.busy
                      ? null
                      : () => p.run(() async {
                          await lb.connect(token.text);
                          token.clear();
                        }),
                  child: const UiText('Validar e conectar'),
                ),
                TextButton(
                  onPressed: p.busy || lb.user.isEmpty
                      ? null
                      : () => p.run(lb.disconnect),
                  child: const UiText('Desconectar'),
                ),
                TextButton(
                  onPressed: () => openSystemBrowser(
                    Uri.parse('https://listenbrainz.org/settings/'),
                  ),
                  child: const UiText('Obter meu token'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            toggle(
              'listenbrainz.now_playing',
              'Enviar música atual',
              'Mostra a faixa que está tocando no ListenBrainz.',
            ),
            toggle(
              'listenbrainz.scrobbling',
              'Enviar reproduções ao ListenBrainz',
              'Registra faixas após metade da duração ou quatro minutos ouvidos. Pendências ficam vinculadas à conta que as criou; pausar o envio preserva a fila.',
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: p.busy ? null : () => p.run(lb.flush),
                  child: const UiText('Processar pendentes'),
                ),
                TextButton(
                  onPressed: () async {
                    final rows = await lb.outbox();
                    if (!context.mounted) return;
                    final counts = <String, int>{};
                    for (final row in rows) {
                      final s = row['status'] as String;
                      counts[s] = (counts[s] ?? 0) + 1;
                    }
                    const labels = {
                      'pending': 'Aguardando envio',
                      'sent': 'Enviados',
                      'auth_required': 'Reconexão necessária',
                      'ambiguous': 'Resposta incerta (sem reenvio automático)',
                      'rejected': 'Recusados',
                      'sending': 'Enviando',
                    };
                    await showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const UiText('Envios ListenBrainz'),
                        content: Text(
                          rows.isEmpty
                              ? 'Nenhum envio nesta conta.'
                              : 'Últimos 100 registros:\n${counts.entries.map((e) => '${labels[e.key] ?? e.key}: ${e.value}').join('\n')}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const UiText('Fechar'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const UiText('Consultar fila'),
                ),
              ],
            ),
          ]),
          card('MusicBrainz', [
            const UiText(
              'Complemento de metadados, sem scrobbling e sem necessidade de conectar uma conta. Não substitui o ListenBrainz.',
            ),
            toggle(
              'musicbrainz.enabled',
              'Complementar gêneros de artistas',
              'Quando a biblioteca não encontra similares, consulta a identificação e os gêneros do artista para procurar opções locais. Não modifica seus arquivos. Consultas são limitadas e os resultados ficam em cache.',
            ),
            const UiText(
              'Artistas com nomes ambíguos não são associados automaticamente. A opção “Usar apenas dados locais” bloqueia novas consultas.',
            ),
          ]),
        ],
      );
    },
  );
}
