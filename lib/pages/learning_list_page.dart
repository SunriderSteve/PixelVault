import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

class LearningListPage extends StatelessWidget {
  const LearningListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
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
        automaticallyImplyLeading: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const double maxTileWidth = 420;
          int crossAxisCount = math.max(
            2,
            (constraints.maxWidth / maxTileWidth).floor(),
          );

          return Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search Guides',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    itemCount: _guideItems.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 8,
                      childAspectRatio: 3 / 2,
                    ),
                    itemBuilder: (context, i) {
                      final item = _guideItems[i];
                      return _GuideCard(
                        title: item.title,
                        imagePath: item.imagePath,
                        onTap: () => context.go(item.route),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Data holder for guide tiles
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

const List<_GuideItem> _guideItems = [
  _GuideItem(
    title: 'Equipment Guide',
    imagePath: 'assets/images/homepage/inventory.avif',
    route: '/equip',
  ),
  _GuideItem(
    title: 'Videography Guide',
    imagePath: 'assets/images/homepage/scenarios.avif',
    route: '/equip/videography-guide',
  ),
];

/// Card widget preserving AVIF rendering
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
    //final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: AvifImage.asset(imagePath, fit: BoxFit.cover)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontVariations: [FontVariation('wght', 500)]),
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
