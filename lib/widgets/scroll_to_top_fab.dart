// PixelVault — Scroll-to-top FAB.
//
// Listens to a [ScrollController] and shows a circular "back to top"
// button at the bottom-right once the user has scrolled past a small
// threshold. Sits in the same bottom-right slot as the global
// pending-changes FAB; when this button is visible it flips
// [scrollToTopVisible] so the pending-changes FAB (positioned in
// main.dart) can animate itself one slot higher.

import 'package:flutter/material.dart';

const Color _kBrandBlue = Color(0xFF0047BB);

/// Distance from the page top before the back-to-top button fades in.
const double _kShowThreshold = 200.0;

/// True while a [ScrollToTopFab] is currently visible on screen. The
/// global pending-changes FAB watches this so it can shift up out of
/// the way when the back-to-top button appears. Only one
/// [ScrollToTopFab] is expected to be mounted at a time (one per
/// route), so a plain bool is sufficient.
final ValueNotifier<bool> scrollToTopVisible = ValueNotifier<bool>(false);

/// Floating "scroll to top" button anchored bottom-right. Shares the
/// same bottom-right slot as the pending-changes FAB; the pending-
/// changes FAB reacts to [scrollToTopVisible] to step up one slot.
class ScrollToTopFab extends StatefulWidget {
  final ScrollController controller;

  const ScrollToTopFab({
    super.key,
    required this.controller,
  });

  @override
  State<ScrollToTopFab> createState() => _ScrollToTopFabState();
}

class _ScrollToTopFabState extends State<ScrollToTopFab> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    // Reset the global notifier so a stale "visible" doesn't keep the
    // pending-changes FAB elevated after we leave the page.
    if (_visible) scrollToTopVisible.value = false;
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final bool shouldShow = widget.controller.offset > _kShowThreshold;
    if (shouldShow != _visible && mounted) {
      setState(() => _visible = shouldShow);
      scrollToTopVisible.value = shouldShow;
    }
  }

  void _scrollToTop() {
    if (!widget.controller.hasClients) return;
    widget.controller.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: _visible
            ? FloatingActionButton(
                key: const ValueKey('scroll-to-top'),
                heroTag: 'scroll-to-top',
                onPressed: _scrollToTop,
                backgroundColor: _kBrandBlue,
                foregroundColor: Colors.white,
                tooltip: 'Back to top',
                child: const Icon(Icons.arrow_upward),
              )
            : const SizedBox.shrink(key: ValueKey('hidden')),
      ),
    );
  }
}
