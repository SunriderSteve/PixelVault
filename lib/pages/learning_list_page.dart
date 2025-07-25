import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
//import '../models/learn_equipment_model.dart';

class LearningListPage extends StatefulWidget {
  const LearningListPage({super.key});

  @override
  _LearningListPageState createState() => _LearningListPageState();
}

class _LearningListPageState extends State<LearningListPage> {
  final TextEditingController _searchController = TextEditingController();
  late List<_GuideItem> _displayItems;
  late final List<_GuideItem> _staticNavItems;
  late final List<_GuideItem> _dynamicItems;

  @override
  void initState() {
    super.initState();
    // Static nav cards
    _staticNavItems = [
      const _GuideItem(
        title: 'Equipment Guides',
        imagePath: 'assets/images/homepage/inventory.avif',
        route: '/equip',
      ),
      const _GuideItem(
        title: 'Videography Guides',
        imagePath: 'assets/images/homepage/scenarios.avif',
        route: '/equip/videography-guide',
      ),
    ];
    // Dynamic items: only equipment for now
    final equipment = DataRepository().getAllEquipment();
    _dynamicItems = [
      for (var eq in equipment)
        _GuideItem(
          title: eq.name,
          imagePath: eq.images.isNotEmpty ? eq.images.first : '',
          route: '/equip/${eq.id}',
        ),
    ];
    // Initialize display with static nav items
    _displayItems = List.from(_staticNavItems);
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _displayItems = List.from(_staticNavItems);
      } else {
        _displayItems = _dynamicItems
            .where((item) => item.title.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double maxTileWidth = 420;
    final crossAxisCount = math.max(
      2,
      (MediaQuery.of(context).size.width / maxTileWidth).floor(),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        backgroundColor: const Color(0xFF0047BB),
        title: const Text(
          'Learning Guides',
          style: TextStyle(
            fontVariations: [FontVariation('wght', 800)],
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search Guides',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                itemCount: _displayItems.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 8,
                  childAspectRatio: 3 / 2,
                ),
                itemBuilder: (context, index) {
                  final item = _displayItems[index];
                  return _GuideCard(
                    title: item.title,
                    imagePath: item.imagePath,
                    onTap: () => context.push(item.route),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic guide item
class _GuideItem {
  final String title;
  final String imagePath;
  final String route;
  const _GuideItem({
    required this.title,
    required this.imagePath,
    required this.route,
  });
}

/// Card widget
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
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontVariations: [FontVariation('wght', 500)]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
