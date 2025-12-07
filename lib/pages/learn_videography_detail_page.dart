import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';

import '../services/data_repository.dart';
import '../models/videography_model.dart';

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
    const brandBlue = Color(0xFF0047BB);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF001F54),
                  Color(0xFF0047BB),
                  Color(0xFFFF8200),
                  Color(0xFFE80029),
                ],
                stops: [0.0, 0.3, 0.7, 1.0],
              ),
            ),
          ),
          // 2. Blobs
          Positioned(
            top: -150,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                color: brandBlue.withValues(alpha: 0.3),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 150,
                    color: brandBlue.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),

          // 3. Content
          CustomScrollView(
            slivers: [
              SliverAppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                backgroundColor: Colors.transparent,
                pinned: true,
                flexibleSpace: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: FlexibleSpaceBar(
                      title: Text(
                        _guide.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      background: Container(
                        color: Colors.black.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          _guide.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                          textAlign: TextAlign.start,
                        ),
                        const SizedBox(height: 16),

                        // Main Cover images
                        if (_guide.coverImages.length > 1)
                          Center(
                            child: _ImageCarousel(
                              images: _guide.coverImages,
                              height: 500,
                            ),
                          )
                        else if (_guide.coverImages.isNotEmpty)
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AvifImage.asset(
                                _guide.coverImages.first,
                                fit: BoxFit.scaleDown,
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),

                        // Sections
                        for (var section in _guide.sections) ...[
                          _GlassContainer(
                            child: _SectionTile(section: section),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassContainer extends StatelessWidget {
  final Widget child;
  const _GlassContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: child,
        ),
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
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      iconColor: Colors.white,
      collapsedIconColor: Colors.white70,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Section images: carousel if multiple
        if (section.images.length > 1)
          Center(
            child: _ImageCarousel(
              images: section.images,
              height: _maxImageHeight,
            ),
          )
        else if (section.images.isNotEmpty)
          Center(
            child: ClipRRect(
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
          ),

        if (section.images.isNotEmpty) const SizedBox(height: 12),

        // Section body text
        Align(
          alignment: Alignment.centerLeft,
          child: _StyledText(
            text: section.body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.4,
            ),
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
                  return Center(
                    // Center image within page view
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AvifImage.asset(
                        widget.images[index],
                        fit: BoxFit.scaleDown,
                      ),
                    ),
                  );
                },
              ),
              if (_current > 0)
                Positioned(
                  left: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: _previous,
                      tooltip: 'Previous Image',
                    ),
                  ),
                ),
              if (_current < widget.images.length - 1)
                Positioned(
                  right: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_forward,
                        color: Colors.black,
                      ),
                      onPressed: _next,
                      tooltip: 'Next Image',
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Interactive Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: widget.images.asMap().entries.map((entry) {
            return GestureDetector(
              onTap: () => _goToPage(entry.key),
              child: Container(
                width: 10.0,
                height: 10.0,
                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(
                    _current == entry.key ? 0.9 : 0.3,
                  ),
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

    // Text outline style for better readability
    final outlineStyle =
        style?.copyWith(
          shadows: [
            Shadow(
              offset: const Offset(1.0, 1.0),
              blurRadius: 2.0,
              color: Colors.black.withOpacity(0.8),
            ),
          ],
        ) ??
        const TextStyle(
          shadows: [
            Shadow(
              offset: Offset(1.0, 1.0),
              blurRadius: 2.0,
              color: Colors.black,
            ),
          ],
        );

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
      TextSpan(style: outlineStyle, children: children),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
