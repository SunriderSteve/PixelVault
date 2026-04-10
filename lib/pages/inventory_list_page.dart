import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:web/web.dart' as web;

import '../services/data_repository.dart';
import '../models/equipment_model.dart'; // Equipment
import 'inventory_edit_dialog.dart';

// Key used to persist admin mode in the browser's localStorage so that
// admin login survives page reloads and full browser restarts.
const String _adminStorageKey = 'pv_admin_mode';

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

  // admin mode — restored from localStorage so admin sessions persist
  // across page reloads / browser restarts.
  bool _isAdmin = web.window.localStorage.getItem(_adminStorageKey) == '1';

  // data
  late final List<Equipment> _all; // All items from repo
  late List<Equipment> _filtered; // Items to display
  late final List<String> _allCategories;
  late final List<String> _allBrands;

  @override
  void initState() {
    super.initState();
    final repo = DataRepository();
    _all = List.from(repo.getAllEquipment());
    _filtered = List.from(_all);

    _allCategories = _all.map((e) => e.category).toSet().toList()..sort();
    _allBrands = _all.map((e) => e.brand).toSet().toList()..sort();

    _search.addListener(_applyFilters);
    repo.overlayEpoch.addListener(_onOverlayChanged);
  }

  @override
  void dispose() {
    DataRepository().overlayEpoch.removeListener(_onOverlayChanged);
    _search.dispose();
    super.dispose();
  }

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
        if (_availability == 1) matchesAvail = qty > 0;
        if (_availability == 2) matchesAvail = qty <= 0;

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

  Future<void> _handleAdminToggle() async {
    if (_isAdmin) {
      // Prompt to exit admin mode
      final shouldExit = await showDialog<bool>(
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

      if (shouldExit == true) {
        setState(() => _isAdmin = false);
        web.window.localStorage.removeItem(_adminStorageKey);
      }
      return;
    }

    // Show password dialog
    await showDialog(
      context: context,
      builder: (context) => const _AdminPasswordDialog(),
    ).then((success) {
      if (success == true) {
        setState(() => _isAdmin = true);
        web.window.localStorage.setItem(_adminStorageKey, '1');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Admin Mode Enabled')));
        }
      }
    });
  }

  Future<void> _onSavePatch(String id, int? newQty, String? newCab) async {
    try {
      await DataRepository().applyInventoryChanges(
        id,
        quantity: newQty,
        cabinet: newCab,
      );
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
    const brandBlue = Color(0xFF0047BB);

    // Responsive Grid logic
    const double maxTileWidth = 420;
    final width = MediaQuery.of(context).size.width;
    final cols = math.max(
      2, // Changed to 2 to match other pages logic (unless very small screen)
      (width / maxTileWidth).floor(),
    );

    final totalFilters =
        _selectedCategories.length +
        _selectedBrands.length +
        (_availability != 0 ? 1 : 0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background
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
          // Blobs
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

          // Content
          CustomScrollView(
            slivers: [
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
                        onTap: _handleAdminToggle, // Direct tap on title too
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
                  // Admin Toggle Button (Replaced Sort Button)
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
                                          onPressed: () {
                                            _search.clear();
                                          },
                                        ),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            // Sort Button (Moved here)
                            IconButton(
                              icon: Icon(
                                _sortAsc
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
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
                            // Filter Button
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _showFilters = !_showFilters),
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
                                    final isSelected = _selectedBrands.contains(
                                      b,
                                    );
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
                              const Divider(color: Colors.white24, height: 32),
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

              // Inventory Grid
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 4 / 3,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = _filtered[index];
                    return _GlassInventoryCard(
                      item: item,
                      isAdmin: _isAdmin,
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
    );
  }
}

class _AdminPasswordDialog extends StatefulWidget {
  const _AdminPasswordDialog();

  @override
  State<_AdminPasswordDialog> createState() => _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends State<_AdminPasswordDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  final String _adminPassword = 'admin123';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text == _adminPassword) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorText = 'Incorrect Password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      title: const Text('Admin Access', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        obscureText: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Enter Password',
          hintStyle: const TextStyle(color: Colors.white54),
          errorText: _errorText,
          errorStyle: const TextStyle(color: Colors.redAccent),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF0047BB)),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Enter', style: TextStyle(color: Colors.white)),
        ),
      ],
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
          style: const TextStyle(
            color: Colors.white,
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
              mainAxisSize: MainAxisSize.min, // Allow column to shrink
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

                // Availability Badge (Always visible, always shows stock qty)
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

                // Cabinet Location (Admin Only)
                if (isAdmin && item.cabinet != null) ...[
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
                      'Cabinet: ${item.cabinet}',
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
