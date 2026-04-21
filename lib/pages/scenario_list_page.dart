// PixelVault — Production scenarios list page.
//
// Stateless grid of production-scenario tiles. Each tile deep-links to a
// [ScenarioDetailPage] via `/scenarios/:id`.

import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter used by BackdropFilter.

import 'package:flutter/material.dart';
import '../widgets/smart_image.dart';
import 'package:go_router/go_router.dart';

import '../models/scenario_model.dart';
import '../services/data_repository.dart';
import '../widgets/admin_auth.dart';
import 'guide_creator_page.dart';

/// Grid page listing every production scenario loaded by
/// [DataRepository].
class ScenarioListPage extends StatefulWidget {
  const ScenarioListPage({super.key});

  @override
  State<ScenarioListPage> createState() => _ScenarioListPageState();
}

class _ScenarioListPageState extends State<ScenarioListPage> {
  Future<void> _handleAdminToggle() async {
    final isAdmin = adminNotifier.value;
    if (isAdmin) {
      final bool? shouldExit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text('Exit Admin Mode?',
              style: TextStyle(color: Colors.white)),
          content: const Text('Are you sure you want to return to user mode?',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Exit',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (shouldExit == true) setAdminPersisted(false);
      return;
    }

    final bool success = await showAdminPasswordDialog(context);
    if (!mounted) return;
    if (success) {
      setAdminPersisted(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin Mode Enabled')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ScenarioGuide> items = DataRepository().getAllScenarios();

    const double maxTileWidth = 420.0;
    final int cols = math.max(
      2,
      (MediaQuery.of(context).size.width / maxTileWidth).floor(),
    );

    return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── 1. Background gradient ──────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF001F54),
                    Color(0xFF0047BB),
                    Color(0xFFFF8200),
                    Color(0xFFE80029),
                  ],
                  stops: [0.0, 0.3, 0.7, 1.0],
                ),
              ),
            ),
            // ── 2. Ambient purple blob ──────────────────────────────
            // Only one blob on this page — the purple tint is the
            // scenario section's accent colour.
            Positioned(
              bottom: -100,
              left: -50,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 120,
                      color: Colors.purple.withValues(alpha: 0.3),
                    ),
                  ],
                ),
              ),
            ),

            // ── 3. Foreground content ──────────────────────────────
            CustomScrollView(
              slivers: [
                // Frosted pinned app bar.
                SliverAppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                  actions: [
                    ValueListenableBuilder<bool>(
                      valueListenable: adminNotifier,
                      builder: (_, isAdmin, _) => isAdmin
                          ? IconButton(
                              icon: const Icon(Icons.add, color: Colors.white),
                              tooltip: 'Create Production Scenario',
                              onPressed: () => showGuideCreator(
                                  context, GuideType.scenario),
                            )
                          : const SizedBox.shrink(),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: adminNotifier,
                      builder: (_, isAdmin, _) => IconButton(
                        icon: Icon(
                          isAdmin
                              ? Icons.admin_panel_settings
                              : Icons.person,
                          color: isAdmin ? Colors.green : Colors.white,
                        ),
                        onPressed: _handleAdminToggle,
                        tooltip: 'Admin Mode',
                      ),
                    ),
                  ],
                  backgroundColor: Colors.transparent,
                  pinned: true,
                  flexibleSpace: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: FlexibleSpaceBar(
                        title: const Text(
                          'Production Scenarios',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        background: Container(
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  ),
                ),

                // Scenario tile grid.
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 3 / 2,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final s = items[index];
                      final cover = s.coverImages.isNotEmpty
                          ? s.coverImages.first
                          : '';
                      return _GlassScenarioCard(
                        title: s.name,
                        imagePath: cover,
                        onTap: () => context.push('/scenarios/${s.id}'),
                      );
                    }, childCount: items.length),
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }
}

/// Glassmorphism tile for a single scenario. Layers a cover image, a
/// bottom-up darkening gradient (for title legibility), the title text,
/// and an [InkWell] tap layer on top.
class _GlassScenarioCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final VoidCallback onTap;

  const _GlassScenarioCard({
    required this.title,
    required this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // Cover image, or a subtle translucent placeholder if the
          // scenario has no cover art.
          Positioned.fill(
            child: imagePath.isNotEmpty
                ? SmartImage.network(DataRepository().imageUrl(imagePath), fit: BoxFit.cover)
                : Container(color: Colors.white.withValues(alpha: 0.1)),
          ),
          // Darkening gradient so the title stays legible over any image.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
          ),
          // Title text, centered along the bottom of the tile.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      blurRadius: 4,
                      color: Colors.black,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Tap ripple layer, sits above everything so feedback shows
          // through on press.
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                highlightColor: Colors.white.withValues(alpha: 0.1),
                splashColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
