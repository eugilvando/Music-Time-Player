import 'package:flutter/material.dart';

/// Opens the same menu as the item's action button on secondary click.
class ItemActionRegion extends StatelessWidget {
  const ItemActionRegion({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Builder(
    builder: (region) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (_) {
        PopupMenuButtonState<dynamic>? menu;
        void visit(Element element) {
          if (menu != null) return;
          if (element is StatefulElement &&
              element.state is PopupMenuButtonState) {
            menu = element.state as PopupMenuButtonState<dynamic>;
            return;
          }
          element.visitChildren(visit);
        }

        (region as Element).visitChildren(visit);
        menu?.showButtonMenu();
      },
      child: child,
    ),
  );
}
