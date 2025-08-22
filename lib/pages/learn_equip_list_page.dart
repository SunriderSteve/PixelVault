import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/learn_equipment_model.dart';

class LearnEquipListPage extends StatefulWidget {
  const LearnEquipListPage({super.key});

  @override
  State<LearnEquipListPage> createState() => _LearnEquipListPageState();
}

class _LearnEquipListPageState extends State<LearnEquipListPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _showFilters = false;
  int _activeTab = 0; // 0: Category, 1: Brand

  final Set<String> _selectedCategories = {};
  final Set<String> _selectedBrands = {};

  late final List<Equipment> _allItems;
  late List<Equipment> _filteredItems;
  late final List<String> _allCategories;
  late final List<String> _allBrands;

  @override
  void initState() {
    super.initState();
    _allItems = DataRepository().getAllEquipment();
    _filteredItems = List.from(_allItems);
    _allCategories = _allItems.map((e) => e.category).toSet().toList();
    _allBrands = _allItems.map((e) => e.brand).toSet().toList();
    _searchController.addListener(_updateFilters);
  }

  void _updateFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _allItems.where((item) {
        final matchesQuery = item.name.toLowerCase().contains(query);
        final matchesCategory =
            _selectedCategories.isEmpty ||
            _selectedCategories.contains(item.category);
        final matchesBrand =
            _selectedBrands.isEmpty || _selectedBrands.contains(item.brand);
        return matchesQuery && matchesCategory && matchesBrand;
      }).toList();
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedCategories.clear();
      _selectedBrands.clear();
      _updateFilters();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double maxTileWidth = 420;
    final cols = math.max(
      2,
      (MediaQuery.of(context).size.width / maxTileWidth).floor(),
    );
    final totalFilters = _selectedCategories.length + _selectedBrands.length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        backgroundColor: const Color(0xFF0047BB),
        title: const Text(
          'Equipment Guides',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Sticky search & filter bar
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search Equipment',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _updateFilters();
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
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
          // Filter panel
          if (_showFilters)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 200,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tabs with notification
                        SizedBox(
                          width: 150,
                          child: ListView(
                            children: [
                              _TabButton(
                                label:
                                    'Category (${_selectedCategories.length})',
                                selected: _activeTab == 0,
                                onTap: () => setState(() => _activeTab = 0),
                              ),
                              _TabButton(
                                label: 'Brand (${_selectedBrands.length})',
                                selected: _activeTab == 1,
                                onTap: () => setState(() => _activeTab = 1),
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
                                if (_activeTab == 0)
                                  for (var c in _allCategories)
                                    FilterChip(
                                      label: Text(
                                        '$c (${_allItems.where((i) => i.category == c).length})',
                                      ),
                                      selected: _selectedCategories.contains(c),
                                      onSelected: (sel) => setState(() {
                                        (sel)
                                            ? _selectedCategories.add(c)
                                            : _selectedCategories.remove(c);

                                        _updateFilters();
                                      }),
                                    ),
                                if (_activeTab == 1)
                                  for (var b in _allBrands)
                                    FilterChip(
                                      label: Text(
                                        '$b (${_allItems.where((i) => i.brand == b).length})',
                                      ),
                                      selected: _selectedBrands.contains(b),
                                      onSelected: (sel) => setState(() {
                                        (sel)
                                            ? _selectedBrands.add(b)
                                            : _selectedBrands.remove(b);

                                        _updateFilters();
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
          // Content grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GridView.builder(
                itemCount: _filteredItems.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 8,
                  childAspectRatio: 3 / 2,
                ),
                itemBuilder: (context, index) {
                  final eq = _filteredItems[index];
                  final imagePath = eq.coverImages.isNotEmpty
                      ? eq.coverImages.first
                      : '';
                  return _EquipmentCard(
                    title: eq.name,
                    imagePath: imagePath,
                    onTap: () => context.push('/learn/equip-guides/${eq.id}'),
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

class _EquipmentCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final VoidCallback onTap;

  const _EquipmentCard({
    required this.title,
    required this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: imagePath.isNotEmpty
                  ? AvifImage.asset(imagePath, fit: BoxFit.cover)
                  : const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(title, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
