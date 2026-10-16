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
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 16,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 16, right: 12),
            child: Icon(Icons.search),
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 64,
            minHeight: 48,
          ),
          hintText: ui(context, 'Buscar músicas, artistas, álbuns e playlists'),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: ui(context, 'Limpar busca'),
                  onPressed: clear,
                  icon: const Icon(Icons.close),
                ),
        ),
      ),
    ),
  );
}
