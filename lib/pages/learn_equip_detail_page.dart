import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/data_repository.dart';
import '../models/equipment_model.dart';

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
    final all = DataRepository().getAllEquipment();
    _equip = all.firstWhere(
      (e) => e.id == widget.itemID,
      orElse: () => throw Exception('Equipment not found: ${widget.itemID}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0047BB);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF001F54), // Dark Blue
                  Color(0xFF0047BB), // NLB Blue
                  Color(0xFFFF8200), // NLB Orange
                  Color(0xFFE80029), // NLB Red
                ],
                stops: [0.0, 0.3, 0.7, 1.0],
              ),
            ),
          ),

          // 2. Background Blobs
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
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 150,
                    color: Colors.orange.withValues(alpha: 0.2),
                  ),
                ],
              ),
            ),
          ),

          // 3. Content
          CustomScrollView(
            slivers: [
              // Glass AppBar
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
                        _equip.name,
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
                          _equip.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 16),

                        // Cover Image / Carousel (Centered)
                        if (_equip.coverImages.length > 1)
                          Center(
                            child: _ImageCarousel(
                              images: _equip.coverImages,
                              height: 500,
                            ),
                          )
                        else if (_equip.coverImages.isNotEmpty)
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 500,
                                ),
                                child: AvifImage.asset(
                                  _equip.coverImages.first,
                                  fit: BoxFit.scaleDown,
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 24),

                        // Description
                        if (_equip.description.isNotEmpty)
                          _GlassContainer(
                            child: _DescriptionTile(text: _equip.description),
                          ),

                        const SizedBox(height: 16),

                        // Sections
                        for (final s in _equip.sections) ...[
                          _GlassContainer(child: _EquipSectionTile(section: s)),
                          const SizedBox(height: 16),
                        ],

                        // Related
                        if (_equip.related.isNotEmpty)
                          _GlassContainer(
                            child: ExpansionTile(
                              initiallyExpanded: true,
                              title: const Text(
                                'Related equipment',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              iconColor: Colors.white,
                              collapsedIconColor: Colors.white70,
                              childrenPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              children: [_RelatedGrid(ids: _equip.related)],
                            ),
                          ),
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
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: child,
        ),
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
      title: const Text(
        'About',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      iconColor: Colors.white,
      collapsedIconColor: Colors.white70,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _StyledText(
            text: text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.5,
            ),
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
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      iconColor: Colors.white,
      collapsedIconColor: Colors.white70,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
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
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _maxImageHeight),
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.5,
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
              // Navigation Buttons
              if (_current > 0)
                Positioned(
                  left: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => _controller.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
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
                      onPressed: () => _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
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
                      : Container(color: Colors.white10),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                e.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
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
    final RegExp pattern = RegExp(
      r'(\[([^\]]+)\]\(([^)]+)\))|(\*\*(.*?)\*\*)|(\*(.*?)\*)',
    );

    Future<void> openLink(String rawUrl) async {
      final trimmed = rawUrl.trim();
      final normalized =
          (trimmed.startsWith('http://') || trimmed.startsWith('https://'))
          ? trimmed
          : 'https://$trimmed';
      final uri = Uri.tryParse(normalized);
      if (uri == null) return;
      await launchUrl(uri, webOnlyWindowName: '_blank');
    }

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
        // Link: [text](url)
        if (match.group(1) != null) {
          final linkText = match.group(2) ?? '';
          final linkUrl = match.group(3) ?? '';

          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => openLink(linkUrl),
                  child: Text(
                    linkText,
                    style: outlineStyle.copyWith(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.blue, // force underline color
                      decorationThickness: 2.0, // make it visibly “link-like”
                      decorationStyle: TextDecorationStyle.solid,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        // Bold: **text**
        else if (match.group(4) != null) {
          children.add(
            TextSpan(
              text: match.group(5),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }
        // Italic: *text*
        else if (match.group(6) != null) {
          children.add(
            TextSpan(
              text: match.group(7),
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
