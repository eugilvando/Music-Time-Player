import 'media_card_size.dart';
import 'design_icon.dart';
import 'ui_language.dart';
import 'item_action_region.dart';

import 'dart:math';

import 'package:flutter/material.dart';

/// Headers and lazy rows share the available width without horizontal scrolling.
class MediaDetailsTable extends StatefulWidget {
  const MediaDetailsTable({
    super.key,
    required this.headers,
    required this.widths,
    required this.itemCount,
    required this.rowBuilder,
    this.onChooseColumns,
    this.columnKey,
  });
  final List<String> headers;
  final List<double> widths;
  final int itemCount;
  final List<Widget> Function(int) rowBuilder;
  final VoidCallback? onChooseColumns;
  final String? columnKey;
  @override
  State<MediaDetailsTable> createState() => _MediaDetailsTableState();
}

class _MediaDetailsTableState extends State<MediaDetailsTable> {
  int get itemCount => widget.itemCount;
  Future<void> chooseColumns(BuildContext context) async {
    final scope = MediaCardSizeScope.of(context);
    final key =
        'details_columns_${widget.columnKey ?? scope?.contextKey ?? 'catalog'}_${widget.headers.length}';
    final saved = scope?.settings?.visualList(
      key,
      List.generate(widget.headers.length, (i) => '$i'),
    );
    final selected = <int>{
      for (var i = 0; i < widget.headers.length; i++)
        if (saved == null || saved.contains('$i')) i,
    };
    final title = widget.headers.first == '#' ? 1 : 0;
    selected.add(title);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          insetPadding: const EdgeInsets.all(24),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          title: const UiText('Escolher colunas'),
          contentPadding: const EdgeInsets.all(24),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.headers.length; i++)
                    if (widget.headers[i].isNotEmpty &&
                        widget.headers[i] != '#')
                      CheckboxListTile(
                        title: Text(widget.headers[i]),
                        value: selected.contains(i),
                        onChanged: i == title
                            ? null
                            : (v) => update(() {
                                v == true
                                    ? selected.add(i)
                                    : selected.remove(i);
                              }),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const UiText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const UiText('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    await scope?.settings?.updateVisual(
      key,
      selected.map((v) => '$v').toList(),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final scope = MediaCardSizeScope.of(context);
      final key =
          'details_columns_${widget.columnKey ?? scope?.contextKey ?? 'catalog'}_${widget.headers.length}';
      final saved = widget.onChooseColumns != null
          ? null
          : scope?.settings?.visualList(
              key,
              List.generate(widget.headers.length, (i) => '$i'),
            );
      final title = widget.headers.first == '#' ? 1 : 0;
      final indices = [
        for (var i = 0; i < widget.headers.length; i++)
          if (i == title ||
              widget.headers[i].isEmpty ||
              widget.headers[i] == '#' ||
              saved == null ||
              saved.contains('$i'))
            i,
      ];
      final headers = [for (final i in indices) widget.headers[i]];
      final widths = [for (final i in indices) widget.widths[i]];
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final rowHeight = 44 * scale;
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
                  child: cells[i] is Text || cells[i] is IconButton
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
                    if (label.isEmpty &&
                        (scope?.settings != null ||
                            widget.onChooseColumns != null))
                      IconButton(
                        tooltip: ui(context, 'Escolher colunas'),
                        icon: const MtIcon(Icons.view_column, size: 16),
                        onPressed:
                            widget.onChooseColumns ??
                            () => chooseColumns(context),
                      )
                    else
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
                  itemBuilder: (_, i) {
                    final cells = widget.rowBuilder(i);
                    return ItemActionRegion(
                      child: row([for (final index in indices) cells[index]]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
