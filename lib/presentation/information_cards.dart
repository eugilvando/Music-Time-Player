import 'ui_language.dart';

import 'package:flutter/material.dart';

class InformationCards extends StatelessWidget {
  const InformationCards({super.key, required this.values});
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: constraints.maxWidth.clamp(640.0, double.infinity),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in values.entries)
              SizedBox(
                width:
                    (constraints.maxWidth.clamp(640.0, double.infinity) - 36) /
                    4,
                child: Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Tooltip(
                          message: ui(context, item.key),
                          child: UiText(
                            item.key,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
