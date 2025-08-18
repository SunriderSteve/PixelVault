import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/learn_videography_model.dart';

class VideographyDetailPage extends StatefulWidget {
  final String itemID;
  const VideographyDetailPage({super.key, required this.itemID});

  @override
  _VideographyDetailPageState createState() => _VideographyDetailPageState();
}

class _VideographyDetailPageState extends State<VideographyDetailPage> {
  late final VideographyGuide _guide;

  @override
  void initState() {
    super.initState();
    final guide = DataRepository().getVideographyGuide(widget.itemID);
    if (guide == null) {
      // In a real app show error or navigate back.
      throw Exception('Guide not found: ${widget.itemID}');
    }
    _guide = guide;
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
        title: Text(_guide.name, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Title
          Text(
            _guide.name,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 16),
          // Cover images carousel or single image
          if (_guide.coverImages.length > 1)
            SizedBox(
              height: 500,
              child: PageView.builder(
                itemCount: _guide.coverImages.length,
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AvifImage.asset(
                      _guide.coverImages[index],
                      fit: BoxFit.scaleDown,
                    ),
                  );
                },
              ),
            )
          else if (_guide.coverImages.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AvifImage.asset(
                _guide.coverImages.first,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 24),
          // Sections as collapsible tiles
          for (var section in _guide.sections) _SectionTile(section: section),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final GuideSection section;
  const _SectionTile({required this.section});

  static const double _maxImageHeight = 360; // cap large section images

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(
        section.title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Section images (size-limited)
        for (var img in section.images) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                // limit height, allow width to follow layout constraints
                maxHeight: _maxImageHeight,
              ),
              child: Center(
                // scale down if too large; never scale up
                child: AvifImage.asset(img, fit: BoxFit.scaleDown),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Section body text
        Text(
          section.body,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
