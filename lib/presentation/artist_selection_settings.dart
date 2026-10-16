import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings/app_settings.dart';
import 'ui_language.dart';

class ArtistSelectionSettings extends StatefulWidget {
  const ArtistSelectionSettings({super.key, required this.settings});
  final AppSettings settings;
  @override
  State<ArtistSelectionSettings> createState() =>
      _ArtistSelectionSettingsState();
}

class _ArtistSelectionSettingsState extends State<ArtistSelectionSettings> {
  AppSettings get settings => widget.settings;
  final form = GlobalKey<FormState>();
  late final controllers = [
    for (final radio in [false, true])
      TextEditingController(
        text: '${settings.artistSelectionSize(radio: radio)}',
      ),
  ];
  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const UiText(
              'Mixes and radios',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const UiText(
              'Finite selections, from 1 to 500 tracks. Changes apply to new generations only. Continuous play is separate.',
            ),
            for (final radio in [false, true])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: TextFormField(
                  controller: controllers[radio ? 1 : 0],
                  decoration: InputDecoration(
                    labelText: ui(
                      context,
                      radio ? 'Artist radio size' : 'Artist mix size',
                    ),
                    helperText: '1–500',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (s) =>
                      (int.tryParse(s ?? '') ?? 0) < 1 ||
                          (int.tryParse(s ?? '') ?? 501) > 500
                      ? ui(context, 'Enter a number from 1 to 500')
                      : null,
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: settings.saving
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        await settings.setArtistSelectionSize(
                          int.parse(controllers[0].text),
                        );
                        await settings.setArtistSelectionSize(
                          int.parse(controllers[1].text),
                          radio: true,
                        );
                      },
                child: const UiText('Save'),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: settings.saving
                    ? null
                    : () async {
                        await settings.setArtistSelectionSize(40);
                        await settings.setArtistSelectionSize(40, radio: true);
                        for (final c in controllers) {
                          c.text = '40';
                        }
                      },
                icon: const Icon(Icons.restore),
                label: const UiText('Restore defaults'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
