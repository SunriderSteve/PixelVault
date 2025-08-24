import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/learn_equipment_model.dart';

class EquipDetailPage extends StatefulWidget {
  final String itemID;
  const EquipDetailPage({super.key, required this.itemID});

  @override
  State<EquipDetailPage> createState() => _LearnEquipDetailPageState();
}

class _LearnEquipDetailPageState extends State<EquipDetailPage> {
  late final Equipment _equip;

  @override
  void initState() {
    super.initState();
    // Avoid assuming a repository method name; find by id from the cache.
    final all = DataRepository().getAllEquipment();
    _equip = all.firstWhere(
      (e) => e.id == widget.itemID,
      orElse: () => throw Exception('Equipment not found: ${widget.itemID}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        backgroundColor: const Color(0xFF0047BB),
        title: Text(_equip.name, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Name
          Text(
            _equip.name,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 16),

          // Covers: single or carousel
          if (_equip.coverImages.length > 1)
            SizedBox(
              height: 500,
              child: PageView.builder(
                itemCount: _equip.coverImages.length,
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AvifImage.asset(
                      _equip.coverImages[index],
                      fit: BoxFit.scaleDown,
                    ),
                  );
                },
              ),
            )
          else if (_equip.coverImages.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AvifImage.asset(
                _equip.coverImages.first,
                fit: BoxFit.scaleDown,
              ),
            ),

          const SizedBox(height: 24),

          // Description (as its own expandable section for parity with Videography layout)
          if (_equip.description.isNotEmpty)
            _DescriptionTile(text: _equip.description),

          // Collapsible sections (images stacked vertically above text)
          for (final s in _equip.sections) _EquipSectionTile(section: s),

          // Related equipment grid
          if (_equip.related.isNotEmpty)
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
              children: [_RelatedGrid(ids: _equip.related)],
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

class _EquipSectionTile extends StatelessWidget {
  final EquipSection section;
  const _EquipSectionTile({required this.section});

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

    // responsive columns similar to list pages
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
          onTap: () => context.push('/learn/equip-guides/${e.id}'),
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
                textAlign: TextAlign.start,
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
