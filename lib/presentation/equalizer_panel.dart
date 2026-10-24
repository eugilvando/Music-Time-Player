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
  });
  final PlayerController controller;
  final AppSettings settings;
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
  Map<String, List<double>> get custom =>
      decodeEqualizerPresets(widget.settings.visualChoice('eq_presets', '{}'));
  Map<String, List<double>> get presets => {
    for (final entry in equalizerPresets.entries)
      'builtin:${entry.key}': entry.value,
    for (final entry in custom.entries) 'custom:${entry.key}': entry.value,
  };
  String get selection {
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
    final values = id == 'manual' ? gains : presets[id];
    if (values == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.setEqualizer(
        widget.settings.visualBool('eq_enabled', fallback: false),
        values,
      );
      for (var i = 0; i < values.length; i++) {
        await persist(
          'eq_${PlayerController.equalizerFrequencies[i]}',
          values[i],
        );
      }
      await persist('eq_preset', id);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível aplicar ou salvar o preset.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
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
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível salvar o preset.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deletePreset() async {
    final id = selection;
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
      await widget.controller.setEqualizer(enabled, gains);
      await persist(key, value);
      if (key != 'eq_enabled') await persist('eq_preset', 'manual');
    } catch (_) {
      if (mounted) {
        setState(() => error = 'O motor não conseguiu aplicar o equalizador.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const UiText('Equalizador'),
        subtitle: const UiText(
          'Cinco bandas; redução automática de ganho para compensar reforços.',
        ),
        value: widget.settings.visualBool('eq_enabled', fallback: false),
        onChanged: busy ? null : (v) => change('eq_enabled', v),
      ),
      DropdownButtonFormField<String>(
        key: ValueKey('equalizer:$selection'),
        initialValue: selection,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: ui(context, 'Preset do equalizador'),
        ),
        items: [
          const DropdownMenuItem(
            value: 'manual',
            child: UiText('Ajuste manual'),
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
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: busy ? null : savePreset,
            icon: const MtIcon(Icons.save),
            label: const UiText('Salvar preset'),
          ),
          if (selection.startsWith('custom:'))
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
      if (widget.settings.visualBool('eq_enabled', fallback: false))
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
