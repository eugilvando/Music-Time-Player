import 'package:flutter/material.dart';

import '../settings/app_settings.dart';

class ResizableSidePanel extends StatefulWidget {
  const ResizableSidePanel({
    super.key,
    required this.settings,
    required this.preference,
    required this.defaultWidth,
    required this.maxWidth,
    required this.child,
  });

  final AppSettings settings;
  final String preference;
  final double defaultWidth, maxWidth;
  final Widget child;

  @override
  State<ResizableSidePanel> createState() => _ResizableSidePanelState();
}

class _ResizableSidePanelState extends State<ResizableSidePanel> {
  double? draggingWidth;

  @override
  Widget build(BuildContext context) {
    final width =
        (draggingWidth ??
                widget.settings.visualNumber(
                  widget.preference,
                  widget.defaultWidth,
                ))
            .clamp(280.0, widget.maxWidth.clamp(280.0, 960.0))
            .toDouble();
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              key: ValueKey('${widget.preference}.resize'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) => setState(() {
                draggingWidth = ((draggingWidth ?? width) - details.delta.dx)
                    .clamp(280.0, widget.maxWidth.clamp(280.0, 960.0))
                    .toDouble();
              }),
              onHorizontalDragEnd: (_) async {
                await widget.settings.updateVisual(
                  widget.preference,
                  draggingWidth ?? width,
                );
                if (mounted) setState(() => draggingWidth = null);
              },
              onHorizontalDragCancel: () =>
                  setState(() => draggingWidth = null),
              child: const SizedBox(width: 8),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
