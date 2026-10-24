import 'package:flutter/material.dart';

/// Pill surface shared by native dropdown selectors, matching the input theme.
class RoundedSelect extends StatelessWidget {
  const RoundedSelect({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: DropdownButtonHideUnderline(child: child),
      ),
    ),
  );
}
