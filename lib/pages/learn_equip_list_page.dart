import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/equipment_model.dart';

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
    // Brand Blue
    const brandBlue = Color(0xFF0047BB);

    // Responsive Grid
    const double maxTileWidth = 420;
    final cols = math.max(
      2,
      (MediaQuery.of(context).size.width / maxTileWidth).floor(),
    );
    final totalFilters = _selectedCategories.length + _selectedBrands.length;

    // Hero wrapping the entire scaffold for smooth transition
    return Hero(
      tag: 'equip_guides_card',
      child: Scaffold(
        backgroundColor: Colors.black, // Base background
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

            // 2. Background Blobs for Depth
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

            // 3. Content with Glassmorphism
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

                // Search & Filter Bar (Glassmorphism)
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

                // Filter Panel (Conditional)
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
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _activeTab == 0
                                      ? _allCategories.map((c) {
                                          final isSelected = _selectedCategories
                                              .contains(c);
                                          return _GlassFilterChip(
                                            label: c,
                                            selected: isSelected,
                                            onSelected: (sel) => setState(() {
                                              sel
                                                  ? _selectedCategories.add(c)
                                                  : _selectedCategories.remove(
                                                      c,
                                                    );
                                              _updateFilters();
                                            }),
                                          );
                                        }).toList()
                                      : _allBrands.map((b) {
                                          final isSelected = _selectedBrands
                                              .contains(b);
                                          return _GlassFilterChip(
                                            label: b,
                                            selected: isSelected,
                                            onSelected: (sel) => setState(() {
                                              sel
                                                  ? _selectedBrands.add(b)
                                                  : _selectedBrands.remove(b);
                                              _updateFilters();
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

                // Grid Content
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
                      final imagePath = eq.coverImages.isNotEmpty
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
            color: selected ? Colors.white : Colors.white54, // Brighter border
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white, // Always white text
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
        side: BorderSide(
          color: selected
              ? Colors.transparent
              : Colors.white38, // Visible border
        ),
      ),
    );
  }
}

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
          // Background Image
          Positioned.fill(
            child: imagePath.isNotEmpty
                ? AvifImage.asset(imagePath, fit: BoxFit.cover)
                : Container(color: Colors.white.withValues(alpha: 0.1)),
          ),
          // Gradient Overlay
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
          // Text Content
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
          // Tap handler
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
