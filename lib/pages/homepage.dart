import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart'; // For navigation between pages

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PixelVault'), // Main app bar title
        actions: [
          // Popup menu for quick navigation to all main pages
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) {
              switch (value) {
                case 'home':
                  context.go('/'); // Navigate to Home
                  break;
                case 'equipment':
                  context.go('/equip'); // Navigate to Equipment List
                  break;
                case 'scenarios':
                  context.go('/scenarios'); // Navigate to Scenarios List
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
      body: const Center(
        child: Text('Welcome to PixelVault!'), // Placeholder welcome text
      ),
    );
  }
}
