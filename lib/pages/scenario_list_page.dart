import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/data_repository.dart'; // Provides scenario data

class ScenarioListPage extends StatelessWidget {
  const ScenarioListPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Fetch all scenarios from the repository
    final scenarios = DataRepository().getAllScenarios();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scenarios'),
        actions: [
          // Navigation menu for main pages
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
        itemCount: scenarios.length,
        itemBuilder: (context, index) {
          final s = scenarios[index];
          return ListTile(
            title: Text(s.title), // Display scenario title
            onTap: () {
              // Navigate to scenario detail page
              context.go('/scenarios/${s.id}');
            },
          );
        },
      ),
    );
  }
}
