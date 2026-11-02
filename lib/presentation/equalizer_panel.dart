import '../platform/output_equalizer.dart';
import 'playback_transition_settings.dart';

import 'package:file_selector/file_selector.dart';

import '../settings/parametric_eq.dart';
import 'design_icon.dart';
import 'ui_language.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../application/player_controller.dart';
import '../settings/app_settings.dart';
import '../settings/equalizer_presets.dart';

class EqualizerPanel extends StatefulWidget {
  const EqualizerPanel({
    super.key,
    required this.controller,
    required this.settings,
    this.outputs,
  });
  final PlayerController controller;
  final AppSettings settings;
  final OutputEqualizer? outputs;
  @override
  State<EqualizerPanel> createState() => _EqualizerPanelState();
}

class _EqualizerPanelState extends State<EqualizerPanel> {
  bool busy = false;
  String? error;
  List<double> get gains => [
    for (final f in PlayerController.equalizerFrequencies)
      widget.settings.visualNumber('eq_$f', 0),
  ];
  Map<String, ParametricEqProfile> get parametric => decodeParametricProfiles(
    widget.settings.visualChoice('eq_autoeq_profiles', '{}'),
  );
  ParametricEqProfile? get activeProfile => selection.startsWith('autoeq:')
      ? parametric[selection.substring(7)]
      : null;
  Map<String, List<double>> get custom =>
      decodeEqualizerPresets(widget.settings.visualChoice('eq_presets', '{}'));
  Map<String, List<double>> get presets => {
    for (final entry in equalizerPresets.entries)
      'builtin:${entry.key}': entry.value,
    for (final entry in custom.entries) 'custom:${entry.key}': entry.value,
  };
  String get selection {
    final saved = widget.settings.visualChoice('eq_preset', '');
    if (saved.startsWith('autoeq:') &&
        parametric.containsKey(saved.substring(7))) {
      return saved;
    }
    final current = gains;
    final matches = presets.entries
        .where(
          (entry) => List.generate(
            5,
            (i) => entry.value[i] == current[i],
          ).every((v) => v),
        )
        .map((e) => e.key)
        .toList();
    final preferred = widget.settings.visualChoice('eq_preset', '');
    if (preferred == 'manual') return 'manual';
    return matches.contains(preferred)
        ? preferred
        : matches.firstOrNull ?? 'manual';
  }

  Future<void> persist(String key, Object value) async {
    await widget.settings.updateVisual(key, value);
    if (widget.settings.error != null) {
      throw StateError('Preferência não salva');
    }
  }

  Future<void> applyPreset(String id) async {
    final profile = id.startsWith('autoeq:')
        ? parametric[id.substring(7)]
        : null;
    final values = id == 'manual' ? gains : presets[id];
    if (values == null && profile == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (profile != null) {
        await widget.controller.setParametricEqualizer(
          widget.settings.visualBool('eq_enabled', fallback: false),
          profile,
        );
      } else {
        await widget.controller.setEqualizer(
          widget.settings.visualBool('eq_enabled', fallback: false),
          values!,
        );
        for (var i = 0; i < values.length; i++) {
          await persist(
            'eq_${PlayerController.equalizerFrequencies[i]}',
            values[i],
          );
        }
      }
      await persist('eq_preset', id);
      await widget.outputs?.rememberCurrent();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível aplicar ou salvar o preset.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importAutoEq() async {
    if (parametric.length >= 50) {
      setState(() => error = 'Limite de 50 perfis AutoEQ.');
      return;
    }
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'AutoEQ ParametricEQ', extensions: ['txt']),
        ],
      );
      if (file == null || !mounted) return;
      if (await file.length() > 65536) {
        throw const FormatException('O arquivo de perfil é muito grande.');
      }
      final source = await file.readAsString();
      final suggested = file.name
          .replaceAll(RegExp(r'\.txt$', caseSensitive: false), '')
          .replaceAll('ParametricEQ', '')
          .trim();
      final parsed = ParametricEqProfile.parse(
        source,
        suggested.isEmpty
            ? 'AutoEQ'
            : suggested.substring(0, suggested.length.clamp(0, 60)),
      );
      if (!mounted) return;
      final field = TextEditingController(text: parsed.name);
      String? invalid;
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const UiText('Importar perfil AutoEQ'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: field,
                      maxLength: 60,
                      decoration: InputDecoration(
                        labelText: ui(context, 'Nome do preset'),
                        errorText: invalid,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${parsed.filters.length} filtros · Preamp ${parsed.effectivePreamp.toStringAsFixed(1)} dB',
                    ),
                    const SizedBox(height: 12),
                    for (final f in parsed.filters)
                      Text(
                        '${f.type} · ${f.frequency.toStringAsFixed(0)} Hz · ${f.gain.toStringAsFixed(1)} dB · Q ${f.q}',
                      ),
                    const SizedBox(height: 16),
                    const UiText(
                      'A pré-amplificação pode ser reduzida para evitar saturação. O arquivo original será preservado.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const UiText('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final name = field.text.trim();
                  if (name.isEmpty ||
                      parametric.keys.any(
                        (n) => n.toLowerCase() == name.toLowerCase(),
                      )) {
                    update(
                      () =>
                          invalid = 'Informe um nome diferente para o perfil.',
                    );
                    return;
                  }
                  Navigator.pop(context, name);
                },
                child: const UiText('Salvar e selecionar'),
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      field.dispose();
      if (chosen == null || !mounted) return;
      final profile = ParametricEqProfile(
        chosen,
        parsed.preamp,
        parsed.filters,
      );
      await persist(
        'eq_autoeq_profiles',
        jsonEncode({
          for (final entry in parametric.entries)
            entry.key: entry.value.toJson(),
          chosen: profile.toJson(),
        }),
      );
      await applyPreset('autoeq:$chosen');
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível importar o perfil AutoEQ.');
      }
    }
  }

  Future<void> savePreset() async {
    final field = TextEditingController();
    String? validation;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          title: const UiText('Salvar preset'),
          content: TextField(
            controller: field,
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: ui(context, 'Nome do preset'),
              errorText: validation,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const UiText('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final name = field.text.trim();
                if (name.isEmpty ||
                    custom.keys.any(
                      (key) => key.toLowerCase() == name.toLowerCase(),
                    ) ||
                    custom.length >= 50) {
                  update(
                    () => validation = name.isEmpty
                        ? 'Informe um nome.'
                        : custom.length >= 50
                        ? 'Limite de 50 presets.'
                        : 'Já existe um preset com esse nome.',
                  );
                  return;
                }
                Navigator.pop(context, name);
              },
              child: const UiText('Salvar'),
            ),
          ],
        ),
      ),
    );
    // The dialog's closing animation may still reference its text controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    field.dispose();
    if (name == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await persist('eq_presets', jsonEncode({...custom, name: gains}));
      await persist('eq_preset', 'custom:$name');
      await widget.outputs?.rememberCurrent();
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível salvar o preset.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deletePreset() async {
    final id = selection;
    if (id.startsWith('autoeq:')) {
      final next = parametric..remove(id.substring(7));
      await applyPreset('manual');
      try {
        await persist(
          'eq_autoeq_profiles',
          jsonEncode({for (final e in next.entries) e.key: e.value.toJson()}),
        );
      } catch (_) {
        if (mounted) {
          setState(() => error = 'Não foi possível remover o preset.');
        }
      }
      return;
    }
    if (!id.startsWith('custom:')) return;
    final next = custom..remove(id.substring(7));
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await persist('eq_presets', jsonEncode(next));
      await persist('eq_preset', 'manual');
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível remover o preset.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change(String key, Object value) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final enabled = key == 'eq_enabled'
          ? value as bool
          : widget.settings.visualBool('eq_enabled', fallback: false);
      final gains = [
        for (final f in PlayerController.equalizerFrequencies)
          key == 'eq_$f'
              ? value as double
              : widget.settings.visualNumber('eq_$f', 0),
      ];
      final profile = activeProfile;
      if (profile != null && key == 'eq_enabled') {
        await widget.controller.setParametricEqualizer(enabled, profile);
      } else {
        await widget.controller.setEqualizer(enabled, gains);
      }
      await persist(key, value);
      if (key != 'eq_enabled') await persist('eq_preset', 'manual');
      await widget.outputs?.rememberCurrent();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'O motor não conseguiu aplicar o equalizador.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget outputSettings() => ListenableBuilder(
    listenable: widget.outputs!,
    builder: (context, _) {
      final outputs = widget.outputs!;
      final current = outputs.current;
      final binding = outputs.binding;
      final selected = binding?['enabled'] == true
          ? binding!['preset'] as String? ?? 'off'
          : 'off';
      final choices = <String, String>{
        'off': ui(context, 'Sem equalização'),
        'manual': ui(context, 'Ajuste manual'),
        for (final id in presets.keys)
          id: id.startsWith('custom:')
              ? id.substring(7)
              : ui(context, id.substring(8)),
        for (final name in parametric.keys) 'autoeq:$name': 'AutoEQ: $name',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const UiText('Perfil por dispositivo de saída'),
            subtitle: const UiText(
              'Troca o equalizador quando a saída padrão do sistema muda.',
            ),
            value: outputs.automatic,
            onChanged: busy
                ? null
                : (value) async {
                    setState(() => busy = true);
                    try {
                      await outputs.setAutomatic(value);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
          ),
          const SizedBox(height: 12),
          Text(
            '${ui(context, 'Saída atual')}: ${current?.name ?? ui(context, 'Não identificada')}',
          ),
          const SizedBox(height: 20),
          PlaybackSettingField<String>(
            label: 'Perfil desta saída',
            value: choices.containsKey(selected) ? selected : 'off',
            items: [
              for (final entry in choices.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: busy || !outputs.automatic || current == null
                ? null
                : (value) async {
                    if (value == null) return;
                    setState(() => busy = true);
                    try {
                      await outputs.bindPreset(value);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
          ),
          const SizedBox(height: 12),
          const UiText(
            'Escolha a saída no sistema e associe um perfil aqui. Saídas sem associação ficam sem equalização.',
          ),
          if (outputs.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: UiText(
                outputs.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const Divider(height: 40),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.outputs != null) outputSettings(),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const UiText('Equalizador'),
        subtitle: UiText(
          activeProfile == null
              ? 'Cinco bandas; redução automática de ganho para compensar reforços.'
              : 'Perfil AutoEQ com filtros paramétricos e proteção de ganho.',
        ),
        value: widget.settings.visualBool('eq_enabled', fallback: false),
        onChanged: busy ? null : (v) => change('eq_enabled', v),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: ValueKey('equalizer:$selection'),
        initialValue: selection,
        isExpanded: true,
        isDense: false,
        decoration: InputDecoration(
          labelText: ui(context, 'Preset do equalizador'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        items: [
          const DropdownMenuItem(
            value: 'manual',
            child: UiText('Ajuste manual'),
          ),
          for (final profile in parametric.values)
            DropdownMenuItem(
              value: 'autoeq:${profile.name}',
              child: Text(
                'AutoEQ: ${profile.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          for (final id in presets.keys)
            DropdownMenuItem(
              value: id,
              child: Text(
                id.startsWith('custom:')
                    ? '${ui(context, 'Personalizado')}: ${id.substring(7)}'
                    : ui(context, id.substring(8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: busy
            ? null
            : (value) {
                if (value != null) applyPreset(value);
              },
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton.icon(
            onPressed: busy ? null : importAutoEq,
            icon: const MtIcon(Icons.file_open),
            label: const UiText('Importar AutoEQ'),
          ),
          if (activeProfile == null)
            TextButton.icon(
              onPressed: busy ? null : savePreset,
              icon: const MtIcon(Icons.save),
              label: const UiText('Salvar preset'),
            ),
          if (selection.startsWith('custom:') ||
              selection.startsWith('autoeq:'))
            TextButton.icon(
              onPressed: busy ? null : deletePreset,
              icon: const MtIcon(Icons.delete_outline),
              label: const UiText('Excluir preset'),
            ),
        ],
      ),
      if (error != null)
        UiText(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (activeProfile != null) ...[
        const SizedBox(height: 12),
        Text(
          '${activeProfile!.filters.length} filtros · Preamp ${activeProfile!.effectivePreamp.toStringAsFixed(1)} dB',
        ),
        const SizedBox(height: 8),
        const UiText(
          'O perfil é aplicado integralmente. Os presets de cinco bandas continuam disponíveis.',
        ),
      ],
      if (activeProfile == null &&
          widget.settings.visualBool('eq_enabled', fallback: false))
        for (final f in PlayerController.equalizerFrequencies)
          Row(
            children: [
              SizedBox(width: 72, child: Text('$f Hz')),
              Expanded(
                child: Slider(
                  value: widget.settings.visualNumber('eq_$f', 0),
                  min: -12,
                  max: 12,
                  divisions: 24,
                  label:
                      '${widget.settings.visualNumber('eq_$f', 0).round()} dB',
                  onChanged: busy ? null : (v) => change('eq_$f', v),
                ),
              ),
            ],
          ),
      const Divider(height: 32),
    ],
  );
}
