import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../library/catalog.dart';

String alphabetLetter(String name) {
  final value = searchKey(name.trim());
  return value.isNotEmpty && RegExp('[a-z]').hasMatch(value[0])
      ? value[0].toUpperCase()
      : '#';
}

Map<String, int> alphabetPositions(Iterable<String> names) {
  final result = <String, int>{};
  var index = 0;
  for (final name in names) {
    result.putIfAbsent(alphabetLetter(name), () => index);
    index++;
  }
  return result;
}

/// Works with lazy lists, grids and detailed tables without loading row widgets.
class AlphabetScrollbar extends StatefulWidget {
  const AlphabetScrollbar({
    super.key,
    required this.controller,
    required this.positions,
    required this.itemCount,
    required this.child,
    this.onSelect,
  });
  final ScrollController controller;
  final Map<String, int> positions;
  final int itemCount;
  final Widget child;
  final Future<int?> Function(String)? onSelect;
  @override
  State<AlphabetScrollbar> createState() => _AlphabetScrollbarState();
}

class _AlphabetScrollbarState extends State<AlphabetScrollbar> {
  final content = GlobalKey();
  int generation = 0;
  RenderSliverMultiBoxAdaptor? findSliver(RenderObject? node) {
    if (node is RenderSliverMultiBoxAdaptor) return node;
    RenderSliverMultiBoxAdaptor? result;
    node?.visitChildren((child) {
      result ??= findSliver(child);
    });
    return result;
  }

  Future<void> select(String letter) async {
    final ticket = ++generation;
    final index = widget.onSelect == null
        ? widget.positions[letter]
        : await widget.onSelect!(letter);
    if (!mounted || ticket != generation || index == null) return;
    for (var attempt = 0; attempt < 10; attempt++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || ticket != generation || !widget.controller.hasClients) {
        return;
      }
      final position = widget.controller.position;
      if (!position.hasContentDimensions) continue;
      final sliver = findSliver(content.currentContext?.findRenderObject());
      if (sliver == null || sliver.firstChild == null) return;
      final first = sliver.firstChild!;
      var last = first;
      for (
        var child = sliver.firstChild;
        child != null;
        child = sliver.childAfter(child)
      ) {
        last = child;
        if ((child.parentData as SliverMultiBoxAdaptorParentData).index ==
            index) {
          final target = RenderAbstractViewport.of(child)
              .getOffsetToReveal(child, 0)
              .offset;
          widget.controller.jumpTo(target.clamp(0, position.maxScrollExtent));
          return;
        }
      }
      final a = first.parentData as SliverMultiBoxAdaptorParentData;
      final b = last.parentData as SliverMultiBoxAdaptorParentData;
      final stride = b.index! > a.index! && b.layoutOffset! > a.layoutOffset!
          ? (b.layoutOffset! - a.layoutOffset!) / (b.index! - a.index!)
          : position.viewportDimension / ((b.index! - a.index!) + 1);
      final start = RenderAbstractViewport.of(first)
          .getOffsetToReveal(first, 0)
          .offset;
      final target = start + (index - a.index!) * stride;
      widget.controller.jumpTo(target.clamp(0, position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: KeyedSubtree(key: content, child: widget.child),
      ),
      SizedBox(
        width: 28,
        child: ListView(
          key: const ValueKey('alphabet.rail'),
          primary: false,
          scrollCacheExtent: const ScrollCacheExtent.pixels(600),
          itemExtent: 20,
          children: [
            for (final letter in [
              '#',
              ...List.generate(26, (i) => String.fromCharCode(65 + i)),
            ])
              Tooltip(
                message: letter,
                child: InkWell(
                  key: ValueKey('alphabet.$letter'),
                  onTap: widget.positions.containsKey(letter)
                      ? () => select(letter)
                      : null,
                  child: Center(
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: widget.positions.containsKey(letter)
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).disabledColor,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
