import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/data_repository.dart'; // To fetch scenario details

class ScenarioDetailPage extends StatelessWidget {
  final String scenarioId; // ID of the scenario to display

  const ScenarioDetailPage({super.key, required this.scenarioId});

  @override
  Widget build(BuildContext context) {
    final scenario = DataRepository().getScenario(scenarioId);
    return Scaffold(
      appBar: AppBar(
        title: Text(scenario?.title ?? 'Scenario Detail'),
        actions: [
          // Navigation menu for consistency across pages
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
      body: scenario == null
          ? const Center(child: Text('Scenario not found'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scenario.description), // Scenario description
                  const SizedBox(height: 16),
                  const Text(
                    'Required Equipment:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // List each required equipment with navigation
                  ...scenario.equipment.map((eid) {
                    final eq = DataRepository().getEquipment(eid);
                    return ListTile(
                      title: Text(eq?.name ?? eid),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        // Navigate to equipment detail
                        context.go('/equip/$eid');
                      },
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
