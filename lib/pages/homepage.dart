import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0047BB), // RGB(0,71,187)
        title: const Text(
          'PixelVault',
          style: TextStyle(
            fontVariations: [FontVariation('wght', 800)],
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const double maxTileWidth = 420; // cap per-card width
          // Compute how many columns we can fit given the cap, but never below 2.
          int crossAxisCount = math.max(
            2,
            (constraints.maxWidth / maxTileWidth).floor(),
          );

          return Padding(
            padding: const EdgeInsets.all(8),
            child: GridView.builder(
              itemCount: _items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 16,
                crossAxisSpacing: 8,
                childAspectRatio: 3 / 2,
              ),
              itemBuilder: (context, i) {
                final item = _items[i];
                return _NavCard(
                  title: item.title,
                  imagePath: item.imagePath,
                  onTap: () => context.go(item.route),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Simple data holder for the tiles.
class _HomeItem {
  final String title;
  final String imagePath;
  final String route;
  const _HomeItem({
    required this.title,
    required this.imagePath,
    required this.route,
  });
}

const List<_HomeItem> _items = [
  _HomeItem(
    title: 'Learn',
    imagePath: 'assets/images/homepage/learn.avif',
    route: '/equip',
  ),
  _HomeItem(
    title: 'Production Scenarios',
    imagePath: 'assets/images/homepage/scenarios.avif',
    route: '/scenarios',
  ),
  _HomeItem(
    title: 'Inventory List',
    imagePath: 'assets/images/homepage/inventory.avif',
    route: '/inventory',
  ),
];

/// Card widget that preserves your AVIF image rendering.
class _NavCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final VoidCallback onTap;

  const _NavCard({
    required this.title,
    required this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(fontVariations: [FontVariation('wght', 500)]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
