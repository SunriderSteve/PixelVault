// PixelVault — Videography guides list page.
//
// Stateful grid of videography guide tiles with a top search bar. Each
// tile deep-links to [VideographyDetailPage] via
// `/learn/videography-guides/:id`. Search is a simple case-insensitive
// `contains` match on the guide name, applied reactively via a
// [TextEditingController] listener registered in initState.

import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter used by BackdropFilter.

import 'package:flutter/material.dart';
import '../widgets/smart_image.dart';
import 'package:go_router/go_router.dart';

import '../models/videography_model.dart';
import '../services/data_repository.dart';
import '../widgets/admin_auth.dart';
import 'guide_creator_page.dart';

class LearnVideographyListPage extends StatefulWidget {
  const LearnVideographyListPage({super.key});
  @override
  State<LearnVideographyListPage> createState() =>
      _LearnVideographyListPageState();
}

class _LearnVideographyListPageState extends State<LearnVideographyListPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  /// Alphabetical sort direction. A→Z by default.
  bool _sortAsc = true;

  // Source list + search-filtered view. `_all` is immutable for the
  // life of this page; `_filtered` is recomputed on every search change.
  late final List<VideographyGuide> _all;
  late List<VideographyGuide> _filtered;

  @override
  void initState() {
    super.initState();
    _all = DataRepository().getAllVideographyGuides();
    _filtered = List.of(_all)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _searchCtrl.addListener(_onSearch);
  }

  /// Case-insensitive `contains` filter on the guide name plus the
  /// current alphabetical sort direction.
  void _onSearch() {
    final String q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = (q.isEmpty
          ? List.of(_all)
          : _all.where((g) => g.name.toLowerCase().contains(q)).toList())
        ..sort((a, b) {
          final int cmp =
              a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return _sortAsc ? cmp : -cmp;
        });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
    const brandBlue = Color(0xFF0047BB);

    // Responsive column count — one column per ~420 px, min 2.
    const double maxTileWidth = 420;
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
            // ── 2. Ambient blob glow (top-right) ────────────────────
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  color: brandBlue.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 120,
                      color: brandBlue.withValues(alpha: 0.4),
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
                              tooltip: 'Create Videography Guide',
                              onPressed: () => showGuideCreator(
                                  context, GuideType.videography),
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
                          'Videography Basics',
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

                // Glassmorphism search bar.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Search Guides',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: Colors.white,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _sortAsc
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  color: Colors.white,
                                ),
                                tooltip: _sortAsc ? 'Sort Z-A' : 'Sort A-Z',
                                onPressed: () {
                                  _sortAsc = !_sortAsc;
                                  _onSearch();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Guide tile grid.
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
                      final guide = _filtered[index];
                      final img = guide.coverImages.isNotEmpty
                          ? guide.coverImages.first
                          : '';
                      return _GlassGuideCard(
                        title: guide.name,
                        imagePath: img,
                        onTap: () => context.push(
                          '/learn/videography-guides/${guide.id}',
                        ),
                      );
                    }, childCount: _filtered.length),
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }
}

/// Glassmorphism tile for a single videography guide. Structurally
/// identical to the scenario / equipment cards on other list pages —
/// image, gradient, centered title, tap layer — but kept local because
/// the list pages don't currently share a common card widget.
class _GlassGuideCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final VoidCallback onTap;

  const _GlassGuideCard({
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
          // Cover image or a translucent fallback when empty.
          Positioned.fill(
            child: imagePath.isNotEmpty
                ? SmartImage.network(DataRepository().imageUrl(imagePath), fit: BoxFit.cover)
                : Container(color: Colors.white.withValues(alpha: 0.1)),
          ),
          // Darkening gradient for title legibility.
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
          // Centered bottom title.
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
          // Tap ripple layer.
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
