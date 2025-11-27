import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/learn_videography_model.dart';

class VideographyDetailPage extends StatefulWidget {
  final String itemID;
  const VideographyDetailPage({super.key, required this.itemID});

  @override
  State<VideographyDetailPage> createState() => _VideographyDetailPageState();
}

class _VideographyDetailPageState extends State<VideographyDetailPage> {
  late final VideographyGuide _guide;

  @override
  void initState() {
    super.initState();
    final guide = DataRepository().getVideographyGuide(widget.itemID);
    if (guide == null) {
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
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 16),

          // Main Cover images: carousel or single
          if (_guide.coverImages.length > 1)
            _ImageCarousel(images: _guide.coverImages, height: 500)
          else if (_guide.coverImages.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AvifImage.asset(
                _guide.coverImages.first,
                fit: BoxFit.scaleDown,
              ),
            ),
          const SizedBox(height: 24),

          // Sections
          for (var section in _guide.sections) _SectionTile(section: section),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final GuideSection section;
  const _SectionTile({required this.section});

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
        // Section images: carousel if multiple
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

        // Section body text
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
