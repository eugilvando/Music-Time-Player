import 'design_icon.dart';
import 'design_tokens.dart';
import 'media_card_size.dart';
import 'ui_language.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'library_screen.dart';
import 'navigation.dart';
import '../settings/sidebar_layout.dart';
import '../settings/app_settings.dart';
import '../persistence/library_store.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.settings,
    required this.store,
    this.nativeIntegration = false,
    this.validation = false,
    this.designPreview = false,
    this.smokeAudio,
    this.startupNotice,
  });
  final AppSettings settings;
  final LibraryStore store;
  final bool nativeIntegration, validation;
  final bool designPreview;
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
    height: MtDesign.topbar,
    child: InkWell(
      key: const ValueKey('navigation.brand'),
      onTap: goHome,
      child: Padding(
        padding: compact
            ? const EdgeInsets.symmetric(vertical: 12)
            : const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                  height: 32,
                  width: 150,
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
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              for (final section
                  in sidebarOrder(
                        widget.settings.visualList(
                          'sidebar_order',
                          sidebarItems,
                        ),
                      )
                      .where(
                        (id) => widget.settings
                            .visualList('sidebar_items', sidebarItems)
                            .contains(id),
                      )
                      .map(
                        (id) =>
                            AppSection.values.firstWhere((s) => s.name == id),
                      ))
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 7 : 16,
                    vertical: 4,
                  ),
                  child: Tooltip(
                    message: ui(context, section.label),
                    child: ListTile(
                      minTileHeight: 44,
                      key: ValueKey('navigation.${section.name}'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      selected: selected == section,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .secondaryContainer,
                      leading: compact ? null : MtIcon(section.icon, size: 20),
                      title: compact
                          ? Center(child: MtIcon(section.icon, size: 20))
                          : UiText(
                              section.label,
                              style: TextStyle(
                                fontSize: widget.settings.visualNumber(
                                  'font_navigation',
                                  14,
                                ),
                                fontFamily: widget.settings.secondaryFont,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                      horizontalTitleGap: 8,
                      contentPadding: compact
                          ? EdgeInsets.zero
                          : const EdgeInsets.symmetric(horizontal: 12),
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
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: Tooltip(
                message: ui(context, 'Configurações'),
                child: compact
                    ? Semantics(
                        button: true,
                        selected: selected == AppSection.settings,
                        label: ui(context, 'Configurações'),
                        child: InkWell(
                          key: const ValueKey('navigation.settings'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() {
                              selected = AppSection.settings;
                              navigationReset++;
                            });
                            if (drawer) scaffoldKey.currentState?.closeDrawer();
                          },
                          child: const SizedBox.expand(
                            child: Center(
                              child: MtIcon(Icons.settings, size: 20),
                            ),
                          ),
                        ),
                      )
                    : ListTile(
                        key: const ValueKey('navigation.settings'),
                        minTileHeight: 44,
                        horizontalTitleGap: 12,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        leading: compact
                            ? null
                            : const MtIcon(Icons.settings, size: 20),
                        contentPadding: compact
                            ? EdgeInsets.zero
                            : const EdgeInsets.symmetric(horizontal: 16),
                        title: compact
                            ? const Center(
                                child: MtIcon(Icons.settings, size: 20),
                              )
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
                          designPreview: widget.designPreview,
                          sidebar: desktop
                              ? SizedBox(
                                  width: collapsed
                                      ? MtDesign.sidebarCollapsed
                                      : MtDesign.sidebar,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface
                                          .withValues(alpha: .78),
                                      border: Border(
                                        right: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: sidebar(
                                        drawer: false,
                                        compact: collapsed,
                                      ),
                                    ),
                                  ),
                                )
                              : null,
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
