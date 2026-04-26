// PixelVault — Production scenario detail page.
//
// Shows the full guide for a single production scenario, loaded by id
// from [DataRepository] in initState and cached in [_scenario]. The
// page lays out, top to bottom:
//
//   • Title
//   • Cover image or multi-image [_ImageCarousel]
//   • Description ("About") in a glass card
//   • Zero or more content sections, each in its own glass card
//   • A "Related equipment" grid when the YAML declares related ids
//
// The body text supports a tiny inline markdown subset handled by
// [_StyledText]: `**bold**`, `*italic*`, and `[label](url)` links.

import 'dart:ui'; // For ImageFilter used by BackdropFilter.

import 'package:flutter/material.dart';
import '../widgets/smart_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/equipment_model.dart';
import '../models/scenario_model.dart';
import '../services/data_repository.dart';
import '../widgets/admin_auth.dart';
import '../widgets/pending_changes_fab.dart' show ensureNoPendingChangeFor;
import 'guide_creator_page.dart';

class ScenarioDetailPage extends StatefulWidget {
  final String id;
  const ScenarioDetailPage({super.key, required this.id});

  @override
  State<ScenarioDetailPage> createState() => _ScenarioDetailPageState();
}

class _ScenarioDetailPageState extends State<ScenarioDetailPage> {
  /// The resolved scenario record for [widget.id]. Looked up once in
  /// [initState] so the build method stays pure.
  late final ScenarioGuide _scenario;

  @override
  void initState() {
    super.initState();
    // Throws on missing id rather than silently rendering a blank page —
    // routing should never produce an unknown id, so surface the bug
    // loudly if it happens.
    final s = DataRepository().getScenario(widget.id);
    if (s == null) {
      throw Exception('Scenario not found: ${widget.id}');
    }
    _scenario = s;
  }

  Future<void> _handleAdminToggle() async {
    final isAdmin = adminNotifier.value;
    if (isAdmin) {
      final bool? shouldExit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text('Exit Admin Mode?',
              style: TextStyle(color: Colors.white)),
          content: const Text('Are you sure you want to return to user mode?',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Exit',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (shouldExit == true) setAdminPersisted(false);
      return;
    }

    final bool success = await showAdminPasswordDialog(context);
    if (!mounted) return;
    if (success) {
      setAdminPersisted(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin Mode Enabled')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cap for the cover carousel height so a huge asset can't push the
    // description card below the fold on phones.
    const double coverMaxHeight = 360;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 1. Background gradient ──────────────────────────────
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

          // ── 2. Ambient purple blob ──────────────────────────────
          // Matches the scenario section's accent colour on the home
          // page and scenario list page.
          Positioned(
            bottom: -100,
            left: -50,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.3),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 120,
                    color: Colors.purple.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),

          // ── 3. Foreground content ──────────────────────────────
          CustomScrollView(
            slivers: [
              // Frosted pinned app bar showing the scenario name.
              SliverAppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                actions: [
                  ValueListenableBuilder<bool>(
                    valueListenable: adminNotifier,
                    builder: (_, isAdmin, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isAdmin)
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white),
                            onPressed: () {
                              if (!ensureNoPendingChangeFor(
                                  context, _scenario.id)) {
                                return;
                              }
                              showGuideEditor(
                                context,
                                GuideType.scenario,
                                GuideEditData(
                                  name: _scenario.name,
                                  coverImages: _scenario.coverImages,
                                  sections: _scenario.sections
                                      .map((s) => (
                                            title: s.title,
                                            body: s.body,
                                            images: s.images,
                                          ))
                                      .toList(),
                                ),
                              );
                            },
                            tooltip: 'Edit Guide',
                          ),
                        IconButton(
                          icon: Icon(
                            isAdmin
                                ? Icons.admin_panel_settings
                                : Icons.person,
                            color: isAdmin ? Colors.green : Colors.white,
                          ),
                          onPressed: _handleAdminToggle,
                          tooltip: 'Admin Mode',
                        ),
                      ],
                    ),
                  ),
                ],
                backgroundColor: Colors.transparent,
                pinned: true,
                flexibleSpace: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: FlexibleSpaceBar(
                      title: Text(
                        _scenario.name,
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
                        // Large title — duplicates the AppBar title so
                        // users scrolling mid-page still see it clearly
                        // above the cover image.
                        Text(
                          _scenario.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                          textAlign: TextAlign.start,
                        ),
                        const SizedBox(height: 16),

                        // Cover image(s) — carousel when the YAML lists
                        // more than one cover, otherwise a single image.
                        if (_scenario.coverImages.length > 1)
                          Center(
                            child: _ImageCarousel(
                              images: _scenario.coverImages,
                              height: coverMaxHeight,
                            ),
                          )
                        else if (_scenario.coverImages.isNotEmpty)
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: coverMaxHeight,
                                ),
                                child: Center(
                                  child: SmartImage.network(
                                    DataRepository().imageUrl(_scenario.coverImages.first),
                                    fit: BoxFit.scaleDown,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 24),

                        // Description card (only when non-empty).
                        if (_scenario.description.isNotEmpty)
                          _GlassContainer(
                            child: _DescriptionTile(
                              text: _scenario.description,
                            ),
                          ),

                        const SizedBox(height: 16),

                        // Content sections, each in its own glass card.
                        for (final s in _scenario.sections) ...[
                          _GlassContainer(
                            child: _ScenarioSectionTile(section: s),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Related equipment grid (only when the YAML
                        // declares related ids).
                        if (_scenario.related.isNotEmpty)
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
                              children: [_RelatedGrid(ids: _scenario.related)],
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

/// Rounded, blurred, semi-transparent container used to host each
/// content block. The blur is what gives the card the "frosted glass"
/// look over the gradient background.
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Expansion tile rendering the scenario's "About" description text.
/// Starts expanded because the description is the primary content on
/// most scenarios.
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

/// Expansion tile for a single [ScenarioSection]. Renders the section's
/// images (carousel or single) above the body text. Starts collapsed
/// so long guides don't dump everything at once.
class _ScenarioSectionTile extends StatelessWidget {
  final ScenarioSection section;
  const _ScenarioSectionTile({required this.section});

  /// Shared cap for inline section images so a huge asset can't blow
  /// out the layout; the image still scales down to fit naturally.
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
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _maxImageHeight),
                child: Center(
                  child: SmartImage.network(
                    DataRepository().imageUrl(section.images.first),
                    fit: BoxFit.scaleDown,
                  ),
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

/// PageView-backed image carousel with prev/next arrows and tappable
/// dot indicators. Used by both the cover section and the per-section
/// tiles whenever the scenario lists more than one image.
class _ImageCarousel extends StatefulWidget {
  final List<String> images;
  final double height;

  const _ImageCarousel({required this.images, required this.height});

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  final PageController _controller = PageController();
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

  /// Jump to a specific page — used by the dot indicators below the
  /// carousel so users can tap a dot to land on that image directly.
  void _goToPage(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SmartImage.network(
                        DataRepository().imageUrl(widget.images[index]),
                        fit: BoxFit.scaleDown,
                      ),
                    ),
                  );
                },
              ),

              // Prev / next chevrons — only rendered when there is
              // actually a page to move to in that direction.
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

        // Tappable page dots. Current page is fully opaque; the rest
        // render at reduced opacity.
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
                  color: Colors.white.withValues(
                    alpha: _current == entry.key ? 1.0 : 0.4,
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

/// Small responsive grid of related-equipment thumbnails. Resolves the
/// id list against the full equipment catalogue so unknown ids are
/// silently skipped rather than crashing the page.
class _RelatedGrid extends StatelessWidget {
  final List<String> ids;
  const _RelatedGrid({required this.ids});

  @override
  Widget build(BuildContext context) {
    final all = DataRepository().getAllEquipment();

    // Resolve the id list into Equipment objects, skipping ids that
    // don't match anything in the catalogue.
    final List<Equipment> items = [];
    for (final id in ids) {
      final match = all.where((e) => e.id == id);
      if (match.isNotEmpty) items.add(match.first);
    }

    // Column count scales with page width, clamped between 2 and 5 so
    // the thumbnails never get too tall or too thin.
    final double width = MediaQuery.of(context).size.width;
    final int cols = (width / 180).clamp(2, 5).toInt();

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
        final String cover = e.coverImages.isNotEmpty
            ? e.coverImages.first
            : '';
        return InkWell(
          onTap: () => context.push('/learn/equip-guides/${e.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: cover.isNotEmpty
                      ? SmartImage.network(DataRepository().imageUrl(cover), fit: BoxFit.cover)
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

/// Minimal inline markdown renderer for body text. Supports exactly
/// three constructs, handled by a single regex with alternation:
///
///   • `[label](url)`  — tappable link, opened via url_launcher
///   • `**bold**`      — bold text span
///   • `*italic*`      — italic text span
///
/// Anything else is emitted as a plain text span. Every span inherits
/// a subtle black text shadow so body text stays legible against the
/// variable-brightness gradient background.
class _StyledText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _StyledText({required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> children = [];
    final RegExp pattern = RegExp(
      r'(\[([^\]]+)\]\(([^)]+)\))|(\*\*(.*?)\*\*)|(\*(.*?)\*)',
    );

    // Open a link in a new tab on web / the default handler elsewhere.
    // Missing schemes are normalized to https:// so bare `example.com`
    // entries in YAML still work.
    Future<void> openLink(String rawUrl) async {
      final String trimmed = rawUrl.trim();
      final String normalized =
          (trimmed.startsWith('http://') || trimmed.startsWith('https://'))
          ? trimmed
          : 'https://$trimmed';
      final Uri? uri = Uri.tryParse(normalized);
      if (uri == null) return;
      await launchUrl(uri, webOnlyWindowName: '_blank');
    }

    // Base style gets a black drop-shadow outline for legibility over
    // the bright gradient background.
    final TextStyle outlineStyle =
        style?.copyWith(
          shadows: [
            Shadow(
              offset: const Offset(1.0, 1.0),
              blurRadius: 2.0,
              color: Colors.black.withValues(alpha: 0.8),
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

    // splitMapJoin walks the string, calling onMatch for every regex
    // hit and onNonMatch for the text between matches — the return
    // values are discarded because we accumulate into `children`.
    text.splitMapJoin(
      pattern,
      onMatch: (Match match) {
        // Group 1: full link construct `[text](url)`.
        if (match.group(1) != null) {
          final String linkText = match.group(2) ?? '';
          final String linkUrl = match.group(3) ?? '';
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
                      decorationColor: Colors.blue,
                      decorationThickness: 2.0,
                      decorationStyle: TextDecorationStyle.solid,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        // Group 4: `**bold**`.
        else if (match.group(4) != null) {
          children.add(
            TextSpan(
              text: match.group(5),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }
        // Group 6: `*italic*`.
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
      textAlign: TextAlign.start,
    );
  }
}
