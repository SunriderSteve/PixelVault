import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart'; // For navigation between pages
import 'package:flutter_avif/flutter_avif.dart';

class NavCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final VoidCallback onTap;
  const NavCard({
    super.key,
    required this.title,
    required this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Rounded corners
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image area with fixed aspect ratio
            AspectRatio(
              aspectRatio: 16 / 9,
              child: AvifImage.asset(imagePath, fit: BoxFit.cover),
            ),
            // Title area below the image, centered
            Expanded(
              child: Center(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The homepage showing three navigation cards
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Blue horizontal bar with title; no back button on homepage
      appBar: AppBar(
        backgroundColor: Color.fromARGB(255, 0, 71, 187),
        automaticallyImplyLeading: false,
        title: const Text(
          'PixelVault',
          style: TextStyle(
            fontVariations: [FontVariation('wght', 800)],
            color: Colors.white,
          ),
        ),
        centerTitle: false,
      ),
      // Grid with responsive cards
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2, // Two cards per row
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 6 / 4, // Width to height ratio for cards
          children: [
            NavCard(
              title: 'Learn',
              imagePath: 'assets/images/homepage/learn.avif',
              onTap: () => context.go('/equip'),
            ),
            NavCard(
              title: 'Production Scenarios',
              imagePath: 'assets/images/homepage/scenarios.avif',
              onTap: () => context.go('/scenarios'),
            ),
            NavCard(
              title: 'Inventory List',
              imagePath: 'assets/images/homepage/inventory.avif',
              onTap: () => context.go('/inventory'), // Route stub
            ),
          ],
        ),
      ),
    );
  }
}
