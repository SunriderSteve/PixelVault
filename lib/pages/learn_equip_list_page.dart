// lib/pages/equip_list_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/data_repository.dart';

class EquipListPage extends StatelessWidget {
  const EquipListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = DataRepository().getAllEquipment();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 71, 187),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true,
        centerTitle: false,
        title: Text(
          'Learn',
          style: TextStyle(
            fontVariations: [FontVariation('wght', 800)],
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            title: Text(
              item.name,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            onTap: () => context.push('/equip/${item.id}'),
          );
        },
      ),
    );
  }
}
