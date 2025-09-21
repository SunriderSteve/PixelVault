import 'dart:math' as math;
import 'dart:ui' as ui;
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

  // admin
  bool _isAdmin = false;

  // data
  late final List<_Row> _all; // immutable base rows derived from repository
  late List<_Row> _display; // filtered + sorted rows

  // facet values
  late final List<String> _allCategories;
  late final List<String> _allBrands;

  VoidCallback? _overlayListener;

  @override
  void initState() {
    super.initState();

    // build immutable rows once from repository
    final repo = DataRepository();
    final List<Equipment> invItems = repo.getInventoryItems();

    _all = invItems
        .map(
          (e) => _Row(
            eq: e,
            nameKey: e.name.toLowerCase(),
            brand: e.brand,
            category: e.category,
            cover: e.coverImages.isNotEmpty ? e.coverImages.first : '',
            quantity: e.quantity ?? 0,
            cabinet: e.cabinet ?? '',
          ),
        )
        .toList(growable: false);

    _allCategories = _all.map((r) => r.category).toSet().toList()..sort();
    _allBrands = _all.map((r) => r.brand).toSet().toList()..sort();

    _display = List.of(_all);

    _search.addListener(_applyFilters);
    _applyFilters();

    _overlayListener = _syncOverlayToRows;
    DataRepository().overlayEpoch.addListener(_overlayListener!);
  }

  void _syncOverlayToRows() {
    final repo = DataRepository();
    bool any = false;

    for (var i = 0; i < _all.length; i++) {
      final r = _all[i];
      final o = repo.getOverlayFor(r.eq.id);
      final newQty = (o?['quantity'] as int?) ?? r.quantity;
      final newCab = (o?['cabinet'] as String?) ?? r.cabinet;

      if (newQty != r.quantity || newCab != r.cabinet) {
        _all[i] = _Row(
          eq: r.eq,
          nameKey: r.nameKey,
          brand: r.brand,
          category: r.category,
          cover: r.cover,
          quantity: newQty,
          cabinet: newCab,
        );
        any = true;
      }
    }

    if (any) _applyFilters(); // setState happens inside _applyFilters
  }

  void _applyLocalOptimisticUpdate(
    String id, {
    int? quantity,
    String? cabinet,
  }) {
    final idx = _all.indexWhere((r) => r.eq.id == id);
    if (idx == -1) return;
    final r = _all[idx];
    _all[idx] = _Row(
      eq: r.eq,
      nameKey: r.nameKey,
      brand: r.brand,
      category: r.category,
      cover: r.cover,
      quantity: quantity ?? r.quantity,
      cabinet: cabinet ?? r.cabinet,
    );
    _applyFilters(); // setState to refresh UI
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();

    if (_overlayListener != null) {
      DataRepository().overlayEpoch.removeListener(_overlayListener!);
    }
  }

  // recompute display list based on current query, filters, sort
  void _applyFilters() {
    final q = _search.text.trim().toLowerCase();

    final filtered = _all.where((r) {
      final matchQ = q.isEmpty || r.nameKey.contains(q);
      final matchC =
          _selectedCategories.isEmpty ||
          _selectedCategories.contains(r.category);
      final matchB =
          _selectedBrands.isEmpty || _selectedBrands.contains(r.brand);

      bool matchAvail = true;
      if (_availability == 1) {
        matchAvail = r.quantity > 0;
      } else if (_availability == 2) {
        matchAvail = r.quantity <= 0;
      }

      return matchQ && matchC && matchB && matchAvail;
    }).toList();

    filtered.sort((a, b) => a.nameKey.compareTo(b.nameKey));
    if (!_sortAsc) {
      filtered.reverseRange(0, filtered.length);
    }

    setState(() => _display = filtered);
  }

  // clear all filters to defaults
  void _clearFilters() {
    _selectedCategories.clear();
    _selectedBrands.clear();
    _availability = 0;
    _applyFilters();
    setState(() {}); // refresh badges
  }

  // prompt for admin password and toggle admin mode
  Future<void> _promptEnterAdmin() async {
    final controller = TextEditingController();
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Admin',
      barrierColor: Colors.black.withValues(alpha: 0.25), // slight dim
      pageBuilder: (context, a1, a2) {
        return Stack(
          children: [
            // blur background behind dialog
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: const SizedBox.expand(),
            ),
            Center(
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AlertDialog(
                    title: const Text('Enter password to enter Admin Mode'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => Navigator.of(context).pop(
                        controller.text == 'admin123', // demo only
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(
                          controller.text == 'admin123', // demo only
                        ),
                        child: const Text('Enter'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionDuration: const Duration(milliseconds: 150),
    );

    if (!mounted) return; // guard context after async gap

    if (ok == true) {
      setState(() => _isAdmin = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Admin mode enabled')));
    } else if (ok == false) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Incorrect password')));
    }
  }

  // confirm exit from admin mode
  Future<void> _confirmExitAdmin() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch back to User Mode?'),
        content: const Text(
          'You will need to re-enter the password to enter Admin Mode again',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Proceed'),
          ),
        ],
      ),
    );

    if (!mounted) return; // guard context after async gap

    if (proceed == true) {
      setState(() => _isAdmin = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Returned to user mode')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // responsive columns with minimum of 2
    const maxTile = 420.0;
    final cols = math.max(
      2,
      (MediaQuery.of(context).size.width / maxTile).floor(),
    );

    // badge counts across all filters
    final totalFilters =
        _selectedCategories.length +
        _selectedBrands.length +
        (_availability == 0 ? 0 : 1);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        backgroundColor: _isAdmin ? Colors.red : const Color(0xFF0047BB),
        title: const Text('Inventory', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _isAdmin ? _confirmExitAdmin : _promptEnterAdmin,
            child: Text(
              _isAdmin ? 'Admin Mode' : 'User Mode',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // sticky search + sort + filter row
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search Inventory',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                _applyFilters();
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                // sort toggles A→Z / Z→A
                IconButton(
                  tooltip: _sortAsc ? 'Sort Z → A' : 'Sort A → Z',
                  icon: Icon(
                    _sortAsc
                        ? Icons.sort_by_alpha
                        : Icons.sort_by_alpha_outlined,
                  ),
                  onPressed: () {
                    setState(() => _sortAsc = !_sortAsc);
                    _applyFilters();
                  },
                ),
                // filter button with count badge
                GestureDetector(
                  onTap: () => setState(() => _showFilters = !_showFilters),
                  child: Stack(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.filter_alt, size: 28),
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

          // filter panel with left-side tabs
          if (_showFilters)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 220,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // tabs with per-tab active count
                        SizedBox(
                          width: 170,
                          child: ListView(
                            children: [
                              _TabButton(
                                label:
                                    'Availability (${_availability == 0 ? 0 : 1})',
                                selected: _activeTab == 0,
                                onTap: () => setState(() => _activeTab = 0),
                              ),
                              _TabButton(
                                label:
                                    'Category (${_selectedCategories.length})',
                                selected: _activeTab == 1,
                                onTap: () => setState(() => _activeTab = 1),
                              ),
                              _TabButton(
                                label: 'Brand (${_selectedBrands.length})',
                                selected: _activeTab == 2,
                                onTap: () => setState(() => _activeTab = 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // panel body shows chips for active tab only
                        Expanded(
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_activeTab == 0)
                                  FilterChip(
                                    selected: _availability != 0,
                                    showCheckmark:
                                        false, // avoid default ✓ overlay
                                    label: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_availability == 1) ...[
                                          const Icon(
                                            Icons.check,
                                            size: 16,
                                            color: Colors.green,
                                          ),
                                          const SizedBox(width: 6),
                                        ] else if (_availability == 2) ...[
                                          const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.redAccent,
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        const Text('Available'),
                                      ],
                                    ),
                                    onSelected: (_) {
                                      setState(() {
                                        _availability =
                                            (_availability + 1) % 3; // 0→1→2→0
                                      });
                                      _applyFilters();
                                    },
                                  ),
                                if (_activeTab == 1)
                                  for (final c in _allCategories)
                                    FilterChip(
                                      label: Text(
                                        '$c (${_all.where((r) => r.category == c).length})',
                                      ),
                                      selected: _selectedCategories.contains(c),
                                      onSelected: (sel) {
                                        setState(() {
                                          sel
                                              ? _selectedCategories.add(c)
                                              : _selectedCategories.remove(c);
                                        });
                                        _applyFilters();
                                      },
                                    ),
                                if (_activeTab == 2)
                                  for (final b in _allBrands)
                                    FilterChip(
                                      label: Text(
                                        '$b (${_all.where((r) => r.brand == b).length})',
                                      ),
                                      selected: _selectedBrands.contains(b),
                                      onSelected: (sel) {
                                        setState(() {
                                          sel
                                              ? _selectedBrands.add(b)
                                              : _selectedBrands.remove(b);
                                        });
                                        _applyFilters();
                                      },
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: _clearFilters,
                          child: const Text('Clear Filters'),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () => setState(() => _showFilters = false),
                          child: const Text('Show Results'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // grid of cards
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GridView.builder(
                itemCount: _display.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 8,
                  childAspectRatio: 3 / 2,
                ),
                itemBuilder: (context, i) {
                  final r = _display[i];
                  return _InventoryCard(
                    id: r.eq.id,
                    title: r.eq.name,
                    coverPath: r.cover,
                    quantity: r.quantity,
                    cabinet: r.cabinet,
                    isAdmin: _isAdmin,
                    onTap: () => context.push('/learn/equip/${r.eq.id}'),
                    onSavePatch: (int? q, String? c) async {
                      // optimistic local UI first
                      final oldQ = r.quantity;
                      final oldC = r.cabinet;
                      _applyLocalOptimisticUpdate(
                        r.eq.id,
                        quantity: q,
                        cabinet: c,
                      );

                      try {
                        await DataRepository().applyInventoryChanges(
                          r.eq.id,
                          quantity: q,
                          cabinet: c,
                        );
                        if (!mounted) return; // async gap guard
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Saved changes for ${r.eq.name}'),
                          ),
                        );
                      } catch (e) {
                        // revert on failure
                        _applyLocalOptimisticUpdate(
                          r.eq.id,
                          quantity: oldQ,
                          cabinet: oldC,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save: $e')),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// derived row used for fast filtering and sorting
class _Row {
  final Equipment eq;
  final String nameKey;
  final String brand;
  final String category;
  final String cover;
  final int quantity;
  final String cabinet;

  const _Row({
    required this.eq,
    required this.nameKey,
    required this.brand,
    required this.category,
    required this.cover,
    required this.quantity,
    required this.cabinet,
  });
}

// side tab button for filter panel
class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(color: selected ? Colors.blue : Colors.black),
      ),
    );
  }
}

// single inventory card with unavailable overlay and admin affordances
class _InventoryCard extends StatelessWidget {
  final String id;
  final String title;
  final String coverPath;
  final int quantity;
  final String cabinet;
  final bool isAdmin;
  final VoidCallback onTap;
  final Future<void> Function(int? quantity, String? cabinet)? onSavePatch;

  const _InventoryCard({
    required this.id,
    required this.title,
    required this.coverPath,
    required this.quantity,
    required this.cabinet,
    required this.isAdmin,
    required this.onTap,
    this.onSavePatch,
  });

  @override
  Widget build(BuildContext context) {
    final isUnavailable = quantity <= 0;

    // build thumbnail with optional blurred unavailable overlay
    Widget thumb;
    if (coverPath.isEmpty) {
      thumb = Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFFE0E0E0)),
          if (isUnavailable)
            ColoredBox(color: Colors.white.withValues(alpha: 0.6)),
          if (isUnavailable)
            const Center(
              child: Text(
                'Unavailable',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: Colors.redAccent,
                ),
              ),
            ),
        ],
      );
    } else {
      final base = AvifImage.asset(coverPath, fit: BoxFit.cover);
      thumb = isUnavailable
          ? Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                  child: base,
                ),
                ColoredBox(color: Colors.white.withValues(alpha: 0.6)),
                const Center(
                  child: Text(
                    'Unavailable',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ],
            )
          : base;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: thumb),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment:
                        CrossAxisAlignment.start, // left align labels
                    children: [
                      Center(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontVariations: [FontVariation('wght', 500)],
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$quantity Left',
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: isUnavailable
                              ? Colors.grey
                              : Colors.deepOrange,
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Cabinet: ${cabinet.isEmpty ? '—' : cabinet}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // admin edit affordance bottom-right
            if (isAdmin)
              Positioned(
                right: 8,
                bottom: 8,
                child: FloatingActionButton.small(
                  heroTag: null,
                  onPressed: () async {
                    final res = await showInventoryEditDialog(
                      context,
                      equipmentName: title,
                      initialQuantity: quantity,
                      initialCabinet: cabinet,
                    );
                    if (!context.mounted) return; // async gap guard

                    if (res == null || !res.changed) return;

                    final int? newQty = (res.quantity != quantity)
                        ? res.quantity
                        : null;
                    final String? newCab = (res.cabinet != cabinet)
                        ? res.cabinet
                        : null;
                    if (newQty == null && newCab == null) return;

                    // delegate to page so it can mutate _all and call repo
                    await onSavePatch?.call(newQty, newCab);
                  },
                  child: const Icon(Icons.edit),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
