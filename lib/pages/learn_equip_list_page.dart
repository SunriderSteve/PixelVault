// PixelVault — Equipment guides list page.
//
// Stateful grid of equipment guide tiles with a combined search +
// category/brand filter panel at the top. Each tile deep-links to an
// [EquipDetailPage] via `/learn/equip-guides/:id`.
//
// Search and filtering both funnel through [_updateFilters], which
// recomputes [_filtered] and calls setState in one pass. Guides without
// any content (no description AND no sections) are hidden from the list
// so empty YAMLs don't show up as dead tiles.

import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter used by BackdropFilter.

import 'package:flutter/material.dart';
import '../widgets/smart_image.dart';
import 'package:go_router/go_router.dart';

import '../models/equipment_model.dart';
import '../services/data_repository.dart';
import '../widgets/admin_auth.dart';
import 'guide_creator_page.dart';

class LearnEquipListPage extends StatefulWidget {
  const LearnEquipListPage({super.key});

  @override
  State<LearnEquipListPage> createState() => _LearnEquipListPageState();
}

class _LearnEquipListPageState extends State<LearnEquipListPage> {
  // ── Search / filter state ───────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();

  /// Whether the expandable filter panel is currently visible.
  bool _showFilters = false;

  /// Tab index inside the filter panel: 0 = Category, 1 = Brand.
  int _activeTab = 0;

  /// Alphabetical sort direction. A→Z by default.
  bool _sortAsc = true;

  final Set<String> _selectedCategories = {};
  final Set<String> _selectedBrands = {};

  // ── Source data ─────────────────────────────────────────────────────
  // `_allItems` is refetched from the repo whenever [overlayEpoch]
  // ticks, so a guide created / edited / removed in another session
  // appears without a reload. The category / brand option lists are
  // rebuilt at the same time.
  late List<Equipment> _allItems;
  late List<Equipment> _filteredItems;
  late List<String> _allCategories;
  late List<String> _allBrands;

  @override
  void initState() {
    super.initState();
    _loadFromRepo();
    _searchController.addListener(_updateFilters);
    DataRepository().overlayEpoch.addListener(_onOverlayChanged);
  }

  /// (Re)populate the source list + filter option lists from the repo.
  void _loadFromRepo() {
    _allItems = DataRepository().getAllEquipment();

    // Seed `_filteredItems` with only guides that actually have content —
    // `_updateFilters` applies the same rule, but we populate up front so
    // the first paint doesn't flash all-items before the filter runs.
    _filteredItems = _allItems.where(_hasContent).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Alphabetical so the chip order is stable across sessions
    // regardless of YAML load order.
    _allCategories = _allItems.map((e) => e.category).toSet().toList()..sort();
    _allBrands = _allItems.map((e) => e.brand).toSet().toList()..sort();
  }

  /// Repository signalled an equipment change — refetch and re-apply
  /// the current search/filter/sort so the grid reflects it immediately.
  void _onOverlayChanged() {
    if (!mounted) return;
    _loadFromRepo();
    _updateFilters();
  }

  @override
  void dispose() {
    DataRepository().overlayEpoch.removeListener(_onOverlayChanged);
    _searchController.dispose();
    super.dispose();
  }

  // ── Filter logic ────────────────────────────────────────────────────

  /// Items marked with no_guide, or without a description and sections,
  /// are hidden from the list.
  bool _hasContent(Equipment item) =>
      !item.noGuide &&
      (item.description.trim().isNotEmpty || item.sections.isNotEmpty);

  /// Recomputes [_filteredItems] from the current search text plus the
  /// selected category/brand filters, and triggers a rebuild. Every
  /// mutator calls this single method so the filtering pipeline is
  /// defined in exactly one place.
  void _updateFilters() {
    final String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _allItems.where((item) {
        final bool matchesQuery = item.name.toLowerCase().contains(query);
        final bool matchesCategory =
            _selectedCategories.isEmpty ||
            _selectedCategories.contains(item.category);
        final bool matchesBrand =
            _selectedBrands.isEmpty || _selectedBrands.contains(item.brand);
        return matchesQuery &&
            matchesCategory &&
            matchesBrand &&
            _hasContent(item);
      }).toList()
        ..sort((a, b) {
          final int cmp =
              a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return _sortAsc ? cmp : -cmp;
        });
    });
  }

  /// Clear both filter sets and refresh the list. `_updateFilters`
  /// already wraps the list rebuild in setState, so no outer setState
  /// is needed here.
  void _clearFilters() {
    _selectedCategories.clear();
    _selectedBrands.clear();
    _updateFilters();
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0047BB);

    // Responsive column count — one column per ~420 px, min 2.
    const double maxTileWidth = 420;
    final int cols = math.max(
      2,
      (MediaQuery.of(context).size.width / maxTileWidth).floor(),
    );
    final int totalFilters =
        _selectedCategories.length + _selectedBrands.length;

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

            // ── 2. Ambient blob glows ───────────────────────────────
            Positioned(
              top: -150,
              left: -100,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  color: brandBlue.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 150,
                      color: brandBlue.withValues(alpha: 0.3),
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
                  color: Colors.orange.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 150,
                      color: Colors.orange.withValues(alpha: 0.2),
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
                              tooltip: 'Create Equipment Guide',
                              onPressed: () => showGuideCreator(
                                  context, GuideType.equipment),
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
                          'Equipment Guides',
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

                // Search bar + filter toggle (glassmorphism).
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Search Equipment',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: Colors.white,
                                    ),
                                    // Only show the clear button when the
                                    // field has text — otherwise an empty
                                    // icon slot eats space on small screens.
                                    suffixIcon: _searchController.text.isEmpty
                                        ? null
                                        : IconButton(
                                            icon: const Icon(
                                              Icons.clear,
                                              color: Colors.white,
                                            ),
                                            onPressed: () {
                                              _searchController.clear();
                                              _updateFilters();
                                            },
                                          ),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              // Sort direction toggle.
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
                                  _updateFilters();
                                },
                              ),
                              // Filter panel toggle. Shows a small badge
                              // with the number of active filter chips.
                              GestureDetector(
                                onTap: () => setState(
                                  () => _showFilters = !_showFilters,
                                ),
                                child: Stack(
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Icon(
                                        Icons.filter_alt,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    if (totalFilters > 0)
                                      Positioned(
                                        right: 4,
                                        top: 4,
                                        child: CircleAvatar(
                                          radius: 8,
                                          backgroundColor: Colors.red,
                                          child: Text(
                                            '$totalFilters',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Expandable filter panel ──
                // Rendered conditionally — only appears while
                // [_showFilters] is true. Hosts the Category/Brand tab
                // switcher and the chip grid for the active tab.
                if (_showFilters)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.6),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Tab switcher: Category / Brand.
                                Row(
                                  children: [
                                    _GlassTabButton(
                                      label: 'Category',
                                      selected: _activeTab == 0,
                                      onTap: () =>
                                          setState(() => _activeTab = 0),
                                    ),
                                    const SizedBox(width: 16),
                                    _GlassTabButton(
                                      label: 'Brand',
                                      selected: _activeTab == 1,
                                      onTap: () =>
                                          setState(() => _activeTab = 1),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Chip list for the currently active tab.
                                // Tapping a chip mutates the selection set
                                // and calls _updateFilters (which already
                                // wraps in setState, so no outer setState
                                // is needed here).
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _activeTab == 0
                                      ? _allCategories.map((c) {
                                          final bool isSelected =
                                              _selectedCategories.contains(c);
                                          return _GlassFilterChip(
                                            label: c,
                                            selected: isSelected,
                                            onSelected: (sel) {
                                              if (sel) {
                                                _selectedCategories.add(c);
                                              } else {
                                                _selectedCategories.remove(c);
                                              }
                                              _updateFilters();
                                            },
                                          );
                                        }).toList()
                                      : _allBrands.map((b) {
                                          final bool isSelected =
                                              _selectedBrands.contains(b);
                                          return _GlassFilterChip(
                                            label: b,
                                            selected: isSelected,
                                            onSelected: (sel) {
                                              if (sel) {
                                                _selectedBrands.add(b);
                                              } else {
                                                _selectedBrands.remove(b);
                                              }
                                              _updateFilters();
                                            },
                                          );
                                        }).toList(),
                                ),
                                const Divider(
                                  color: Colors.white24,
                                  height: 32,
                                ),

                                // Clear-all + Done row.
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: _clearFilters,
                                      child: const Text(
                                        'Clear All',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    ElevatedButton(
                                      onPressed: () =>
                                          setState(() => _showFilters = false),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: brandBlue,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Done'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Equipment tile grid.
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
                      final eq = _filteredItems[index];
                      final String imagePath = eq.coverImages.isNotEmpty
                          ? eq.coverImages.first
                          : '';
                      return _GlassEquipmentCard(
                        title: eq.name,
                        imagePath: imagePath,
                        onTap: () =>
                            context.push('/learn/equip-guides/${eq.id}'),
                      );
                    }, childCount: _filteredItems.length),
                  ),
                ),
              ],
            ),
          ],
        ),
    );
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
}

/// Pill-shaped tab toggle used at the top of the filter panel. Not a
/// real [TabBar] because the filter panel only has two options and the
/// visual style needs to match the page's glass theme.
class _GlassTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GlassTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            // Slightly brighter border when selected so the active tab
            // reads at a glance even in the darkened filter panel.
            color: selected ? Colors.white : Colors.white54,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Thin wrapper around the material [FilterChip] with PixelVault's
/// glass/brand colour palette baked in. Kept local because no other
/// page in the app currently uses filter chips.
class _GlassFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _GlassFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      // Darker background for unselected so text stays legible against
      // the blurred gradient behind the filter panel.
      backgroundColor: Colors.black.withValues(alpha: 0.3),
      selectedColor: const Color(0xFF0047BB),
      checkmarkColor: Colors.white,
      labelStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? Colors.transparent : Colors.white38),
      ),
    );
  }
}

/// Glassmorphism tile for a single equipment guide. Structurally
/// identical to the scenario / videography cards on other list pages,
/// kept local because list pages don't currently share a common card
/// widget.
class _GlassEquipmentCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final VoidCallback onTap;

  const _GlassEquipmentCard({
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
