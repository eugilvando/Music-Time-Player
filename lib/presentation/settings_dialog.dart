import 'artist_selection_settings.dart';
import 'storage_settings.dart';
import 'artwork_storage_settings.dart';
import 'source_visibility_settings.dart';
import 'ui_language.dart';

import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../sources/provider_connections.dart';
import '../domain/track.dart';
import '../offline/download_manager.dart';
import 'sources_dialog.dart';
import 'now_playing_artwork.dart';
import 'now_playing_page.dart';
import 'downloads_dialog.dart';
import '../application/player_controller.dart';
import 'equalizer_panel.dart';
import 'data_settings.dart';
import 'player_bar_organizer.dart';
import 'collection_summary.dart';

enum SettingsCategory {
  general('Geral', Icons.settings_outlined),
  appearance('Aparência e acessibilidade', Icons.palette_outlined),
  customization('Interface e player', Icons.dashboard_customize_outlined),
  playback('Reprodução e áudio', Icons.graphic_eq),
  library('Biblioteca e metadados', Icons.library_music_outlined),
  onedrive('Fontes de música', Icons.cloud_outlined),
  downloads('Offline e armazenamento', Icons.storage_outlined),
  lastfm('Integrações', Icons.extension_outlined),
  data('Backup e manutenção', Icons.backup_outlined);

  const SettingsCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.onAddFiles,
    required this.trackCount,
    this.onAddFolder,
    this.providers,
    this.onImported,
    this.previewTrack,
    this.downloads,
    this.localSources,
    this.onCustomizeHome,
    this.controller,
    this.onBackup,
    this.onRestore,
    this.onReset,
    this.canOptimizeArtwork,
  });
  final PlayerController? controller;
  final bool Function()? canOptimizeArtwork;
  final Future<void> Function()? onBackup, onRestore, onReset;
  final VoidCallback? onCustomizeHome;
  final Widget? localSources;
  final AppSettings settings;
  final VoidCallback onAddFiles;
  final VoidCallback? onAddFolder, onImported;
  final ProviderConnections? providers;
  final Track? previewTrack;
  final DownloadManager? downloads;
  final int trackCount;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsCategory category = SettingsCategory.general;
  String subpage = '', search = '';
  final searchController = TextEditingController();
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  static const pages = <SettingsCategory, List<String>>{
    SettingsCategory.general: ['Idioma', 'Janela e bandeja'],
    SettingsCategory.appearance: [
      'Tema e cores',
      'Tipografia',
      'Movimento e acessibilidade',
    ],
    SettingsCategory.customization: [
      'Página inicial',
      'Now Playing',
      'Capas e fundo',
      'Informações e painéis',
      'Barra do player',
      'Informações da barra',
      'Letras — apresentação',
    ],
    SettingsCategory.playback: [
      'Mixes and radios',
      'Play contínuo',
      'Equalizador',
    ],
    SettingsCategory.library: [
      'Sua coleção',
      'Agrupamento visual',
      'Mostrar bibliotecas por fonte',
    ],
    SettingsCategory.onedrive: ['Fontes conectadas'],
    SettingsCategory.downloads: [
      'Visão geral',
      'Downloads permanentes',
      'Cache automático',
      'Limpeza',
    ],
    SettingsCategory.lastfm: ['Last.fm', 'Provedores de letras'],
    SettingsCategory.data: ['Backup e manutenção'],
  };
  void navigate(SettingsCategory next, [String page = '']) => setState(() {
    category = next;
    subpage = page;
    search = '';
    searchController.clear();
  });
  String get activePage =>
      pages[category]!.contains(subpage) ? subpage : pages[category]!.first;
  Widget pageList(List<Widget> children) => ListView(
    key: ValueKey('settings.content.${category.name}.$activePage'),
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
    children: children,
  );
  Widget unavailable(String message) => Center(child: UiText(message));

  Widget visualSwitch(
    String key,
    String title, {
    String? subtitle,
    bool fallback = true,
  }) => Card(
    child: SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: UiText(title),
      subtitle: subtitle == null ? null : UiText(subtitle),
      value: widget.settings.visualBool(key, fallback: fallback),
      onChanged: widget.settings.saving
          ? null
          : (value) => widget.settings.updateVisual(key, value),
    ),
  );
  Widget choice(
    String key,
    String label,
    Map<String, String> choices,
    String fallback,
  ) {
    final value = widget.settings.visualChoice(key, fallback);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        key: ValueKey('$key:$value'),
        initialValue: choices.containsKey(value) ? value : fallback,
        decoration: InputDecoration(labelText: ui(context, label)),
        items: choices.entries
            .map(
              (entry) => DropdownMenuItem(
                value: entry.key,
                child: UiText(entry.value),
              ),
            )
            .toList(),
        onChanged: widget.settings.saving
            ? null
            : (value) {
                if (value != null) widget.settings.updateVisual(key, value);
              },
      ),
    );
  }

  List<Widget> typography({bool lyrics = false}) => [
    for (final entry in {
      'font_title': 'Títulos',
      'font_body': 'Textos e campos',
      'font_secondary': 'Informações secundárias',
      'font_navigation': 'Menu lateral',
      'lyrics_font': 'Letras',
      'lyrics_spacing': 'Espaçamento das letras',
    }.entries.where((entry) => entry.key.startsWith('lyrics_') == lyrics)) ...[
      UiText(entry.value),
      Slider(
        value: widget.settings.visualNumber(
          entry.key,
          entry.key == 'lyrics_font'
              ? 26
              : entry.key == 'lyrics_spacing'
              ? 1.25
              : entry.key == 'font_title'
              ? 22
              : entry.key == 'font_secondary'
              ? 12
              : 14,
        ),
        min: entry.key == 'lyrics_spacing' ? 1 : 10,
        max: entry.key == 'lyrics_spacing' ? 2 : 40,
        divisions: entry.key == 'lyrics_spacing' ? 10 : 30,
        onChanged: (v) => widget.settings.updateVisual(entry.key, v),
      ),
    ],
  ];
  Widget subsection(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiText(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    ),
  );
  List<Widget> appearance() => [
    subsection('Tema e cores', [
      UiText(
        'Personalize o Music Time',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 20),
      DropdownButtonFormField<ThemeMode>(
        isExpanded: true,
        key: ValueKey(widget.settings.mode),
        initialValue: widget.settings.mode,
        decoration: InputDecoration(labelText: ui(context, 'Tema')),
        items: const [
          DropdownMenuItem(value: ThemeMode.dark, child: UiText('Escuro')),
          DropdownMenuItem(value: ThemeMode.light, child: UiText('Claro')),
          DropdownMenuItem(value: ThemeMode.system, child: UiText('Sistema')),
        ],
        onChanged: widget.settings.saving
            ? null
            : (value) => widget.settings.update(theme: value),
      ),
      const SizedBox(height: 20),
      visualSwitch(
        'system_accent',
        'Usar cor de destaque do Windows',
        fallback: false,
        subtitle: widget.settings.systemAccent == null
            ? 'Se a cor do sistema estiver indisponível, será usada a cor manual.'
            : 'Acompanha as alterações de cor do Windows.',
      ),
      DropdownButtonFormField<int>(
        isExpanded: true,
        key: ValueKey(widget.settings.accent),
        initialValue: widget.settings.accent,
        decoration: InputDecoration(labelText: ui(context, 'Cor de destaque')),
        items: AppSettings.accents.entries
            .map(
              (entry) => DropdownMenuItem(
                value: entry.key,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Color(entry.key), size: 20),
                    const SizedBox(width: 12),
                    UiText(entry.value),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged:
            widget.settings.saving ||
                widget.settings.visualBool('system_accent', fallback: false)
            ? null
            : (value) => widget.settings.update(color: value),
      ),
      const SizedBox(height: 24),
    ]),
    subsection('Navegação e início', [
      if (widget.onCustomizeHome != null)
        TextButton.icon(
          onPressed: widget.onCustomizeHome,
          icon: const Icon(Icons.home),
          label: const UiText('Página inicial · personalizar seções'),
        ),
    ]),
    subsection('Visual da reprodução', [
      UiText('Now Playing', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final entry in nowPlayingStyles.entries)
            SizedBox(
              width: 144,
              child: Semantics(
                button: true,
                selected: widget.settings.nowPlayingStyle == entry.key,
                child: InkWell(
                  key: ValueKey('style.${entry.key}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: widget.settings.saving
                      ? null
                      : () => widget.settings.updateVisual('style', entry.key),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        width: 2,
                        color: widget.settings.nowPlayingStyle == entry.key
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                      ),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 92,
                          child: Center(
                            child: NowPlayingArtwork(
                              style: entry.key,
                              track: widget.previewTrack,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        UiText(entry.value),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ]),
    subsection('Capas e fundo', [
      choice('cover_shape', 'Formato da capa', {
        'rounded': 'Arredondada',
        'square': 'Quadrada',
        'circle': 'Circular',
      }, 'rounded'),
      choice('cover_position', 'Posição da capa', {
        'left': 'À esquerda',
        'right': 'À direita',
        'above': 'Acima das informações',
      }, 'left'),
      const UiText('Tamanho da capa'),
      Slider(
        value: widget.settings.visualNumber('cover_scale', 1).clamp(.7, 1.8),
        min: .7,
        max: 1.8,
        divisions: 11,
        onChanged: widget.settings.saving
            ? null
            : (value) => widget.settings.updateVisual('cover_scale', value),
      ),
      choice('background', 'Fundo', {
        'solid': 'Sólido',
        'cover': 'Cores da capa',
        'blur': 'Capa desfocada',
      }, 'blur'),
      const UiText('Intensidade do fundo'),
      Slider(
        value: widget.settings
            .visualNumber('background_intensity', .20)
            .clamp(.05, .45),
        min: .05,
        max: .45,
        divisions: 8,
        onChanged: widget.settings.saving
            ? null
            : (value) =>
                  widget.settings.updateVisual('background_intensity', value),
      ),
    ]),
    subsection('Informações e acessibilidade', [
      visualSwitch(
        'show_queue',
        'Mostrar fila lateral',
        subtitle: 'No Now Playing quando houver espaço suficiente.',
      ),
      visualSwitch('additional_info', 'Mostrar álbum nas informações'),
      visualSwitch('animations', 'Animações da reprodução'),
      visualSwitch(
        'reduce_motion',
        'Reduzir movimento',
        fallback: false,
        subtitle:
            'A preferência de acessibilidade do sistema também é respeitada.',
      ),
    ]),

    subsection('Restaurar aparência', [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: widget.settings.saving
              ? null
              : widget.settings.resetVisual,
          child: const UiText('Restaurar padrões visuais'),
        ),
      ),
    ]),
  ];
  List<Widget> language() => [
    subsection('Idioma', [
      DropdownButtonFormField<String>(
        isExpanded: true,
        key: ValueKey(widget.settings.language),
        initialValue: widget.settings.language,
        decoration: InputDecoration(
          labelText: ui(context, 'Idioma do aplicativo'),
        ),
        items: const [
          DropdownMenuItem(value: 'pt', child: UiText('Português (Brasil)')),
          DropdownMenuItem(value: 'en', child: UiText('English')),
        ],
        onChanged: widget.settings.saving
            ? null
            : (value) {
                if (value != null) widget.settings.setLanguage(value);
              },
      ),
    ]),
  ];
  List<Widget> texts() => [
    subsection('Textos da interface', typography()),
    subsection('Textos e espaçamento das letras', typography(lyrics: true)),
    subsection('Letras', [
      visualSwitch(
        'online_lyrics',
        'Online lyrics fallback · LRCLIB',
        subtitle: 'Looks up the track title, artist, album and duration when your own lyrics are unavailable. Disabled in offline mode.',
      ),
      visualSwitch('lyrics_auto_scroll', 'Rolagem automática das letras'),
    ]),
  ];
  List<Widget> controls() => [
    subsection('Organizar barra de reprodução', [
      PlayerBarOrganizer(settings: widget.settings),
    ]),
    subsection('Play contínuo', [
      visualSwitch(
        'smart_play',
        'Play contínuo',
        fallback: false,
        subtitle: 'Ao terminar a fila, acrescenta faixas do mesmo gênero da sua biblioteca, sem reproduzir músicas externas.',
      ),
    ]),
    subsection('Cache e pré-carregamento', [
      visualSwitch(
        'cache_enabled',
        'Cache automático de áudio',
        fallback: true,
      ),
      Text(
        'Limite: ${widget.settings.visualNumber('cache_gb', 10).round()} GB',
      ),
      Slider(
        value: widget.settings.visualNumber('cache_gb', 10).clamp(1, 100),
        min: 1,
        max: 100,
        divisions: 99,
        onChanged: (v) => widget.settings.updateVisual('cache_gb', v),
      ),
      Text(
        uiFormat(
          context,
          'Pré-carregar ${widget.settings.visualNumber('prefetch_count', 5).round()} faixas',
          'Preload ${widget.settings.visualNumber('prefetch_count', 5).round()} tracks',
        ),
      ),
      Slider(
        value: widget.settings.visualNumber('prefetch_count', 5).clamp(0, 20),
        min: 0,
        max: 20,
        divisions: 20,
        onChanged: (v) => widget.settings.updateVisual('prefetch_count', v),
      ),
      const UiText(
        'Somente arquivos completos. Cache automático é limpo após 30 dias sem uso, respeitando o limite. Downloads explícitos são permanentes até você removê-los.',
      ),
    ]),
    subsection('Informações da barra', [
      const UiText(
        'Primeira linha: título. Escolha os campos da segunda linha:',
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final e in {
            'artist': 'Artista',
            'album': 'Álbum',
            'year': 'Ano',
            'format': 'Formato',
            'source': 'Fonte',
          }.entries)
            FilterChip(
              label: UiText(e.value),
              selected: widget.settings
                  .visualList('bar_fields', ['artist', 'album'])
                  .contains(e.key),
              onSelected: (v) {
                final next = List<String>.of(
                  widget.settings.visualList('bar_fields', ['artist', 'album']),
                );
                if (v) {
                  next.add(e.key);
                } else {
                  next.remove(e.key);
                }
                widget.settings.updateVisual('bar_fields', next);
              },
            ),
        ],
      ),
    ]),
    if (widget.controller != null)
      subsection('Equalizador', [
        EqualizerPanel(
          controller: widget.controller!,
          settings: widget.settings,
        ),
      ]),
  ];
  List<Widget> library() => [
    subsection('Disponibilidade', [
      visualSwitch(
        'offline_only',
        'Modo offline',
        fallback: false,
        subtitle: 'Exibe e reproduz somente músicas locais acessíveis, downloads completos e cache válido.',
      ),
    ]),
    subsection('Agrupamento visual', [
      visualSwitch(
        'merge_artists',
        'Agrupar variações de nomes de artistas',
        fallback: true,
        subtitle: 'Normaliza somente caixa e espaços. Não divide nomes por vírgula, ponto ou &. Use mesclar para correções explícitas.',
      ),
      visualSwitch(
        'merge_albums',
        'Agrupar cópias de álbuns por tags e faixas',
        fallback: true,
        subtitle: 'Preserva edições/identificadores diferentes e os arquivos originais. Requer numeração e duração conhecidas.',
      ),
    ]),
    if (widget.providers != null)
      subsection('Mostrar bibliotecas por fonte', [
        SourceVisibilitySettings(
          providers: widget.providers!,
          onChanged: widget.onImported ?? () {},
        ),
      ]),
    subsection('Sua coleção', [
      if (widget.downloads != null)
        CollectionSummary(store: widget.downloads!.store),
      visualSwitch(
        'artist_biographies',
        'Artist biographies',
        subtitle: 'Fetch a short artist biography from TheAudioDB. Cached descriptions are available offline.',
      ),
      visualSwitch(
        'artist_photos',
        'Baixar fotos de artistas automaticamente',
        subtitle: 'Consulta o nome do artista no TheAudioDB e salva a foto neste dispositivo. Fotos já baixadas funcionam offline.',
      ),
      const SizedBox(height: 16),
      Text('${widget.trackCount} ${ui(context, 'músicas na biblioteca')}'),
      const SizedBox(height: 20),
      const UiText(
        'Os arquivos originais são preservados. Biblioteca e fila ficam salvas neste dispositivo.',
      ),
    ]),
  ];
  List<Widget> windows() => [
    subsection('Janela e bandeja', [
      DropdownButtonFormField<bool>(
        isExpanded: true,
        key: ValueKey('close.${widget.settings.closeToTray}'),
        initialValue: widget.settings.closeToTray,
        decoration: InputDecoration(
          labelText: ui(context, 'Ao fechar a janela'),
        ),
        items: [
          DropdownMenuItem(value: true, child: UiText('Manter na bandeja')),
          DropdownMenuItem(value: false, child: UiText('Encerrar aplicativo')),
        ],
        onChanged: widget.settings.saving
            ? null
            : (v) {
                if (v != null) {
                  widget.settings.setWindowBehavior('windows.close_to_tray', v);
                }
              },
      ),
      const SizedBox(height: 24),
      DropdownButtonFormField<bool>(
        isExpanded: true,
        key: ValueKey('minimize.${widget.settings.minimizeToTray}'),
        initialValue: widget.settings.minimizeToTray,
        decoration: InputDecoration(
          labelText: ui(context, 'Ao minimizar a janela'),
        ),
        items: [
          DropdownMenuItem(
            value: false,
            child: UiText('Manter na barra de tarefas'),
          ),
          DropdownMenuItem(
            value: true,
            child: UiText('Minimizar para a bandeja'),
          ),
        ],
        onChanged: widget.settings.saving
            ? null
            : (v) {
                if (v != null) {
                  widget.settings.setWindowBehavior(
                    'windows.minimize_to_tray',
                    v,
                  );
                }
              },
      ),
      const SizedBox(height: 16),
      const UiText('Use Sair no menu da bandeja para encerrar o aplicativo.'),
      const UiText(
        'Os controles de mídia do Windows funcionam enquanto o app estiver aberto, inclusive na bandeja.',
      ),
    ]),
  ];
  Widget content() {
    final page = activePage;
    switch (category) {
      case SettingsCategory.general:
        return pageList(page == 'Idioma' ? language() : windows());
      case SettingsCategory.appearance:
        return pageList([
          if (page == 'Tema e cores') appearance().first,
          if (page == 'Tipografia') subsection('Tipografia', typography()),
          if (page == 'Movimento e acessibilidade')
            subsection(page, [
              visualSwitch('animations', 'Animações da reprodução'),
              visualSwitch(
                'reduce_motion',
                'Reduzir movimento',
                fallback: false,
                subtitle: 'A preferência de acessibilidade do sistema também é respeitada.',
              ),
            ]),
          subsection('Restaurar aparência', [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: widget.settings.saving
                    ? null
                    : widget.settings.resetAppearance,
                icon: const Icon(Icons.restore),
                label: const UiText(
                  'Restaurar apenas aparência e acessibilidade',
                ),
              ),
            ),
          ]),
        ]);
      case SettingsCategory.customization:
        return pageList([
          if (page == 'Página inicial') appearance()[1],
          if (page == 'Now Playing') ...[
            appearance()[2],
            OutlinedButton.icon(
              onPressed: widget.settings.saving
                  ? null
                  : widget.settings.resetNowPlaying,
              icon: const Icon(Icons.restore),
              label: const UiText('Restaurar Now Playing'),
            ),
          ],
          if (page == 'Capas e fundo') appearance()[3],
          if (page == 'Informações e painéis')
            subsection(page, [
              visualSwitch('show_queue', 'Mostrar fila lateral'),
              visualSwitch('additional_info', 'Mostrar álbum nas informações'),
            ]),
          if (page == 'Barra do player') controls().first,
          if (page == 'Informações da barra') controls()[3],
          if (page == 'Letras — apresentação') ...[
            subsection(
              'Textos e espaçamento das letras',
              typography(lyrics: true),
            ),
            subsection('Letras', [
              visualSwitch(
                'lyrics_auto_scroll',
                'Rolagem automática das letras',
              ),
            ]),
          ],
        ]);
      case SettingsCategory.playback:
        return pageList([
          if (page == 'Mixes and radios')
            ArtistSelectionSettings(settings: widget.settings),
          if (page == 'Play contínuo') controls()[1],
          if (page == 'Equalizador' && widget.controller != null)
            controls().last,
        ]);
      case SettingsCategory.library:
        return pageList([
          if (page == 'Sua coleção') library().last,
          if (page == 'Agrupamento visual') library()[1],
          if (page == 'Mostrar bibliotecas por fonte' &&
              widget.providers != null)
            library()[2],
        ]);
      case SettingsCategory.onedrive:
        return widget.providers == null
            ? unavailable('Provedor indisponível.')
            : ProviderSettingsPage(
                providers: widget.providers!,
                onlyMicrosoft: true,
                onAddFolder: widget.onAddFolder,
                onAddFiles: widget.onAddFiles,
                localSources: widget.localSources,
                onImported: widget.onImported ?? () {},
              );
      case SettingsCategory.downloads:
        if (widget.downloads == null) {
          return unavailable('Downloads indisponíveis.');
        }
        if (page == 'Downloads permanentes') {
          return DownloadsDialog(
            key: const ValueKey('offline.permanent'),
            manager: widget.downloads!,
            embedded: true,
            fixedCacheTab: false,
          );
        }
        if (page == 'Cache automático') {
          return pageList([
            controls()[2],
            DownloadsDialog(
              key: const ValueKey('offline.cache'),
              manager: widget.downloads!,
              embedded: true,
              fixedCacheTab: true,
              shrinkWrap: true,
            ),
          ]);
        }
        return pageList([
          if (page == 'Visão geral') ...[
            library().first,
            DownloadsDialog(
              manager: widget.downloads!,
              embedded: true,
              overviewOnly: true,
              shrinkWrap: true,
            ),
          ],
          subsection(page, [
            StorageSettings(
              key: ValueKey('storage.$page'),
              manager: widget.downloads!,
              showCleanup: page == 'Limpeza',
              showOverview: page == 'Visão geral',
            ),
          ]),
        ]);
      case SettingsCategory.lastfm:
        if (page == 'Provedores de letras') {
          return pageList([
            subsection('Provedores de letras', [
              visualSwitch(
                'online_lyrics',
                'Online lyrics fallback · LRCLIB',
                subtitle: 'Looks up the track title, artist, album and duration when your own lyrics are unavailable. Disabled in offline mode.',
              ),
            ]),
          ]);
        }
        return widget.providers == null
            ? unavailable('Provedor indisponível.')
            : ProviderSettingsPage(
                providers: widget.providers!,
                onlyMicrosoft: false,
                onAddFiles: widget.onAddFiles,
                onImported: widget.onImported ?? () {},
              );
      case SettingsCategory.data:
        return widget.onBackup == null ||
                widget.onRestore == null ||
                widget.onReset == null
            ? unavailable('Gestão de dados indisponível.')
            : DataSettings(
                onBackup: widget.onBackup!,
                onRestore: widget.onRestore!,
                onReset: widget.onReset!,
                storage: widget.downloads == null
                    ? null
                    : ArtworkStorageSettings(
                        store: widget.downloads!.store,
                        canOptimize: () =>
                            (widget.canOptimizeArtwork?.call() ?? true) &&
                            !(widget.downloads!.running ||
                                widget.downloads!.maintaining ||
                                (widget.providers?.anyMicrosoftBusy ?? false) ||
                                (widget.providers?.additional.busy.isNotEmpty ??
                                    false) ||
                                widget.downloads!.store.artwork.running),
                      ),
              );
    }
  }

  Widget searchResults() {
    final q = search.toLowerCase().trim();
    const terms = <String, String>{
      'Tema e cores': 'theme colors accent destaque windows',
      'Tipografia': 'font text texto fontes tamanho size',
      'Movimento e acessibilidade':
          'animation accessibility reduce motion animações',
      'Janela e bandeja': 'window tray close minimize fechar minimizar',
      'Now Playing': 'model style classic vinyl minimal gallery focus modelo',
      'Capas e fundo':
          'artwork cover background blur size capa fundo desfoque tamanho',
      'Barra do player':
          'organize order controls separator volume ordem controles separador',
      'Informações da barra':
          'artist album year format source artista ano formato fonte',
      'Letras — apresentação':
          'lyrics font scroll spacing letras rolagem espaçamento',
      'Sua coleção': 'summary collection tracks genres biography photos resumo músicas gêneros biografias fotos',
      'Agrupamento visual':
          'group merge artists albums agrupar artistas álbuns',
      'Cache automático': 'preload prefetch limit gb pré-carregamento limite',
      'Limpeza':
          'clear cache photos incomplete downloads limpar fotos incompletos',
      'Visão geral':
          'offline disk storage space occupied espaço ocupação armazenamento',
      'Provedores de letras': 'lyrics lrclib online fallback letras',
      'Last.fm': 'scrobble keys account import queue índices chaves conta fila importar',
      'Backup e manutenção': 'export restore reset restart diagnostic exportar restaurar redefinir diagnóstico',
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (final entry in pages.entries)
          for (final page in entry.value)
            if ((' ${ui(context, entry.key.label)} ${ui(context, page)} $page ${entry.key.label} ${terms[page] ?? ''} '
                    .toLowerCase())
                .contains(q))
              Card(
                child: ListTile(
                  leading: Icon(entry.key.icon),
                  title: UiText(page),
                  subtitle: UiText(entry.key.label),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () => navigate(entry.key, page),
                ),
              ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.settings,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: compact ? 68 : 248,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                children: [
                  for (final item in SettingsCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Tooltip(
                        message: ui(context, item.label),
                        child: Material(
                          color: item == category
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          child: compact
                              ? IconButton(
                                  key: ValueKey('settings.${item.name}'),
                                  isSelected: item == category,
                                  onPressed: () => navigate(item),
                                  icon: Icon(item.icon),
                                )
                              : ListTile(
                                  key: ValueKey('settings.${item.name}'),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  selected: item == category,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  leading: Icon(item.icon),
                                  title: UiText(
                                    item.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onTap: () => navigate(item),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                    child: TextField(
                      key: const ValueKey('settings.search'),
                      controller: searchController,
                      onChanged: (v) => setState(() => search = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: ui(context, 'Buscar nas configurações'),
                        filled: true,
                        suffixIcon: search.isEmpty
                            ? null
                            : IconButton(
                                tooltip: ui(context, 'Limpar'),
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  search = '';
                                  searchController.clear();
                                }),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  if (search.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: UiText(
                        category.label,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (pages[category]!.length > 1)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Row(
                          spacing: 8,
                          children: [
                            for (final page in pages[category]!)
                              ChoiceChip(
                                key: ValueKey('settings.page.$page'),
                                label: UiText(page),
                                selected: activePage == page,
                                onSelected: (_) =>
                                    setState(() => subpage = page),
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (widget.settings.saving) const LinearProgressIndicator(),
                  if (widget.settings.error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: UiText(widget.settings.error!),
                    ),
                  Expanded(child: search.isEmpty ? content() : searchResults()),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
