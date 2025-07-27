import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart'; // For AVIF image rendering
import '../services/data_repository.dart'; // To get equipment details

class EquipDetailPage extends StatelessWidget {
  final String itemId; // The ID of the equipment to display

  const EquipDetailPage({super.key, required this.itemId});

  @override
  Widget build(BuildContext context) {
    // Retrieve the equipment by ID (or null if not found)
    final item = DataRepository().getEquipment(itemId);
    return Scaffold(
      appBar: AppBar(
        title: Text(item?.name ?? 'Equipment Detail'),
        actions: [
          // Navigation menu for other main pages
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) {
              switch (value) {
                case 'home':
                  context.go('/');
                  break;
                case 'equipment':
                  context.go('/learn/equip-guides');
                  break;
                case 'scenarios':
                  context.go('/scenarios');
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'home', child: Text('Home')),
              PopupMenuItem(value: 'equipment', child: Text('Equipment List')),
              PopupMenuItem(value: 'scenarios', child: Text('Scenarios List')),
            ],
          ),
        ],
      ),
      body: item == null
          ? const Center(child: Text('Item not found'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  // Display each AVIF equipment image at the top, smaller height
                  if (item.images.isNotEmpty) ...[
                    for (final imgPath in item.images)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          height: 200, // Smaller fixed height for images
                          child: AvifImage.asset(imgPath, fit: BoxFit.cover),
                        ),
                      ),
                  ],
                  Text(item.description), // Equipment description
                  const SizedBox(height: 8),
                  Text('Stored at: ${item.storage}'), // Storage location
                  const SizedBox(height: 16),
                  const Text(
                    'Functions:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // List each function with its description
                  ...item.functions.entries.map(
                    (e) => Text('${e.key}: ${e.value}'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Related equipment:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8,
                    children: item.related.map((relatedId) {
                      final related = DataRepository().getEquipment(relatedId);
                      return ElevatedButton(
                        onPressed: () {
                          // Navigate to the related equipment detail
                          context.go('/learn/equip-guides/$relatedId');
                        },
                        child: Text(related?.name ?? relatedId),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
    );
  }
}
