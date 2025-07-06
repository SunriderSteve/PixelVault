import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/data_repository.dart'; // Provides access to equipment data

class EquipListPage extends StatelessWidget {
  const EquipListPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Fetch all equipment items from the repository
    final items = DataRepository().getAllEquipment();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment'), // Page title
        actions: [
          // Reusing the navigation menu for consistency
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) {
              switch (value) {
                case 'home':
                  context.go('/');
                  break;
                case 'equipment':
                  context.go('/equip');
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
      body: ListView.builder(
        itemCount: items.length, // Number of equipment items
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            title: Text(item.name), // Display equipment name
            onTap: () {
              // Navigate to the equipment detail page
              context.go('/equip/${item.id}');
            },
          );
        },
      ),
    );
  }
}
