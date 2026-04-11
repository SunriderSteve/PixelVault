// PixelVault — Home page (app landing screen).
//
// This is the first screen users see after the app finishes loading. It
// establishes the PixelVault brand with a full-bleed vibrant gradient +
// soft "blob" glows, and presents the four main entry points of the app
// as glassmorphism menu cards:
//
//   • Equipment Guides     → /learn/equip-guides
//   • Videography Basics   → /learn/videography-guides
//   • Production Scenarios → /scenarios
//   • Inventory List       → /inventory
//
// The grid is responsive: phones (<600 px wide) render a single column of
// wider tiles, while tablets / desktop render 2+ columns of taller tiles.
// Every card is wrapped in a [Hero] so destination pages can animate a
// matching hero into place if desired.

import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter used by BackdropFilter (frosted glass).

import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:go_router/go_router.dart';

// NLB-derived brand palette used by the background gradient on this page.
// These are kept file-private because the homepage is the only screen
// that renders this specific 4-stop gradient.
const Color _kBrandDarkBlue = Color(0xFF001F54); // Deep blue (gradient start)
const Color _kBrandBlue = Color(0xFF0047BB); // NLB blue
const Color _kBrandOrange = Color(0xFFFF8200); // NLB orange
const Color _kBrandRed = Color(0xFFE80029); // NLB red (gradient end)

/// Landing page widget.
///
/// Stateless because it owns no mutable state — navigation is delegated to
/// go_router and the cards just call [BuildContext.push] when tapped.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Solid black base so any translucency in the gradient / blobs still
      // reads as dark rather than falling through to the Material default.
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 1. Vibrant background gradient ──────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _kBrandDarkBlue,
                  _kBrandBlue,
                  _kBrandOrange,
                  _kBrandRed,
                ],
                // Biased stops so most of the canvas stays in the cool blue
                // range and warm tones only bleed into the bottom-right.
                stops: [0.0, 0.3, 0.7, 1.0],
              ),
            ),
          ),

          // ── 2. Ambient "blob" glows ─────────────────────────────────────
          // These are oversized circles positioned partly off-screen. The
          // visible glow comes from the large-blur BoxShadow, not the
          // container itself — the container is just an anchor point.
          Positioned(
            top: -150,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                color: _kBrandBlue.withValues(alpha: 0.4),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 150,
                    color: _kBrandBlue.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.3),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 150,
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),

          // ── 3. Foreground: scrollable content ───────────────────────────
          CustomScrollView(
            slivers: [
              // Frosted-glass app bar. The collapsed and expanded heights
              // are intentionally identical — this disables the default
              // shrink-on-scroll animation so the title stays fixed while
              // the grid scrolls underneath.
              SliverAppBar(
                backgroundColor: Colors.transparent,
                collapsedHeight: 80.0,
                expandedHeight: 80.0,
                floating: true,
                pinned: true,
                flexibleSpace: ClipRRect(
                  // BackdropFilter must be clipped to a bounded region or
                  // the blur will bleed across the whole screen.
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.2),
                      alignment: Alignment.centerLeft,
                      // Top padding accounts for the OS status-bar area on
                      // mobile; left padding aligns with grid content.
                      padding: const EdgeInsets.only(left: 24, top: 28),
                      child: const Text(
                        'PixelVault',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.0,
                          fontSize: 28,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Responsive grid of navigation cards.
              SliverPadding(
                padding: const EdgeInsets.all(24.0),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final double width = constraints.crossAxisExtent;
                    final bool isPhone = width < 600;

                    // Phones get a single column; larger screens compute a
                    // column count from a ~400 px target tile width, but
                    // never fewer than two columns.
                    final int crossAxisCount = isPhone
                        ? 1
                        : math.max(2, (width / 400).floor());

                    // Wider/shorter tiles on phones, more square on desktop
                    // so the grid feels balanced at any breakpoint.
                    final double childAspectRatio = isPhone ? 1.8 : 1.4;

                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 24,
                        crossAxisSpacing: 24,
                        childAspectRatio: childAspectRatio,
                      ),
                      // The 4 cards are static, so a list delegate is clearer
                      // than a builder here. Hero tags must be unique across
                      // the app so destinations can match their entry hero.
                      delegate: SliverChildListDelegate([
                        _GlassMenuCard(
                          title: 'Equipment Guides',
                          subtitle: 'Cameras, lights, audio',
                          imagePath:
                              'assets/images/homepage/learn/equipment_guides.avif',
                          icon: Icons.camera_alt_rounded,
                          onTap: () => context.push('/learn/equip-guides'),
                          accentColor: Colors.blueAccent,
                          heroTag: 'equip_guides_card',
                        ),
                        _GlassMenuCard(
                          title: 'Videography Basics',
                          subtitle: 'Lighting & composition',
                          imagePath:
                              'assets/images/homepage/learn/videography_guides.avif',
                          icon: Icons.movie_filter_rounded,
                          onTap: () =>
                              context.push('/learn/videography-guides'),
                          accentColor: Colors.orangeAccent,
                          heroTag: 'video_guides_card',
                        ),
                        _GlassMenuCard(
                          title: 'Production Scenarios',
                          subtitle: 'Setup guides & tips',
                          imagePath: 'assets/images/homepage/scenarios.avif',
                          icon: Icons.movie_creation_rounded,
                          onTap: () => context.push('/scenarios'),
                          accentColor: Colors.purpleAccent,
                          heroTag: 'scenarios_card',
                        ),
                        _GlassMenuCard(
                          title: 'Inventory List',
                          subtitle: 'Stock & availability',
                          imagePath: 'assets/images/homepage/inventory.avif',
                          icon: Icons.inventory_2_rounded,
                          onTap: () => context.push('/inventory'),
                          accentColor: Colors.greenAccent,
                          heroTag: 'inventory_card',
                        ),
                      ]),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A glassmorphism menu card used on the home page grid.
///
/// Each card stacks (bottom to top):
///   1. An AVIF background image (falls back to a dark grey tile on error).
///   2. A top→bottom black gradient for text legibility.
///   3. An [InkWell] ripple layer that fires [onTap] on press.
///   4. The foreground content — a frosted icon badge in the top-right and
///      a title + subtitle + accent arrow in the bottom-left.
///
/// The whole card is wrapped in a [Hero] so the image can animate into a
/// matching hero on the destination screen.
class _GlassMenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imagePath;
  final IconData icon;
  final VoidCallback onTap;
  final Color accentColor;
  final String heroTag;

  const _GlassMenuCard({
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.icon,
    required this.onTap,
    required this.accentColor,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: heroTag,
      child: Container(
        // Outer shadow gives the tile a soft "lift" off the background
        // without needing a Material elevation (which would clip awkwardly
        // inside the ClipRRect below).
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Layer 1 — Background image (AVIF for small size + alpha).
              Positioned.fill(
                child: AvifImage.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  // Graceful fallback if the asset is missing/corrupt so
                  // the tile still renders instead of throwing.
                  errorBuilder: (context, error, stackTrace) {
                    return Container(color: Colors.grey.shade900);
                  },
                ),
              ),

              // Layer 2 — Darkening gradient so white text is legible on
              // top of any image content.
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.6),
                        Colors.black.withValues(alpha: 0.9),
                      ],
                      stops: const [0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),

              // Layer 3 — Material ripple. Sits above the image/gradient
              // but below the text so the splash shows through properly.
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    splashColor: accentColor.withValues(alpha: 0.2),
                    highlightColor: accentColor.withValues(alpha: 0.1),
                  ),
                ),
              ),

              // Layer 4 — Foreground content.
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Frosted glass icon badge in the top-right corner.
                    Align(
                      alignment: Alignment.topRight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: Icon(icon, color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                    ),

                    // Title + subtitle block in the bottom-left corner.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                            // Explicitly clear the default underline that
                            // can leak through during Hero transitions.
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: accentColor,
                              size: 20,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
