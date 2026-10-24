import 'package:flutter/material.dart';

/// Shared surface for settings sections, including embedded provider pages.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child, this.padding = 20});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

List<Widget> settingsSections(List<Widget> children) {
  final groups = <List<Widget>>[[]];
  for (final child in children) {
    if (child is Divider) {
      groups.add([]);
    } else {
      groups.last.add(child);
    }
  }
  return [
    for (final group in groups.where((group) => group.isNotEmpty))
      SettingsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: group,
        ),
      ),
  ];
}
