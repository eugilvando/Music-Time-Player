import 'player_bar.dart' show playerBarHeight;
import 'media_card_size.dart';
import 'ui_language.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'library_screen.dart';
import 'navigation.dart';
import '../settings/app_settings.dart';
import '../persistence/library_store.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.settings,
    required this.store,
    this.nativeIntegration = false,
    this.validation = false,
    this.smokeAudio,
    this.startupNotice,
  });
  final AppSettings settings;
  final LibraryStore store;
  final bool nativeIntegration, validation;
  final String? smokeAudio, startupNotice;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection selected = AppSection.home;
  final libraryKey = GlobalKey();
  int navigationReset = 0;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    if (widget.validation) selected = AppSection.nowPlaying;
    if (widget.startupNotice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.startupNotice!),
              duration: const Duration(seconds: 12),
            ),
          );
        }
      });
    }
  }

  void goHome() {
    setState(() {
      selected = AppSection.home;
      navigationReset++;
    });
    scaffoldKey.currentState?.closeDrawer();
  }

  Widget brand(bool compact) => SizedBox(
    height: 84,
    child: InkWell(
      key: const ValueKey('navigation.brand'),
      onTap: goHome,
      child: Padding(
        padding: compact
            ? const EdgeInsets.symmetric(vertical: 16)
            : const EdgeInsets.fromLTRB(20, 16, 16, 16),
        child: compact
            ? SvgPicture.asset(
                'assets/branding/icon.svg',
                height: 32,
                semanticsLabel: 'Music Time',
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: SvgPicture.asset(
                  Theme.of(context).brightness == Brightness.dark
                      ? 'assets/branding/logo-on_dark.svg'
                      : 'assets/branding/logo-on_light.svg',
                  height: 39.1,
                  width: 166.6,
                  semanticsLabel: 'Music Time',
                ),
              ),
      ),
    ),
  );

  Widget sidebar({required bool drawer, bool compact = false}) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        brand(compact),
        Expanded(
          child: ListView(
            key: const ValueKey('navigation.sidebar'),
            children: [
              for (final section in AppSection.values.where(
                (s) => s != AppSection.settings && s != AppSection.downloads,
              ))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Tooltip(
                    message: ui(context, section.label),
                    child: ListTile(
                      key: ValueKey('navigation.${section.name}'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: selected == section,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .secondaryContainer,
                      leading: compact ? null : Icon(section.icon),
                      title: compact
                          ? Center(child: Icon(section.icon))
                          : UiText(
                              section.label,
                              style: TextStyle(
                                fontSize: widget.settings.visualNumber(
                                  'font_navigation',
                                  14,
                                ),
                              ),
                            ),
                      contentPadding: compact ? EdgeInsets.zero : null,
                      onTap: () {
                        setState(() {
                          selected = section;
                          navigationReset++;
                        });
                        if (drawer) scaffoldKey.currentState?.closeDrawer();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          key: const ValueKey("navigation.settings.footer"),
          height: playerBarHeight(context, widget.settings),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Center(
              child: Tooltip(
                message: ui(context, 'Configurações'),
                child: ListTile(
                  key: const ValueKey('navigation.settings'),
                  leading: compact ? null : const Icon(Icons.settings),
                  contentPadding: compact ? EdgeInsets.zero : null,
                  title: compact
                      ? const Center(child: Icon(Icons.settings))
                      : const UiText('Configurações'),
                  selected: selected == AppSection.settings,
                  onTap: () {
                    setState(() {
                      selected = AppSection.settings;
                      navigationReset++;
                    });
                    if (drawer) scaffoldKey.currentState?.closeDrawer();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.settings,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final collapsed = widget.settings.visualBool(
          'sidebar_collapsed',
          fallback: false,
        );
        return Scaffold(
          key: scaffoldKey,
          drawer: desktop ? null : Drawer(child: sidebar(drawer: true)),
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (desktop)
                      SizedBox(
                        width: collapsed ? 72 : 232,
                        child: sidebar(drawer: false, compact: collapsed),
                      ),
                    if (desktop) const VerticalDivider(width: 1),
                    Expanded(
                      child: MediaCardSizeScope.wrap(
                        widget.settings,
                        LibraryScreen(
                          key: libraryKey,
                          section: selected,
                          navigationReset: navigationReset,
                          onMenu: desktop
                              ? () => widget.settings.updateVisual(
                                  'sidebar_collapsed',
                                  !collapsed,
                                )
                              : () => scaffoldKey.currentState?.openDrawer(),
                          menuTooltip: desktop
                              ? collapsed
                                    ? 'Expandir barra lateral'
                                    : 'Recolher barra lateral'
                              : 'Menu',
                          onNavigate: (section) =>
                              setState(() => selected = section),
                          settings: widget.settings,
                          store: widget.store,
                          nativeIntegration: widget.nativeIntegration,
                          validation: widget.validation,
                          smokeAudio: widget.smokeAudio,
                        ),
                      ),
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
