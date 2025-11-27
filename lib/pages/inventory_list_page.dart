import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/equipment_model.dart'; // Equipment
import 'inventory_edit_dialog.dart';

/// inventory list with search, tri-state availability, category/brand filters, A↔Z sort
/// admin mode toggles cabinet visibility and shows edit affordance
class InventoryListPage extends StatefulWidget {
  const InventoryListPage({super.key});

  @override
  State<InventoryListPage> createState() => _InventoryListPageState();
}

class _InventoryListPageState extends State<InventoryListPage> {
  // search
  final TextEditingController _search = TextEditingController();

  // sort
  bool _sortAsc = true; // A→Z by default

  // filters
  bool _showFilters = false;
  int _activeTab = 0; // 0 Availability, 1 Category, 2 Brand
  int _availability = 0; // 0 all, 1 available only, 2 unavailable only
  final Set<String> _selectedCategories = {};
  final Set<String> _selectedBrands = {};

  // admin mode
  bool _isAdmin = false;
  int _tapCount = 0;
  DateTime _lastTap = DateTime.now();

  // data
  late final List<Equipment> _all; // All items from repo
  late List<Equipment> _filtered; // Items to display
  late final List<String> _allCategories;
  late final List<String> _allBrands;

  @override
  void initState() {
    super.initState();
    final repo = DataRepository();
    // Initialize _all as a growable list so we can modify it later
    _all = List.from(repo.getAllEquipment());
    _filtered = List.from(_all);

    _allCategories = _all.map((e) => e.category).toSet().toList()..sort();
    _allBrands = _all.map((e) => e.brand).toSet().toList()..sort();

    _search.addListener(_applyFilters);

    // listen to overlay changes from repository (polling)
    repo.overlayEpoch.addListener(_onOverlayChanged);
  }

  @override
  void dispose() {
    DataRepository().overlayEpoch.removeListener(_onOverlayChanged);
    _search.dispose();
    super.dispose();
  }

  // If repo says data changed (poll or manual write), re-read and re-filter
  void _onOverlayChanged() {
    final fresh = DataRepository().getAllEquipment();
    setState(() {
      _all.clear();
      _all.addAll(fresh);
      _applyFilters();
    });
  }

  void _applyFilters() {
    final query = _search.text.toLowerCase();

    setState(() {
      _filtered = _all.where((e) {
        // 1. Search
        final matchesSearch = e.name.toLowerCase().contains(query);

        // 2. Availability
        final qty = e.quantity ?? 0;
        bool matchesAvail = true;
        if (_availability == 1) matchesAvail = qty > 0; // Available only
        if (_availability == 2) matchesAvail = qty <= 0; // Unavailable only

        // 3. Category
        final matchesCat =
            _selectedCategories.isEmpty ||
            _selectedCategories.contains(e.category);

        // 4. Brand
        final matchesBrand =
            _selectedBrands.isEmpty || _selectedBrands.contains(e.brand);

        return matchesSearch && matchesAvail && matchesCat && matchesBrand;
      }).toList();

      // 5. Sort
      _filtered.sort((a, b) {
        final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return _sortAsc ? cmp : -cmp;
      });
    });
  }

  void _toggleAdmin() {
    final now = DateTime.now();
    if (now.difference(_lastTap) < const Duration(milliseconds: 500)) {
      _tapCount++;
    } else {
      _tapCount = 1;
    }
    _lastTap = now;

    if (_tapCount >= 5) {
      setState(() {
        _isAdmin = !_isAdmin;
        _tapCount = 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAdmin ? 'Admin Mode Enabled' : 'Admin Mode Disabled',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      });
    }
  }

  Future<void> _onSavePatch(String id, int? newQty, String? newCab) async {
    // Call repo to write to gist
    try {
      await DataRepository().applyInventoryChanges(
        id,
        quantity: newQty,
        cabinet: newCab,
      );
      // The repo will notify listeners (including this page) via overlayEpoch
      // So UI updates automatically.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Changes saved to Gist!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Brand Blue
    const brandBlue = Color(0xFF0047BB);

    // Responsive Grid
    const double maxTileWidth = 420;
    final width = MediaQuery.of(context).size.width;
    final cols = math.max(1, (width / maxTileWidth).floor());

    final totalFilters =
        _selectedCategories.length +
        _selectedBrands.length +
        (_availability != 0 ? 1 : 0);

    // Hero added here
    return Hero(
      tag: 'inventory_card',
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 1. Vibrant Background Gradient
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF001F54), // Dark Blue
                    Color(0xFF0047BB), // NLB Blue
                    Color(0xFFFF8200), // NLB Orange
                    Color(0xFFE80029), // NLB Red
                  ],
                  stops: [0.0, 0.3, 0.7, 1.0],
                ),
              ),
            ),

            // 2. Background Blobs
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

            // 3. Content
            CustomScrollView(
              slivers: [
                // Glass App Bar
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
                          onTap: _toggleAdmin,
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
                    IconButton(
                      icon: Icon(
                        _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _sortAsc = !_sortAsc;
                          _applyFilters();
                        });
                      },
                      tooltip: _sortAsc ? 'Sort Z-A' : 'Sort A-Z',
                    ),
                  ],
                ),

                // Search & Filter Bar
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
                                  controller: _search,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Search Inventory',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
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
                                            onPressed: () {
                                              _search.clear();
                                            },
                                          ),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
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

                // Filter Panel
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
                                // Filter Content
                                if (_activeTab == 0)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _GlassFilterChip(
                                        label: 'All',
                                        selected: _availability == 0,
                                        onSelected: (b) => setState(() {
                                          _availability = 0;
                                          _applyFilters();
                                        }),
                                      ),
                                      _GlassFilterChip(
                                        label: 'Available Only',
                                        selected: _availability == 1,
                                        onSelected: (b) => setState(() {
                                          _availability = 1;
                                          _applyFilters();
                                        }),
                                      ),
                                      _GlassFilterChip(
                                        label: 'Unavailable Only',
                                        selected: _availability == 2,
                                        onSelected: (b) => setState(() {
                                          _availability = 2;
                                          _applyFilters();
                                        }),
                                      ),
                                    ],
                                  )
                                else if (_activeTab == 1)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _allCategories.map((c) {
                                      final isSelected = _selectedCategories
                                          .contains(c);
                                      return _GlassFilterChip(
                                        label: c,
                                        selected: isSelected,
                                        onSelected: (b) => setState(() {
                                          b
                                              ? _selectedCategories.add(c)
                                              : _selectedCategories.remove(c);
                                          _applyFilters();
                                        }),
                                      );
                                    }).toList(),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _allBrands.map((b) {
                                      final isSelected = _selectedBrands
                                          .contains(b);
                                      return _GlassFilterChip(
                                        label: b,
                                        selected: isSelected,
                                        onSelected: (v) => setState(() {
                                          v
                                              ? _selectedBrands.add(b)
                                              : _selectedBrands.remove(b);
                                          _applyFilters();
                                        }),
                                      );
                                    }).toList(),
                                  ),
                                const Divider(
                                  color: Colors.white24,
                                  height: 32,
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _selectedCategories.clear();
                                        _selectedBrands.clear();
                                        _availability = 0;
                                        _applyFilters();
                                      }),
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

                // Inventory Grid with Glass Cards
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 3 / 2, // Matches other list pages
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final item = _filtered[index];
                      return _GlassInventoryCard(
                        item: item,
                        isAdmin: _isAdmin,
                        // FIX: Use null-coalescing to provide non-null defaults
                        onEditTap: () async {
                          final res = await showInventoryEditDialog(
                            context,
                            equipmentName: item.name,
                            initialQuantity: item.quantity ?? 0,
                            initialCabinet: item.cabinet ?? '',
                          );
                          if (!context.mounted) return;
                          if (res == null || !res.changed) return;

                          final int? newQty = (res.quantity != item.quantity)
                              ? res.quantity
                              : null;
                          final String? newCab = (res.cabinet != item.cabinet)
                              ? res.cabinet
                              : null;

                          if (newQty == null && newCab == null) return;

                          _onSavePatch(item.id, newQty, newCab);
                        },
                      );
                    }, childCount: _filtered.length),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
          style: TextStyle(
            color: Colors.white, // Always white text
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

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
      backgroundColor: Colors.black.withValues(
        alpha: 0.3,
      ), // Darker background for unselected
      selectedColor: const Color(0xFF0047BB),
      checkmarkColor: Colors.white,
      labelStyle: const TextStyle(
        color: Colors.white, // Always white text
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? Colors.transparent : Colors.white38),
      ),
    );
  }
}

class _GlassInventoryCard extends StatelessWidget {
  final Equipment item;
  final bool isAdmin;
  final VoidCallback? onEditTap;

  const _GlassInventoryCard({
    required this.item,
    required this.isAdmin,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final qty = item.quantity ?? 0;
    final isAvailable = qty > 0;
    final imagePath = item.coverImages.isNotEmpty ? item.coverImages.first : '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // 1. Background Image or Fallback
          Positioned.fill(
            child: imagePath.isNotEmpty
                ? AvifImage.asset(imagePath, fit: BoxFit.cover)
                : Container(color: Colors.white.withValues(alpha: 0.1)),
          ),

          // 2. Gradient Overlay
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

          // 3. Content
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                // Availability Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.red.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isAvailable
                          ? Colors.green.withValues(alpha: 0.5)
                          : Colors.red.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    isAvailable ? 'In Stock: $qty' : 'Out of Stock',
                    style: TextStyle(
                      color: isAvailable
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isAdmin && item.cabinet != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Loc: ${item.cabinet}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 4. Edit Button (Admin Only)
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
