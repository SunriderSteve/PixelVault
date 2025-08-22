import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/scenario_model.dart';
import '../models/learn_equipment_model.dart';

class ScenarioDetailPage extends StatefulWidget {
  final String id;
  const ScenarioDetailPage({super.key, required this.id});

  @override
  State<ScenarioDetailPage> createState() => _ScenarioDetailPageState();
}

class _ScenarioDetailPageState extends State<ScenarioDetailPage> {
  late final ScenarioGuide _scenario;

  @override
  void initState() {
    super.initState();
    final s = DataRepository().getScenario(widget.id);
    if (s == null) {
      throw Exception('Scenario not found: ${widget.id}');
    }
    _scenario = s;
  }

  @override
  Widget build(BuildContext context) {
    const double coverMaxHeight = 360;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        backgroundColor: const Color(0xFF0047BB),
        title: Text(
          _scenario.name,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Name
          Text(
            _scenario.name,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 16),

          // Covers: single or carousel
          if (_scenario.covers.length > 1)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: coverMaxHeight),
              child: PageView.builder(
                itemCount: _scenario.covers.length,
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Center(
                      child: AvifImage.asset(
                        _scenario.covers[index],
                        fit: BoxFit.scaleDown,
                      ),
                    ),
                  );
                },
              ),
            )
          else if (_scenario.covers.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: coverMaxHeight),
                child: Center(
                  child: AvifImage.asset(
                    _scenario.covers.first,
                    fit: BoxFit.scaleDown,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Description
          if (_scenario.description.isNotEmpty)
            _DescriptionTile(text: _scenario.description),

          // Collapsible sections (images stacked vertically above text)
          for (final s in _scenario.sections) _ScenarioSectionTile(section: s),

          // Related equipment (expanded by default)
          if (_scenario.related.isNotEmpty)
            ExpansionTile(
              initiallyExpanded: true,
              title: Text(
                'Related equipment',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              childrenPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              children: [_RelatedGrid(ids: _scenario.related)],
            ),
        ],
      ),
    );
  }
}

class _DescriptionTile extends StatelessWidget {
  final String text;
  const _DescriptionTile({required this.text});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text('About', style: Theme.of(context).textTheme.titleMedium),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.start,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ScenarioSectionTile extends StatelessWidget {
  final ScenarioSection section;
  const _ScenarioSectionTile({required this.section});

  static const double _maxImageHeight = 360;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(
        section.title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final img in section.images) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxImageHeight),
              child: Center(child: AvifImage.asset(img, fit: BoxFit.scaleDown)),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            section.body,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.start,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _RelatedGrid extends StatelessWidget {
  final List<String> ids;
  const _RelatedGrid({required this.ids});

  @override
  Widget build(BuildContext context) {
    final repo = DataRepository();
    final all = repo.getAllEquipment();

    final List<Equipment> items = [];
    for (final id in ids) {
      final match = all.where((e) => e.id == id);
      if (match.isNotEmpty) items.add(match.first); // skip if not found
    }

    final width = MediaQuery.of(context).size.width;
    final cols = (width / 180).clamp(2, 5).toInt();

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 3 / 4,
      ),
      itemBuilder: (context, i) {
        final e = items[i];
        final cover = e.coverImages.isNotEmpty ? e.coverImages.first : '';
        return InkWell(
          onTap: () => context.push('/learn/equip/${e.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: cover.isNotEmpty
                      ? AvifImage.asset(cover, fit: BoxFit.cover)
                      : const ColoredBox(color: Color(0xFFE0E0E0)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                e.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontVariations: [FontVariation('wght', 500)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
