import 'design_icon.dart';
import 'artist_selection_settings.dart';
import 'storage_settings.dart';
import 'artwork_storage_settings.dart';
import 'source_visibility_settings.dart';
import 'ui_language.dart';

import 'package:flutter/material.dart';

import 'settings_card.dart';

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
  general('Geral e aparência', Icons.settings_outlined),
  customization('Interface e player', Icons.dashboard_customize_outlined),
  playback('Reprodução e áudio', Icons.graphic_eq),
  library('Biblioteca e metadados', Icons.library_music_outlined),
  onedrive('Fontes de música', Icons.cloud_outlined),
  cache('Cache e offline', Icons.storage_outlined),
  downloads('Downloads', Icons.download),
  lastfm('Integrações', Icons.extension_outlined),
  data('Backup e avançado', Icons.backup_outlined);

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
    this.initialCategory = SettingsCategory.general,
  });
  final SettingsCategory initialCategory;
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
  late SettingsCategory category = widget.initialCategory;
  String subpage = '', search = '';
  final searchController = TextEditingController();
  final sectionKeys = <String, GlobalKey>{};
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  static const pages = <SettingsCategory, List<String>>{
    SettingsCategory.general: [
      'Tema e cores',
      'Idioma',
      'Janela e bandeja',
      'Movimento e acessibilidade',
    ],
    SettingsCategory.customization: [
      'Tipografia',
      'Fonte primária',
      'Fonte secundária',
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
    SettingsCategory.cache: [
      'Visão geral',
      'Disponibilidade',
      'Armazenamento e cache',
      'Limpeza',
    ],
    SettingsCategory.downloads: [
      'Visão geral',
      'Downloads permanentes',
      'Cache automático',
      'Limpeza',
    ],
    SettingsCategory.lastfm: ['Last.fm', 'Provedores de letras'],
    SettingsCategory.data: ['Backup e manutenção'],
  };
  void navigate(SettingsCategory next, [String page = '']) {
    setState(() {
      category = next;
      subpage = page;
      search = '';
      searchController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final title = switch (page) {
        'Fonte primária' || 'Fonte secundária' => 'Tipografia',
        'Letras — apresentação' => 'Letras',
        'Barra do player' => 'Organizar barra de reprodução',
        _ => page,
      };
      final target = sectionKeys[title]?.currentContext;
      if (target != null && mounted) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  String get activePage =>
      pages[category]!.contains(subpage) ? subpage : pages[category]!.first;
  Widget pageList(List<Widget> children) => SingleChildScrollView(
    key: ValueKey('settings.content.${category.name}.$activePage'),
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
  Widget unavailable(String message) => Center(child: UiText(message));

  Widget visualSwitch(
    String key,
    String title, {
    String? subtitle,
    bool fallback = true,
  }) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    title: UiText(title),
    subtitle: subtitle == null ? null : UiText(subtitle),
    value: widget.settings.visualBool(key, fallback: fallback),
    onChanged: widget.settings.saving
        ? null
        : (value) => widget.settings.updateVisual(key, value),
  );
  Widget choice(
    String key,
    String label,
    Map<String, String> choices,
    String fallback,
  ) {
    final value = widget.settings.visualChoice(key, fallback);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        style: Theme.of(context).textTheme.bodyMedium,
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
    if (!lyrics) ...[
      fontChoice(
        'primary_font_family',
        'Fonte primária',
        widget.settings.primaryFont,
      ),
      const SizedBox(height: 16),
      fontChoice(
        'secondary_font_family',
        'Fonte secundária',
        widget.settings.secondaryFont,
      ),
      const SizedBox(height: 16),
      const UiText(
        'A fonte primária é usada nos títulos; a secundária, nos textos, menus e campos.',
      ),
      const SizedBox(height: 8),
      const UiText(
        'Inter e Bricolage Grotesque estão incluídas no app. As demais fontes dependem do sistema.',
      ),
      const SizedBox(height: 16),
      Text(
        'Music Time — Aa Bb Cc 123',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        ui(context, 'Prévia dos textos, menus e campos.'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 20),
    ],
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
  Widget fontChoice(String key, String label, String family) =>
      DropdownButtonFormField<String>(
        key: ValueKey('$key:$family'),
        initialValue: family,
        isExpanded: true,
        decoration: InputDecoration(labelText: ui(context, label)),
        items: [
          for (final entry in AppSettings.fontFamilies.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, style: TextStyle(fontFamily: entry.key)),
            ),
        ],
        onChanged: widget.settings.saving
            ? null
            : (value) {
                if (value != null) widget.settings.updateVisual(key, value);
              },
      );

  Widget subsection(String title, List<Widget> children) => SettingsCard(
    key: sectionKeys.putIfAbsent(title, () => GlobalKey()),
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
          const SizedBox(height: SettingsSpacing.controlGap),
          ...children,
        ],
      ),
    ),
  );
  List<Widget> appearance() => [
    subsection('Tema e cores', [
      DropdownButtonFormField<ThemeMode>(
        style: Theme.of(context).textTheme.bodyMedium,
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
        style: Theme.of(context).textTheme.bodyMedium,
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
                    MtIcon(Icons.circle, color: Color(entry.key), size: 20),
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
          icon: const MtIcon(Icons.home),
          label: const UiText('Página inicial · personalizar seções'),
        ),
    ]),
    subsection('Now Playing', [
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
    ]),
    subsection('Capas e fundo', [
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
        style: Theme.of(context).textTheme.bodyMedium,
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
      DropdownButtonFormField<int>(
        key: ValueKey(
          'continuous.${widget.settings.visualNumber('continuous_count', 5)}',
        ),
        style: Theme.of(context).textTheme.bodyMedium,
        initialValue: widget.settings
            .visualNumber('continuous_count', 5)
            .round()
            .clamp(1, 100),
        decoration: InputDecoration(
          labelText: ui(context, 'Faixas a adicionar'),
        ),
        items: [
          for (final n in {
            1,
            5,
            10,
            20,
            50,
            100,
            widget.settings
                .visualNumber('continuous_count', 5)
                .round()
                .clamp(1, 100),
          }.toList()..sort())
            DropdownMenuItem(value: n, child: Text('$n')),
        ],
        onChanged: (n) {
          if (n != null) {
            widget.settings.updateVisual('continuous_count', n.toDouble());
          }
        },
      ),
    ]),
    subsection('Cache e pré-carregamento', [
      visualSwitch(
        'cache_enabled',
        'Cache automático de áudio',
        fallback: true,
      ),
      Text(
        '${ui(context, 'Limite')}: ${widget.settings.visualNumber('cache_gb', 10).round()} GB',
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
        style: Theme.of(context).textTheme.bodyMedium,
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
        style: Theme.of(context).textTheme.bodyMedium,
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
    switch (category) {
      case SettingsCategory.general:
        return pageList([
          appearance().first,
          ...language(),
          ...windows(),
          subsection('Movimento e acessibilidade', [
            visualSwitch('animations', 'Animações da reprodução'),
            visualSwitch(
              'reduce_motion',
              'Reduzir movimento',
              fallback: false,
              subtitle: 'A preferência de acessibilidade do sistema também é respeitada.',
            ),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: widget.settings.saving
                  ? null
                  : widget.settings.resetGeneral,
              icon: const MtIcon(Icons.restore),
              label: const UiText('Restaurar configurações gerais'),
            ),
          ),
        ]);
      case SettingsCategory.customization:
        return pageList([
          appearance()[3],
          appearance()[2],
          subsection('Tipografia', typography()),
          subsection('Letras', [
            visualSwitch('lyrics_auto_scroll', 'Rolagem automática das letras'),
            ...typography(lyrics: true),
          ]),
          controls()[3],
          controls().first,
          appearance()[1],
          subsection('Informações e painéis', [
            visualSwitch('show_queue', 'Mostrar fila lateral'),
            visualSwitch('additional_info', 'Mostrar álbum nas informações'),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: widget.settings.saving
                  ? null
                  : widget.settings.resetInterface,
              icon: const MtIcon(Icons.restore),
              label: const UiText('Restaurar interface e player'),
            ),
          ),
        ]);
      case SettingsCategory.playback:
        return pageList([
          controls()[1],
          controls()[2],
          ArtistSelectionSettings(settings: widget.settings),
          if (widget.controller != null) controls().last,
        ]);
      case SettingsCategory.library:
        return pageList([
          if (widget.downloads != null)
            CollectionSummary(store: widget.downloads!.store),
          const SizedBox(height: 20),
          if (widget.providers != null) library()[2],
          library().last,
          library()[1],
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
      case SettingsCategory.cache:
        return widget.downloads == null
            ? unavailable('Downloads indisponíveis.')
            : pageList([
                DownloadsDialog(
                  manager: widget.downloads!,
                  embedded: true,
                  overviewOnly: true,
                  shrinkWrap: true,
                ),
                library().first,
                subsection('Armazenamento e cache', [
                  StorageSettings(
                    manager: widget.downloads!,
                    showCleanup: false,
                  ),
                ]),
                subsection('Limpeza de cache', [
                  StorageSettings(
                    manager: widget.downloads!,
                    showOverview: false,
                  ),
                ]),
              ]);
      case SettingsCategory.downloads:
        return widget.downloads == null
            ? unavailable('Downloads indisponíveis.')
            : DownloadsDialog(manager: widget.downloads!, embedded: true);
      case SettingsCategory.lastfm:
        return pageList([
          if (widget.providers != null)
            ProviderSettingsPage(
              providers: widget.providers!,
              onlyMicrosoft: false,
              onAddFiles: widget.onAddFiles,
              onImported: widget.onImported ?? () {},
              shrinkWrap: true,
            ),
          subsection('Provedores de letras', [
            visualSwitch(
              'online_lyrics',
              'Online lyrics fallback · LRCLIB',
              subtitle: 'Looks up the track title, artist, album and duration when your own lyrics are unavailable. Disabled in offline mode.',
            ),
          ]),
        ]);
      case SettingsCategory.data:
        return widget.onBackup == null ||
                widget.onRestore == null ||
                widget.onReset == null
            ? unavailable('Gestão de dados indisponível.')
            : DataSettings(
                storageHasSurface: true,
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
      'Now Playing':
          'model style classic vinyl minimal cover lyrics modelo capa letras',
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
                  leading: MtIcon(entry.key.icon),
                  title: UiText(page),
                  subtitle: UiText(entry.key.label),
                  trailing: const MtIcon(Icons.arrow_forward),
                  onTap: () => navigate(entry.key, page),
                ),
              ),
      ],
    );
  }

  bool searching = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.settings,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            compact ? 16 : 24,
            compact ? 16 : 24,
            0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: compact ? 48 : 240,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final item in SettingsCategory.values)
                      Tooltip(
                        message: ui(context, item.label),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color: item == category
                                ? Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            child: ListTile(
                              key: ValueKey('settings.${item.name}'),
                              minTileHeight: 44,
                              horizontalTitleGap: 8,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: compact ? 0 : 12,
                              ),
                              leading: compact
                                  ? null
                                  : MtIcon(item.icon, size: 20),
                              title: compact
                                  ? Center(child: MtIcon(item.icon, size: 20))
                                  : UiText(
                                      item.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                              selected: item == category,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onTap: () => navigate(item),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 12 : 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: UiText(
                            category.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: ui(context, 'Buscar nas configurações'),
                          icon: const MtIcon(Icons.search),
                          onPressed: () => setState(() {
                            searching = !searching;
                            if (!searching) {
                              search = '';
                              searchController.clear();
                            }
                          }),
                        ),
                      ],
                    ),
                    if (searching)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          key: const ValueKey('settings.search'),
                          controller: searchController,
                          onChanged: (v) => setState(() => search = v),
                          decoration: InputDecoration(
                            hintText: ui(context, 'Buscar nas configurações'),
                            prefixIcon: const MtIcon(Icons.search),
                            suffixIcon: IconButton(
                              icon: const MtIcon(Icons.close),
                              onPressed: () => setState(() {
                                search = '';
                                searchController.clear();
                              }),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: SettingsSpacing.titleGap),
                    if (widget.settings.saving) const LinearProgressIndicator(),
                    if (widget.settings.error != null)
                      UiText(widget.settings.error!),
                    Expanded(
                      child: search.isEmpty ? content() : searchResults(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
