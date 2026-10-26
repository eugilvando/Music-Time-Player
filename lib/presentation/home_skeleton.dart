import 'package:flutter/material.dart';

class HomeSkeleton extends StatefulWidget {
  const HomeSkeleton({super.key});
  @override
  State<HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.stop();
    } else if (!animation.isAnimating) {
      animation.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: Localizations.localeOf(context).languageCode == 'pt'
        ? 'Carregando início'
        : 'Loading Home',
    child: ExcludeSemantics(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          Widget block(double height, {double? width}) => Container(
            height: height,
            width: width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.onSurface.withValues(
                alpha: MediaQuery.disableAnimationsOf(context)
                    ? .08
                    : .04 + animation.value * .05,
              ),
            ),
          );
          return LayoutBuilder(
            builder: (context, size) => ListView(
              key: const ValueKey('home.skeleton'),
              padding: const EdgeInsets.symmetric(vertical: 24),
              children: [
                block(32, width: 300),
                const SizedBox(height: 12),
                block(16, width: 180),
                for (var section = 0; section < 3; section++) ...[
                  const SizedBox(height: 40),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: block(24, width: 180),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      for (var i = 0; i < (size.maxWidth >= 640 ? 4 : 2); i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Column(
                              children: [
                                block(150),
                                const SizedBox(height: 10),
                                block(14),
                                const SizedBox(height: 6),
                                block(10),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );
}
