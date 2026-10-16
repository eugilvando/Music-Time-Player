import 'item_action_region.dart';

import 'dart:math';

import 'package:flutter/material.dart';

/// Headers and lazy rows share the available width without horizontal scrolling.
class MediaDetailsTable extends StatelessWidget {
  const MediaDetailsTable({
    super.key,
    required this.headers,
    required this.widths,
    required this.itemCount,
    required this.rowBuilder,
  });
  final List<String> headers;
  final List<double> widths;
  final int itemCount;
  final List<Widget> Function(int) rowBuilder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final rowHeight = 72 * scale;
      final width = size.maxWidth;
      final total = widths.reduce((a, b) => a + b);
      final fitted = widths.map((w) => w * width / total).toList();
      if (total > width && widths.length > 1) {
        final title = headers.first == '#' ? 1 : 0;
        final actions = headers.last.isEmpty ? widths.length - 1 : -1;
        final fixed = <int, double>{
          title: min(widths[title], max(160, width * .38)),
          if (title == 1) 0: min(64, width * .12),
          if (actions >= 0) actions: min(widths[actions], width * .4),
        };
        var reserved = fixed.values.fold(0.0, (a, b) => a + b);
        if (reserved > width * .9) {
          final factor = width * .9 / reserved;
          for (final key in fixed.keys.toList()) {
            fixed[key] = fixed[key]! * factor;
          }
          reserved = width * .9;
        }
        final flexible = List.generate(
          widths.length,
          (i) => i,
        ).where((i) => !fixed.containsKey(i)).toList();
        final weight = flexible.fold(0.0, (sum, i) => sum + widths[i]);
        for (var i = 0; i < fitted.length; i++) {
          fitted[i] = fixed[i] ?? (width - reserved) * widths[i] / weight;
        }
        if (flexible.isEmpty) {
          fitted[title] += width - reserved;
        }
      }
      Widget row(List<Widget> cells) => Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            SizedBox(
              width: fitted[i],
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: min(12, fitted[i] * .1),
                ),
                child: DefaultTextStyle.merge(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: cells[i] is Text
                      ? cells[i]
                      : ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: max(
                              fitted[i] - min(24, fitted[i] * .2),
                              min(160, widths[i] - 24),
                            ),
                            maxWidth: max(
                              fitted[i] - min(24, fitted[i] * .2),
                              min(160, widths[i] - 24),
                            ),
                            child: cells[i],
                          ),
                        ),
                ),
              ),
            ),
        ],
      );
      return SizedBox(
        height: size.hasBoundedHeight
            ? size.maxHeight
            : min(520, (itemCount + 1) * rowHeight),
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              SizedBox(
                height: 44 * scale,
                child: row([
                  for (final label in headers)
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  primary: false,
                  itemExtent: rowHeight,
                  itemCount: itemCount,
                  itemBuilder: (_, i) =>
                      ItemActionRegion(child: row(rowBuilder(i))),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
