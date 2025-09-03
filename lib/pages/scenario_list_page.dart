import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/scenario_model.dart';

class ScenarioListPage extends StatelessWidget {
  const ScenarioListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<ScenarioGuide> items = DataRepository().getAllScenarios();

    const maxTileWidth = 420.0;
    final cols = math.max(
      2,
      (MediaQuery.of(context).size.width / maxTileWidth).floor(),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        backgroundColor: const Color(0xFF0047BB),
        title: const Text(
          'Production Scenarios',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: GridView.builder(
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 16,
            crossAxisSpacing: 8,
            childAspectRatio: 3 / 2,
          ),
          itemBuilder: (context, i) {
            final s = items[i];
            final cover = s.coverImages.isNotEmpty ? s.coverImages.first : '';
            return Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: () => context.push('/scenarios/${s.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: cover.isNotEmpty
                          ? AvifImage.asset(cover, fit: BoxFit.cover)
                          : const SizedBox.shrink(),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        s.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontVariations: [FontVariation('wght', 500)],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
