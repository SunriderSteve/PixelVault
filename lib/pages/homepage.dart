import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Custom Blue Color from requirements
    const brandBlue = Color(0xFF0047BB);

    return Scaffold(
      backgroundColor: Colors.black, // Dark background base
      body: Stack(
        children: [
          // 1. Vibrant Background Gradient (Blue, Orange, Red)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF001F54), // Dark Blue
                  Color(0xFF0047BB), // NLB  Blue
                  Color(0xFFFF8200), // NLB Orange
                  Color(0xFFE80029), // NLB Red
                ],
                stops: [0.0, 0.3, 0.7, 1.0],
              ),
            ),
          ),

          // 2. Ambient Background Blobs (Soft Glows)
          Positioned(
            top: -150,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                color: brandBlue.withValues(alpha: 0.4),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 150,
                    color: brandBlue.withValues(alpha: 0.4),
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

          // 3. Main Content
          CustomScrollView(
            slivers: [
              // Fixed Glass AppBar (constant size, no expansion/shrinking)
              SliverAppBar(
                backgroundColor: Colors.transparent,
                // Same height for collapsed and expanded ensures no movement
                collapsedHeight: 80.0,
                expandedHeight: 80.0,
                floating: true, // Floats over content but doesn't expand/shrink
                pinned: true, // Stays at top
                flexibleSpace: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.2),
                      alignment: Alignment.centerLeft, // Align title
                      padding: const EdgeInsets.only(
                        left: 24,
                        top: 28,
                      ), // Adjust padding for status bar area
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

              // Grid Content
              SliverPadding(
                padding: const EdgeInsets.all(24.0),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final bool isPhone = width < 600;

                    // Adjusted for responsiveness:
                    // Phones: 1 column
                    // Tablets/Desktop: 2+ columns
                    final int crossAxisCount = isPhone
                        ? 1
                        : math.max(2, (width / 400).floor());

                    // Aspect ratio tuning to match screenshot style (wider/shorter)
                    final double childAspectRatio = isPhone ? 1.8 : 1.4;

                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 24,
                        crossAxisSpacing: 24,
                        childAspectRatio: childAspectRatio,
                      ),
                      delegate: SliverChildListDelegate([
                        _GlassMenuCard(
                          title: 'Equipment Guides',
                          subtitle: 'Cameras, lights, audio',
                          imagePath:
                              'assets/images/homepage/learn/equipment_guides.avif',
                          icon: Icons.camera_alt_rounded,
                          onTap: () => context.push('/learn/equip-guides'),
                          accentColor: Colors.blueAccent,
                          heroTag: 'equip_guides_card', // Unique tag
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
                          heroTag: 'video_guides_card', // Unique tag
                        ),
                        _GlassMenuCard(
                          title: 'Production Scenarios',
                          subtitle: 'Setup guides & tips',
                          imagePath: 'assets/images/homepage/scenarios.avif',
                          icon: Icons.movie_creation_rounded,
                          onTap: () => context.push('/scenarios'),
                          accentColor: Colors.purpleAccent,
                          heroTag: 'scenarios_card', // Unique tag
                        ),
                        _GlassMenuCard(
                          title: 'Inventory List',
                          subtitle: 'Stock & availability',
                          imagePath: 'assets/images/homepage/inventory.avif',
                          icon: Icons.inventory_2_rounded,
                          onTap: () => context.push('/inventory'),
                          accentColor: Colors.greenAccent,
                          heroTag: 'inventory_card', // Unique tag
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
              // 1. Background Image
              Positioned.fill(
                child: AvifImage.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(color: Colors.grey.shade900);
                  },
                ),
              ),

              // 2. Gradient Overlay (Darker for better text contrast)
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

              // 3. Material Ripple Effect
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

              // 4. Content Layout
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Icon Badge
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

                    // Text Info
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
                            decoration: TextDecoration
                                .none, // Prevent underline in Hero transition
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
