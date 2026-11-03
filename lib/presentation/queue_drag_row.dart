import 'package:flutter/material.dart';

/// Start reordering from the cover/text/empty area; child taps still work.
class QueueDragRow extends StatelessWidget {
  const QueueDragRow({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      ReorderableDragStartListener(index: index, child: child);
}
