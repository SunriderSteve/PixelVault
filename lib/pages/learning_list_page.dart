import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';

class LearningListPage extends StatefulWidget {
  const LearningListPage({Key? key}) : super(key: key);

  @override
  _LearningListPageState createState() => _LearningListPageState();
}

class _LearningListPageState extends State<LearningListPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _showFilters = false;
  int _activeTab = 0; // 0:Type,1:Category,2:Brand

  // Filter selections
  final Set<String> _selectedTypes = {};
  final Set<String> _selectedCategories = {};
  final Set<String> _selectedBrands = {};

  late final List<String> _allTypes;
  late final List<String> _allCategories;
  late final List<String> _allBrands;

  late final List<_GuideItem> _staticNavItems;
  late final List<_GuideItem> _dynamicItems;
  late List<_GuideItem> _displayItems;

  @override
  void initState() {
    super.initState();
    _staticNavItems = const [
      _GuideItem(
        title: 'Equipment Guides',
        imagePath: 'assets/images/homepage/inventory.avif',
        route: '/learn/equip-guides',
        type: 'Type: Equipment Guides',
      ),
      _GuideItem(
        title: 'Videography Guides',
        imagePath: 'assets/images/homepage/scenarios.avif',
        route: '/learn/videography-guides',
        type: 'Type: Videography Guides',
      ),
    ];
    final equips = DataRepository().getAllEquipment();
    _dynamicItems = equips
        .map(
          (eq) => _GuideItem(
            title: eq.name,
            imagePath: eq.coverImages.isNotEmpty ? eq.coverImages.first : '',
            route: '/learn/equip-guides/${eq.id}',
            type: 'Type: Equipment Guides',
            category: eq.category,
            brand: eq.brand,
          ),
        )
        .toList();

    _allTypes = _staticNavItems.map((e) => e.type).toSet().toList();
    _allCategories = equips.map((e) => e.category).toSet().toList();
    _allBrands = equips.map((e) => e.brand).toSet().toList();

    _displayItems = List.from(_staticNavItems);
    _searchController.addListener(_updateDisplayItems);
  }

  void _updateDisplayItems() {
    final q = _searchController.text.toLowerCase();
    final hasFilters =
        _selectedTypes.isNotEmpty ||
        _selectedCategories.isNotEmpty ||
        _selectedBrands.isNotEmpty;
    setState(() {
      if (q.isEmpty && !hasFilters) {
        _displayItems = List.from(_staticNavItems);
      } else {
        _displayItems = _dynamicItems.where((item) {
          final matchesQ = item.title.toLowerCase().contains(q);
          final matchesT =
              _selectedTypes.isEmpty || _selectedTypes.contains(item.type);
          final matchesC =
              _selectedCategories.isEmpty ||
              _selectedCategories.contains(item.category);
          final matchesB =
              _selectedBrands.isEmpty || _selectedBrands.contains(item.brand);
          return matchesQ && matchesT && matchesC && matchesB;
        }).toList();
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedTypes.clear();
      _selectedCategories.clear();
      _selectedBrands.clear();
      _updateDisplayItems();
    });
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
        _selectedTypes.length +
        _selectedCategories.length +
        _selectedBrands.length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        backgroundColor: const Color(0xFF0047BB),
        title: const Text(
          'Learning Guides',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search Guides',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _updateDisplayItems();
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
                        SizedBox(
                          width: 150,
                          child: ListView(
                            children: [
                              _TabButton(
                                label: 'Type (${_selectedTypes.length})',
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
                                if (_activeTab == 0)
                                  for (var t in _allTypes)
                                    FilterChip(
                                      label: Text(
                                        '$t (${_dynamicItems.where((i) => i.type == t).length})',
                                      ),
                                      selected: _selectedTypes.contains(t),
                                      onSelected: (sel) => setState(() {
                                        sel
                                            ? _selectedTypes.add(t)
                                            : _selectedTypes.remove(t);
                                        _updateDisplayItems();
                                      }),
                                    ),
                                if (_activeTab == 1)
                                  for (var c in _allCategories)
                                    FilterChip(
                                      label: Text(
                                        '$c (${_dynamicItems.where((i) => i.category == c).length})',
                                      ),
                                      selected: _selectedCategories.contains(c),
                                      onSelected: (sel) => setState(() {
                                        sel
                                            ? _selectedCategories.add(c)
                                            : _selectedCategories.remove(c);
                                        _updateDisplayItems();
                                      }),
                                    ),
                                if (_activeTab == 2)
                                  for (var b in _allBrands)
                                    FilterChip(
                                      label: Text(
                                        '$b (${_dynamicItems.where((i) => i.brand == b).length})',
                                      ),
                                      selected: _selectedBrands.contains(b),
                                      onSelected: (sel) => setState(() {
                                        sel
                                            ? _selectedBrands.add(b)
                                            : _selectedBrands.remove(b);
                                        _updateDisplayItems();
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GridView.builder(
                itemCount: _displayItems.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 8,
                  childAspectRatio: 3 / 2,
                ),
                itemBuilder: (context, idx) {
                  final g = _displayItems[idx];
                  return _GuideCard(
                    title: g.title,
                    imagePath: g.imagePath,
                    onTap: () => context.push(g.route),
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

class _GuideItem {
  final String title;
  final String imagePath;
  final String route;
  final String type;
  final String? category;
  final String? brand;
  const _GuideItem({
    required this.title,
    required this.imagePath,
    required this.route,
    required this.type,
    this.category,
    this.brand,
  });
}

class _GuideCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final VoidCallback onTap;
  const _GuideCard({
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
