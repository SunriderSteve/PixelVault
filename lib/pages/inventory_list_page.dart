// PixelVault — Inventory list page.
//
// Admin + user view of the equipment inventory. Features:
//
//   • Full-text search over equipment names.
//   • Ascending / descending alphabetical sort toggle.
//   • Three-tab filter panel: availability, category, brand.
//   • Responsive grid that scales from 2 columns on small screens to as
//     many as fit at a ~420 px target tile width.
//   • Hidden admin mode (tap the title or the person icon, enter a
//     password) that persists across reloads via localStorage and unlocks
//     in-place editing of quantity + storage for each item.
//
// Inventory edits are routed through [DataRepository.applyInventoryChanges]
// which pushes to the remote gist; the page subscribes to
// [DataRepository.overlayEpoch] so it refreshes whenever the overlay
// changes (e.g. another admin just edited something in another tab).
//
// NOTE: This page is web-only — admin persistence uses `package:web`
// localStorage.

import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter used by BackdropFilter.

import 'package:flutter/material.dart';
import '../widgets/smart_image.dart';
import 'package:go_router/go_router.dart';

import '../models/equipment_model.dart'; // Equipment
import '../services/avif_converter.dart' as avif;
import '../services/data_repository.dart';
import '../widgets/admin_auth.dart';
import '../widgets/pending_changes_fab.dart' show ensureNoPendingChangeFor;
import '../widgets/scroll_to_top_fab.dart';
import 'guide_creator_page.dart' show GuideType;
import 'inventory_create_dialog.dart';
import 'inventory_edit_dialog.dart';

// ─── Constants ────────────────────────────────────────────────────────────


class InventoryListPage extends StatefulWidget {
  const InventoryListPage({super.key});

  @override
  State<InventoryListPage> createState() => _InventoryListPageState();
}

class _InventoryListPageState extends State<InventoryListPage> {
  // ── Search ────────────────────────────────────────────────────────────
  final TextEditingController _search = TextEditingController();

  // ── Sort ──────────────────────────────────────────────────────────────
  bool _sortAsc = true; // A→Z is the default and least surprising order.

  // ── Filters ───────────────────────────────────────────────────────────
  bool _showFilters = false;
  int _activeTab = 0; // 0 = Availability, 1 = Category, 2 = Brand
  int _availability = 0; // 0 = all, 1 = in-stock only, 2 = out-of-stock only
  final Set<String> _selectedCategories = {};
  final Set<String> _selectedBrands = {};

  // ── Admin mode ────────────────────────────────────────────────────────
  // Driven by the global [adminNotifier] so logging in here unlocks
  // admin features on every other page too.
  bool _isAdmin = adminNotifier.value;

  // ── Data ──────────────────────────────────────────────────────────────
  late final List<Equipment> _all; // Source list straight from the repo.
  late List<Equipment> _filtered; // Post-search/filter/sort view.
  // Category / brand option lists for the filter panel. Recomputed on
  // every overlay tick so newly-added equipment surfaces fresh chips
  // and removed equipment drops them.
  late List<String> _allCategories;
  late List<String> _allBrands;

  // ── Scroll ────────────────────────────────────────────────────────────
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final repo = DataRepository();
    _all = List.of(repo.getAllEquipment());

    _allCategories = _all.map((e) => e.category).toSet().toList()..sort();
    _allBrands = _all.map((e) => e.brand).toSet().toList()..sort();

    // Seed the filtered list in A→Z order to match `_sortAsc = true`.
    _filtered = List.of(_all)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    _search.addListener(_applyFilters);
    repo.overlayEpoch.addListener(_onOverlayChanged);
    adminNotifier.addListener(_onAdminChanged);
  }

  @override
  void dispose() {
    adminNotifier.removeListener(_onAdminChanged);
    DataRepository().overlayEpoch.removeListener(_onOverlayChanged);
    _search.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onAdminChanged() {
    if (!mounted) return;
    setState(() => _isAdmin = adminNotifier.value);
  }

  /// Called when [DataRepository] signals that the overlay (edits) changed
  /// — e.g. another tab just pushed a quantity update. We refetch the full
  /// equipment list so our view reflects the new truth, rebuild the
  /// category / brand option lists, then re-apply the current
  /// search/filter/sort.
  void _onOverlayChanged() {
    if (!mounted) return;
    final fresh = DataRepository().getAllEquipment();
    _all
      ..clear()
      ..addAll(fresh);

    // Rebuild the filter universes so newly-added equipment shows up as
    // selectable chips and removed values drop off.
    _allCategories = _all.map((e) => e.category).toSet().toList()..sort();
    _allBrands = _all.map((e) => e.brand).toSet().toList()..sort();

    // Drop any active selections that no longer exist — otherwise the
    // chip disappears but the filter silently keeps excluding everything.
    _selectedCategories.retainAll(_allCategories);
    _selectedBrands.retainAll(_allBrands);

    _applyFilters(); // already wraps its work in setState
  }

  /// Recompute [_filtered] from the current search + filter + sort state.
  /// Always runs inside setState so the grid rebuilds with the new view.
  void _applyFilters() {
    final String query = _search.text.toLowerCase();

    setState(() {
      _filtered =
          _all.where((e) {
            // 1. Search match (case-insensitive contains on name).
            final bool matchesSearch = e.name.toLowerCase().contains(query);

            // 2. Availability filter.
            final int qty = e.quantity ?? 0;
            bool matchesAvail = true;
            if (_availability == 1) matchesAvail = qty > 0;
            if (_availability == 2) matchesAvail = qty <= 0;

            // 3. Category filter — empty selection means "any".
            final bool matchesCat =
                _selectedCategories.isEmpty ||
                _selectedCategories.contains(e.category);

            // 4. Brand filter — empty selection means "any".
            final bool matchesBrand =
                _selectedBrands.isEmpty || _selectedBrands.contains(e.brand);

            return matchesSearch && matchesAvail && matchesCat && matchesBrand;
          }).toList()
            // 5. Final alphabetical sort, direction based on _sortAsc.
            ..sort((a, b) {
              final int cmp = a.name.toLowerCase().compareTo(
                b.name.toLowerCase(),
              );
              return _sortAsc ? cmp : -cmp;
            });
    });
  }

  // ── Admin toggle ──────────────────────────────────────────────────────

  /// Handles the person / admin icon (and title tap).
  ///
  /// If already admin → prompts to exit. Otherwise shows the password
  /// dialog and, on success, persists the flag to localStorage.
  Future<void> _handleAdminToggle() async {
    if (_isAdmin) {
      // Already admin → confirm exit to user mode.
      final bool? shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text(
            'Exit Admin Mode?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Are you sure you want to return to user mode?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Exit',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (shouldExit == true) {
        setAdminPersisted(false);
      }
      return;
    }

    // Not admin yet — ask for the password.
    final bool? success = await showDialog<bool>(
      context: context,
      builder: (context) => const AdminPasswordDialog(),
    );
    if (!mounted) return;
    if (success == true) {
      setAdminPersisted(true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Admin Mode Enabled')));
    }
  }

  /// Persists an inventory edit through the repository, then shows a
  /// snackbar reporting success or failure.
  Future<void> _onSavePatch(
    String id, {
    int? newQty,
    String? newStorage,
    String? newBrand,
    String? newCategory,
  }) async {
    try {
      await DataRepository().applyInventoryChanges(
        id,
        quantity: newQty,
        storage: newStorage,
        brand: newBrand,
        category: newCategory,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Changes saved!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  /// Open the edit dialog for [item] and persist the result.
  ///
  /// Three possible outcomes:
  ///   • `removed: true`   — delete the equipment entirely.
  ///   • `newImageBytes`   — replace the cover image (AVIF-converted +
  ///                         uploaded, YAML patched in a single commit).
  ///   • inventory patch   — quantity / storage diff only.
  Future<void> _editItem(Equipment item) async {
    // Block the edit dialog if a change for this item is already
    // queued — layering a second edit (or worse, a delete after a
    // create) on top is either confusing or contradictory.
    if (!ensureNoPendingChangeFor(context, item.id)) return;

    final String initialCover =
        item.coverImages.isNotEmpty ? item.coverImages.first : '';
    final InventoryEditResult? res = await showInventoryEditDialog(
      context,
      equipmentName: item.name,
      initialQuantity: item.quantity ?? 0,
      initialStorage: item.storage ?? '',
      initialBrand: item.brand,
      initialCategory: item.category,
      initialCoverImagePath: initialCover,
    );
    if (!mounted || res == null) return;

    // ── Removal path — deletes YAML entry + every image atomically.
    if (res.removed) {
      try {
        await DataRepository().deleteEquipment(item.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${item.name}" removed.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
      return;
    }

    if (!res.changed) return;

    // ── Image replacement — AVIF convert, upload, rewrite YAML.
    if (res.newImageBytes != null) {
      try {
        final converted = await avif.convertToAvif(res.newImageBytes!);
        // Stamp the filename with an epoch so the URL changes on every
        // replacement. Without this the path (e.g. {id}_cover_1.avif)
        // stays identical, and raw.githubusercontent.com + browser
        // caches keep serving the old bytes even after YAML updates.
        final int stamp = DateTime.now().millisecondsSinceEpoch;
        final String basePath = DataRepository.coverImagePath(
          GuideType.equipment,
          item.id,
          0,
          converted.ext,
        );
        final String repoPath = basePath.replaceFirst(
          RegExp(r'\.([^.]+)$'),
          '_$stamp.${converted.ext}',
        );
        await DataRepository().replaceEquipmentCoverImage(
          item.id,
          bytes: converted.bytes,
          repoPath: repoPath,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to replace image: $e')),
        );
        return;
      }
    }

    final int? newQty = (res.quantity != item.quantity) ? res.quantity : null;
    final String? newStorage =
        (res.storage != item.storage) ? res.storage : null;
    final String? newBrand =
        (res.brand != item.brand) ? res.brand : null;
    final String? newCategory =
        (res.category != item.category) ? res.category : null;

    if (newQty != null ||
        newStorage != null ||
        newBrand != null ||
        newCategory != null) {
      await _onSavePatch(
        item.id,
        newQty: newQty,
        newStorage: newStorage,
        newBrand: newBrand,
        newCategory: newCategory,
      );
    } else if (res.newImageBytes != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cover image updated.')),
      );
    }
  }

  /// Open the read-only equipment info popup. Available to admins and
  /// regular users — admins still see (and can tap) the edit button on
  /// the card, but a tap anywhere else on the card opens this view.
  void _showInfoPopup(Equipment item) {
    showDialog(
      context: context,
      builder: (_) => _InventoryInfoPopup(equipment: item),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0047BB);

    // Responsive column count. Floor-division by maxTileWidth scales up on
    // wider screens but never drops below 2 columns.
    const double maxTileWidth = 420;
    final double width = MediaQuery.of(context).size.width;
    final int cols = math.max(2, (width / maxTileWidth).floor());

    // Badge count on the filter icon: sum of all active filters. A set
    // selection counts by its size, and the availability dropdown
    // contributes 1 when it's anything other than "All".
    final int totalFilters =
        _selectedCategories.length +
        _selectedBrands.length +
        (_availability != 0 ? 1 : 0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Background gradient (matches home page palette) ──────────
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

          // ── Ambient glow blobs ───────────────────────────────────────
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

          // ── Foreground content ───────────────────────────────────────
          CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              // Frosted app bar. The title doubles as a hidden admin
              // toggle — tapping it triggers the same flow as the person
              // icon on the right.
              SliverAppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                backgroundColor: Colors.transparent,
                pinned: true,
                flexibleSpace: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: FlexibleSpaceBar(
                      title: GestureDetector(
                        onTap: _handleAdminToggle,
                        child: const Text(
                          'Inventory List',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      background: Container(
                        color: Colors.black.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                ),
                actions: [
                  if (_isAdmin)
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white),
                      onPressed: () => showInventoryCreator(context),
                      tooltip: 'Add Equipment',
                    ),
                  // Visible admin toggle — green while enabled.
                  IconButton(
                    icon: Icon(
                      _isAdmin ? Icons.admin_panel_settings : Icons.person,
                      color: _isAdmin ? Colors.green : Colors.white,
                    ),
                    onPressed: _handleAdminToggle,
                    tooltip: 'Admin Mode',
                  ),
                ],
              ),

              // ── Search / sort / filter bar ──────────────────────────
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
                            // Search text field. Changes route through the
                            // listener registered in initState, so typing
                            // updates _filtered automatically.
                            Expanded(
                              child: TextField(
                                controller: _search,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Search Inventory',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: Colors.white,
                                  ),
                                  suffixIcon: _search.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.clear,
                                            color: Colors.white,
                                          ),
                                          onPressed: _search.clear,
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
                              onPressed: () {
                                _sortAsc = !_sortAsc;
                                _applyFilters(); // already calls setState
                              },
                              tooltip: _sortAsc ? 'Sort Z-A' : 'Sort A-Z',
                            ),
                            // Filter panel toggle with a live count badge.
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

              // ── Filter panel (conditionally rendered) ───────────────
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
                              // Tab picker — determines which chip group
                              // renders below.
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _GlassTabButton(
                                      label: 'Availability',
                                      selected: _activeTab == 0,
                                      onTap: () =>
                                          setState(() => _activeTab = 0),
                                    ),
                                    const SizedBox(width: 12),
                                    _GlassTabButton(
                                      label: 'Category',
                                      selected: _activeTab == 1,
                                      onTap: () =>
                                          setState(() => _activeTab = 1),
                                    ),
                                    const SizedBox(width: 12),
                                    _GlassTabButton(
                                      label: 'Brand',
                                      selected: _activeTab == 2,
                                      onTap: () =>
                                          setState(() => _activeTab = 2),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Chip group body for the active tab.
                              if (_activeTab == 0)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _GlassFilterChip(
                                      label: 'All',
                                      selected: _availability == 0,
                                      onSelected: (_) {
                                        _availability = 0;
                                        _applyFilters();
                                      },
                                    ),
                                    _GlassFilterChip(
                                      label: 'Available Only',
                                      selected: _availability == 1,
                                      onSelected: (_) {
                                        _availability = 1;
                                        _applyFilters();
                                      },
                                    ),
                                    _GlassFilterChip(
                                      label: 'Unavailable Only',
                                      selected: _availability == 2,
                                      onSelected: (_) {
                                        _availability = 2;
                                        _applyFilters();
                                      },
                                    ),
                                  ],
                                )
                              else if (_activeTab == 1)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _allCategories.map((c) {
                                    final bool isSelected = _selectedCategories
                                        .contains(c);
                                    return _GlassFilterChip(
                                      label: c,
                                      selected: isSelected,
                                      onSelected: (selected) {
                                        if (selected) {
                                          _selectedCategories.add(c);
                                        } else {
                                          _selectedCategories.remove(c);
                                        }
                                        _applyFilters();
                                      },
                                    );
                                  }).toList(),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _allBrands.map((brand) {
                                    final bool isSelected = _selectedBrands
                                        .contains(brand);
                                    return _GlassFilterChip(
                                      label: brand,
                                      selected: isSelected,
                                      onSelected: (selected) {
                                        if (selected) {
                                          _selectedBrands.add(brand);
                                        } else {
                                          _selectedBrands.remove(brand);
                                        }
                                        _applyFilters();
                                      },
                                    );
                                  }).toList(),
                                ),

                              const Divider(color: Colors.white24, height: 32),

                              // Clear all + Done action row.
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      _selectedCategories.clear();
                                      _selectedBrands.clear();
                                      _availability = 0;
                                      _applyFilters();
                                    },
                                    child: const Text(
                                      'Clear All',
                                      style: TextStyle(color: Colors.white70),
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

              // ── Inventory grid ──────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final Equipment item = _filtered[index];
                    return _GlassInventoryCard(
                      item: item,
                      isAdmin: _isAdmin,
                      onEditTap: () => _editItem(item),
                      onCardTap: () => _showInfoPopup(item),
                    );
                  }, childCount: _filtered.length),
                ),
              ),
            ],
          ),

          // Back-to-top button — appears once the user has scrolled.
          // The global pending-changes FAB shifts up to stay visible
          // above it (handled in main.dart).
          ScrollToTopFab(controller: _scrollCtrl),
        ],
      ),
    );
  }
}

/// Pill-shaped tab used inside the filter panel. Highlights when
/// [selected] is true and calls [onTap] when pressed.
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

/// Thin wrapper around [FilterChip] that styles it to match the rest of
/// the glassmorphism UI. Passes the selected-bool straight through to
/// [onSelected].
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

/// A single equipment tile in the inventory grid.
///
/// Shows the item image (or a blank placeholder), the name, a stock /
/// out-of-stock badge, and — for admins only — a storage location badge
/// plus an edit button in the top-right corner.
class _GlassInventoryCard extends StatelessWidget {
  final Equipment item;
  final bool isAdmin;
  final VoidCallback? onEditTap;
  final VoidCallback? onCardTap;

  const _GlassInventoryCard({
    required this.item,
    required this.isAdmin,
    this.onEditTap,
    this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final int qty = item.quantity ?? 0;
    final bool isAvailable = qty > 0;
    final String imagePath = item.coverImages.isNotEmpty
        ? item.coverImages.first
        : '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // 1. Background image, or a subtle white placeholder if the
          //    item has no cover image.
          Positioned.fill(
            child: imagePath.isNotEmpty
                ? SmartImage.network(DataRepository().imageUrl(imagePath), fit: BoxFit.cover)
                : Container(color: Colors.white.withValues(alpha: 0.1)),
          ),

          // 2. Bottom-up darkening gradient so labels stay legible over
          //    any image content.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.9),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
          ),

          // 3. Bottom-left content: name, stock badge, (admin) storage.
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, // Allow column to shrink.
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                const SizedBox(height: 4),

                // Stock badge — green with a count when in-stock, red
                // "Out of Stock" otherwise. Always visible to all users.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? Colors.green.withValues(alpha: 0.5)
                        : Colors.red.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isAvailable
                          ? Colors.green.withValues(alpha: 0.5)
                          : Colors.red.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    isAvailable ? 'Stock: $qty' : 'Out of Stock',
                    style: TextStyle(
                      color: isAvailable
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Storage location badge — only visible in admin mode so
                // regular users don't see internal storage details.
                if (isAdmin && item.storage != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      'Storage: ${item.storage}',
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 4. Tap ripple layer — opens the read-only info popup.
          //    Positioned BEFORE the admin edit button so the
          //    IconButton remains on top in the hit-test order and
          //    keeps its own tap target unobstructed.
          if (onCardTap != null)
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onCardTap,
                  highlightColor: Colors.white.withValues(alpha: 0.1),
                  splashColor: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),

          // 5. Admin-only edit button, pinned to the top-right corner.
          if (isAdmin)
            Positioned(
              top: 8,
              right: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    child: IconButton(
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: onEditTap,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Read-only equipment info popup. Mirrors the production-shoot
/// equipment popup but without the bring-quantity editor and remove
/// action — it's the same dialog non-admins and admins both see when
/// tapping an inventory card. Tapping the cover image opens a
/// full-screen viewer.
class _InventoryInfoPopup extends StatelessWidget {
  final Equipment equipment;

  const _InventoryInfoPopup({required this.equipment});

  void _showFullImage(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SmartImage.network(
              DataRepository().imageUrl(imagePath),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Container(
                color: Colors.grey.shade800,
                child: const Icon(
                  Icons.image_not_supported,
                  color: Colors.white38,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String imagePath = equipment.coverImages.isNotEmpty
        ? equipment.coverImages.first
        : '';
    final int qty = equipment.quantity ?? 0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            decoration: BoxDecoration(
              color: Colors.grey.shade900.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),

                if (imagePath.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _showFullImage(context, imagePath),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: SmartImage.network(
                            DataRepository().imageUrl(imagePath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.grey.shade800,
                              child: const Icon(
                                Icons.image_not_supported,
                                color: Colors.white38,
                                size: 48,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Press to view full image',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ] else
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.white38,
                        size: 48,
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        equipment.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(label: 'Category', value: equipment.category),
                      _InfoRow(label: 'Brand', value: equipment.brand),
                      _InfoRow(
                        label: 'Stock',
                        value: qty > 0 ? '$qty' : 'Out of Stock',
                      ),
                      if (equipment.storage != null &&
                          equipment.storage!.isNotEmpty)
                        _InfoRow(
                          label: 'Storage',
                          value: equipment.storage!,
                        ),
                      if (equipment.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          equipment.description,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
