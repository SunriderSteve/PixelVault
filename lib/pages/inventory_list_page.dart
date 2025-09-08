import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/learn_equipment_model.dart'; // class: Equipment (with coverImages)

class InventoryListPage extends StatefulWidget {
  const InventoryListPage({super.key});

  @override
  State<InventoryListPage> createState() => _InventoryListPageState();
}

class _InventoryListPageState extends State<InventoryListPage> {
  final TextEditingController _searchController = TextEditingController();

  // UI state
  bool _showFilters = false;
  int _activeTab = 0; // 0: Availability, 1: Category, 2: Brand
  bool _sortAsc = true; // A→Z by default
  bool _isAdmin = false;

  // Availability tri-state: 0 = all, 1 = available only, 2 = unavailable only
  int _availability = 0;

  // Selections
  final Set<String> _selectedCategories = {};
  final Set<String> _selectedBrands = {};

  // Data
  late final List<_Row> _all;
  late List<_Row> _display;

  // Facets
  late final List<String> _allCategories;
  late final List<String> _allBrands;

  // Yes I know this not secure at all
  static const String _adminPassword = 'admin123';

  @override
  void initState() {
    super.initState();

    final repo = DataRepository();
    final List<Equipment> invItems = repo.getInventoryItems();

    _all = invItems
        .map(
          (e) => _Row(
            eq: e,
            brand: e.brand,
            category: e.category,
            cover: e.coverImages.isNotEmpty ? e.coverImages.first : '',
            quantity: e.quantity ?? 0,
            cabinet: e.cabinet ?? '',
          ),
        )
        .toList();

    _allCategories = _all.map((r) => r.category).toSet().toList()..sort();
    _allBrands = _all.map((r) => r.brand).toSet().toList()..sort();

    _display = List.from(_all);
    _searchController.addListener(_applyFilters);
    _applyFilters();
  }

  void _applyFilters() {
    final q = _searchController.text.toLowerCase().trim();
    setState(() {
      _display = _all.where((r) {
        final matchQ = q.isEmpty || r.eq.name.toLowerCase().contains(q);
        final matchC =
            _selectedCategories.isEmpty ||
            _selectedCategories.contains(r.category);
        final matchB =
            _selectedBrands.isEmpty || _selectedBrands.contains(r.brand);

        bool matchAvail = true;
        if (_availability == 1) {
          matchAvail = r.quantity > 0; // available only
        } else if (_availability == 2) {
          matchAvail = r.quantity <= 0; // unavailable only
        }

        return matchQ && matchC && matchB && matchAvail;
      }).toList();

      _display.sort(
        (a, b) => a.eq.name.toLowerCase().compareTo(b.eq.name.toLowerCase()),
      );
      if (!_sortAsc) {
        _display = _display.reversed.toList();
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedCategories.clear();
      _selectedBrands.clear();
      _availability = 0;
      _applyFilters();
    });
  }

  Future<void> _promptEnterAdmin() async {
    final controller = TextEditingController();
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Admin',
      barrierColor: Colors.black26,
      pageBuilder: (context, a1, a2) {
        return Stack(
          children: [
            // Blur the background behind the dialog
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
                      onSubmitted: (_) => Navigator.of(
                        context,
                      ).pop(controller.text == _adminPassword),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(controller.text == _adminPassword),
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

  Future<void> _confirmExitAdmin() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch back to User Mode?'),
        content: const Text(
          'You will need to re-enter the password to enter Admin Mode again.',
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
    if (proceed == true) {
      setState(() => _isAdmin = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Returned to user mode')));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const maxTile = 420.0;
    final cols = math.max(
      2,
      (MediaQuery.of(context).size.width / maxTile).floor(),
    );
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
          // Sticky search + sort + filter row
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search Inventory',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _applyFilters();
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                // Sort button toggles A→Z / Z→A
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
                // Filter button with count badge
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

          // Filter panel (tabs: Availability | Category | Brand)
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
                        Expanded(
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                // Availability chip (tri-state) styled like other chips
                                if (_activeTab == 0)
                                  FilterChip(
                                    selected: _availability != 0,
                                    showCheckmark: false,
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
                                        _applyFilters();
                                      });
                                    },
                                  ),

                                if (_activeTab == 1)
                                  for (final c in _allCategories)
                                    FilterChip(
                                      label: Text(
                                        '$c (${_all.where((r) => r.category == c).length})',
                                      ),
                                      selected: _selectedCategories.contains(c),
                                      onSelected: (sel) => setState(() {
                                        sel
                                            ? _selectedCategories.add(c)
                                            : _selectedCategories.remove(c);
                                        _applyFilters();
                                      }),
                                    ),

                                if (_activeTab == 2)
                                  for (final b in _allBrands)
                                    FilterChip(
                                      label: Text(
                                        '$b (${_all.where((r) => r.brand == b).length})',
                                      ),
                                      selected: _selectedBrands.contains(b),
                                      onSelected: (sel) => setState(() {
                                        sel
                                            ? _selectedBrands.add(b)
                                            : _selectedBrands.remove(b);
                                        _applyFilters();
                                      }),
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

          // Grid
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
                    title: r.eq.name,
                    coverPath: r.cover,
                    quantity: r.quantity,
                    cabinet: r.cabinet,
                    isAdmin: _isAdmin,
                    onTap: () => context.push('/learn/equip-guides/${r.eq.id}'),
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

class _Row {
  final Equipment eq;
  final String brand;
  final String category;
  final String cover;
  final int quantity;
  final String cabinet;

  _Row({
    required this.eq,
    required this.brand,
    required this.category,
    required this.cover,
    required this.quantity,
    required this.cabinet,
  });
}

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

class _InventoryCard extends StatelessWidget {
  final String title;
  final String coverPath;
  final int quantity;
  final String cabinet;
  final bool isAdmin;
  final VoidCallback onTap;

  const _InventoryCard({
    required this.title,
    required this.coverPath,
    required this.quantity,
    required this.cabinet,
    required this.isAdmin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnavailable = quantity <= 0;

    Widget thumb;
    if (coverPath.isEmpty) {
      thumb = Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFFE0E0E0)),
          if (isUnavailable) Container(color: Colors.white.withOpacity(0.6)),
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
                Container(color: Colors.white.withOpacity(0.6)),
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
                        CrossAxisAlignment.start, // left align quantity/cabinet
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
                      if (isAdmin && cabinet.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Cabinet: $cabinet',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Admin edit button (bottom-right)
            if (isAdmin)
              Positioned(
                right: 8,
                bottom: 8,
                child: FloatingActionButton.small(
                  heroTag: null,
                  onPressed: () {
                    // TODO: implement edit behavior
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
