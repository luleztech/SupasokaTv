import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/carousel_slide_sheet.dart';
import '../widgets/stagger_entrance.dart';

class CarouselScreen extends StatelessWidget {
  const CarouselScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final slides = store.config.carousel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggerEntrance(
            index: 0,
            child: AdminPageHeader(
              title: 'Home carousel',
              icon: Icons.view_carousel_rounded,
              actions: [
                FilledButton.icon(
                  onPressed: () => showCarouselSlideSheet(context, store, null, -1),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add slide'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ReorderableListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: slides.length,
              onReorder: store.reorderCarousel,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, c) {
                    final t = Curves.easeOut.transform(animation.value);
                    return Transform.scale(
                      scale: 1.0 + 0.02 * t,
                      child: Material(
                        elevation: 6 * t,
                        borderRadius: BorderRadius.circular(18),
                        color: Colors.transparent,
                        child: c,
                      ),
                    );
                  },
                  child: child,
                );
              },
              itemBuilder: (context, i) {
                final s = slides[i];
                return Padding(
                  key: ValueKey('car_${s.channelId}_$i'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: StaggerEntrance(
                    index: i,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => showCarouselSlideSheet(context, store, s, i),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF161a24),
                                Color(0xFF12151c),
                              ],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8, right: 8),
                                    child: Icon(Icons.drag_indicator_rounded, color: Colors.white.withValues(alpha: 0.35)),
                                  ),
                                ),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 96,
                                    height: 56,
                                    child: Image.network(
                                      s.img,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => ColoredBox(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        child: const Icon(Icons.broken_image_outlined),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      s.title.replaceAll('\n', ' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded),
                                  onPressed: () => showCarouselSlideSheet(context, store, s, i),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Remove slide?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                                        ],
                                      ),
                                    );
                                    if (ok == true) await store.removeCarouselAt(i);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
