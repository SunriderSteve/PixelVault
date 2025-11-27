import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/scenario_model.dart';
import '../models/equipment_model.dart';

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

          // Main coverImages: single or carousel
          if (_scenario.coverImages.length > 1)
            _ImageCarousel(
              images: _scenario.coverImages,
              height: coverMaxHeight,
            )
          else if (_scenario.coverImages.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: coverMaxHeight),
                child: Center(
                  child: AvifImage.asset(
                    _scenario.coverImages.first,
                    fit: BoxFit.scaleDown,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Description
          if (_scenario.description.isNotEmpty)
            _DescriptionTile(text: _scenario.description),

          // Collapsible sections
          for (final s in _scenario.sections) _ScenarioSectionTile(section: s),

          // Related equipment
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
          child: _StyledText(
            text: text,
            style: Theme.of(context).textTheme.bodyMedium,
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
        // Carousel logic
        if (section.images.length > 1)
          _ImageCarousel(images: section.images, height: _maxImageHeight)
        else if (section.images.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxImageHeight),
              child: Center(
                child: AvifImage.asset(
                  section.images.first,
                  fit: BoxFit.scaleDown,
                ),
              ),
            ),
          ),

        if (section.images.isNotEmpty) const SizedBox(height: 12),

        Align(
          alignment: Alignment.centerLeft,
          child: _StyledText(
            text: section.body,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ImageCarousel extends StatefulWidget {
  final List<String> images;
  final double height;

  const _ImageCarousel({required this.images, required this.height});

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  final _controller = PageController();
  int _current = 0;

  void _previous() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goToPage(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.images.length,
                onPageChanged: (idx) => setState(() => _current = idx),
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AvifImage.asset(
                      widget.images[index],
                      fit: BoxFit.scaleDown,
                    ),
                  );
                },
              ),
              // Previous Button (Left)
              if (_current > 0)
                Positioned(
                  left: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.black, // Fully opaque
                    radius: 20,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _previous,
                      tooltip: 'Previous Image',
                    ),
                  ),
                ),
              // Next Button (Right)
              if (_current < widget.images.length - 1)
                Positioned(
                  right: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.black, // Fully opaque
                    radius: 20,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                      ),
                      onPressed: _next,
                      tooltip: 'Next Image',
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: widget.images.asMap().entries.map((entry) {
            return GestureDetector(
              onTap: () => _goToPage(entry.key),
              child: Container(
                width: 12.0,
                height: 12.0,
                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      (Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black)
                          .withOpacity(_current == entry.key ? 0.9 : 0.4),
                ),
              ),
            );
          }).toList(),
        ),
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
      if (match.isNotEmpty) items.add(match.first);
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

class _StyledText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const _StyledText({
    required this.text,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> children = [];
    final RegExp pattern = RegExp(r'(\*\*(.*?)\*\*)|(\*(.*?)\*)');

    text.splitMapJoin(
      pattern,
      onMatch: (Match match) {
        if (match.group(1) != null) {
          children.add(
            TextSpan(
              text: match.group(2),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        } else if (match.group(3) != null) {
          children.add(
            TextSpan(
              text: match.group(4),
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          );
        }
        return '';
      },
      onNonMatch: (String nonMatch) {
        children.add(TextSpan(text: nonMatch));
        return '';
      },
    );

    return Text.rich(
      TextSpan(style: style, children: children),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
