import 'design_icon.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui_language.dart';

class CatalogSearchField extends StatefulWidget {
  const CatalogSearchField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String> onChanged;
  @override
  State<CatalogSearchField> createState() => _CatalogSearchFieldState();
}

class _CatalogSearchFieldState extends State<CatalogSearchField> {
  late final controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant CatalogSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != controller.text) controller.text = widget.value;
  }

  void clear() {
    if (controller.text.isEmpty) return;
    controller.clear();
    widget.onChanged('');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): clear},
    child: ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        key: const ValueKey('catalog.search'),
        controller: controller,
        style: Theme.of(context).textTheme.bodySmall,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 10,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 16, right: 12),
            child: MtIcon(Icons.search, size: 20),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 64,
            minHeight: 40,
          ),
          hintText: ui(context, 'Buscar músicas, artistas, álbuns e playlists'),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: ui(context, 'Limpar busca'),
                  onPressed: clear,
                  icon: const MtIcon(Icons.close),
                ),
        ),
      ),
    ),
  );
}
