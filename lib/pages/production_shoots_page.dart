// PixelVault — Production Shoots page.
//
// Displays a responsive grid of production shoot cards. Each card shows
// the shoot name and the number of equipment items in its list. Tapping
// a card navigates to the shoot's equipment detail page.
//
// An "Add" button in the app bar opens a dialog that prompts for a shoot
// name, creates it via [DataRepository.createShoot], and navigates to
// the newly created shoot's detail page.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:go_router/go_router.dart';

import '../services/data_repository.dart';
import '../services/production_shoots_client.dart';

const Color _kBrandBlue = Color(0xFF0047BB);

class ProductionShootsPage extends StatefulWidget {
  const ProductionShootsPage({super.key});

  @override
  State<ProductionShootsPage> createState() => _ProductionShootsPageState();
}

class _ProductionShootsPageState extends State<ProductionShootsPage> {
  Map<String, Map<String, ShootEquip>> _shoots = {};

  @override
  void initState() {
    super.initState();
    _shoots = Map.from(DataRepository().getAllShoots());
    DataRepository().shootsEpoch.addListener(_onShootsChanged);
  }

  @override
  void dispose() {
    DataRepository().shootsEpoch.removeListener(_onShootsChanged);
    super.dispose();
  }

  void _onShootsChanged() {
    if (!mounted) return;
    setState(() {
      _shoots = Map.from(DataRepository().getAllShoots());
    });
  }

  Future<void> _showAddShootDialog() async {
    final controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'New Production Shoot',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter shoot name',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white38),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _kBrandBlue),
            ),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.of(ctx).pop(v);
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || name == null || name.isEmpty) return;

    try {
      await DataRepository().createShoot(name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create shoot: $e')));
    }
  }

  Future<void> _showRenameDialog(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final String? newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'Rename Shoot',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter new name',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white38),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _kBrandBlue),
            ),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty && v.trim() != oldName) {
              Navigator.of(ctx).pop(v.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty && v != oldName) Navigator.of(ctx).pop(v);
            },
            child: const Text('Rename', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || newName == null || newName.isEmpty) return;

    try {
      await DataRepository().renameShoot(oldName, newName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to rename: $e')));
    }
  }

  Future<void> _confirmDeleteShoot(String name) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'Delete Shoot?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "$name"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    try {
      await DataRepository().deleteShoot(name);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Shoot deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final int cols = math.max(2, (width / 300).floor());
    final names = _shoots.keys.toList()..sort();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background gradient
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

          // Ambient blobs
          Positioned(
            top: -150,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                color: _kBrandBlue.withValues(alpha: 0.3),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 150,
                    color: _kBrandBlue.withValues(alpha: 0.3),
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

          // Foreground
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
                      title: const Text(
                        'Production Shoots',
                        style: TextStyle(
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
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    tooltip: 'New Shoot',
                    onPressed: _showAddShootDialog,
                  ),
                ],
              ),

              // Grid of shoot cards
              if (names.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No production shoots yet.\nTap + to create one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final name = names[index];
                      final items = _shoots[name] ?? {};
                      final repo = DataRepository();
                      final List<String> coverImages = [];
                      for (final id in items.keys) {
                        if (coverImages.length >= 4) break;
                        final equip = repo.getEquipmentById(id);
                        if (equip != null && equip.coverImages.isNotEmpty) {
                          coverImages.add(equip.coverImages.first);
                        }
                      }
                      final allChecked =
                          items.isNotEmpty &&
                          items.values.every((e) => e.checked);
                      return _ShootCard(
                        name: name,
                        itemCount: items.length,
                        allChecked: allChecked,
                        coverImages: coverImages,
                        onTap: () => context.push(
                          '/shoots/${Uri.encodeComponent(name)}',
                        ),
                        onRename: () => _showRenameDialog(name),
                        onDelete: () => _confirmDeleteShoot(name),
                      );
                    }, childCount: names.length),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShootCard extends StatelessWidget {
  final String name;
  final int itemCount;
  final bool allChecked;
  final List<String> coverImages;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ShootCard({
    required this.name,
    required this.itemCount,
    this.allChecked = false,
    required this.coverImages,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // Photo collage background (up to 4 images in a 2x2 grid)
          if (coverImages.isNotEmpty)
            Positioned.fill(child: _PhotoCollage(images: coverImages))
          else
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),

          // Darkening gradient for text legibility
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.7),
                    Colors.black.withValues(alpha: 0.9),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),

          // Ripple + border
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: InkWell(
                onTap: onTap,
                splashColor: _kBrandBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Foreground content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$itemCount item${itemCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (allChecked) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.greenAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.greenAccent,
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Ready',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: Colors.white70,
                        size: 22,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.grey.shade900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) {
                        if (value == 'rename') onRename();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Colors.white70, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Rename',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Delete',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a 2×2 photo collage from up to 4 image paths.
/// - 1 image: full bleed
/// - 2 images: side by side
/// - 3 images: left full-height + two stacked on right
/// - 4 images: 2×2 grid
class _PhotoCollage extends StatelessWidget {
  final List<String> images;
  const _PhotoCollage({required this.images});

  Widget _tile(String path) {
    return AvifImage.network(
      DataRepository().imageUrl(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: Colors.grey.shade800),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double gap = 1.5;

    if (images.length == 1) {
      return _tile(images[0]);
    }

    if (images.length == 2) {
      return Row(
        children: [
          Expanded(child: _tile(images[0])),
          const SizedBox(width: gap),
          Expanded(child: _tile(images[1])),
        ],
      );
    }

    if (images.length == 3) {
      return Row(
        children: [
          Expanded(child: _tile(images[0])),
          const SizedBox(width: gap),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _tile(images[1])),
                const SizedBox(height: gap),
                Expanded(child: _tile(images[2])),
              ],
            ),
          ),
        ],
      );
    }

    // 4 images — 2×2
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _tile(images[0])),
              const SizedBox(width: gap),
              Expanded(child: _tile(images[1])),
            ],
          ),
        ),
        const SizedBox(height: gap),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _tile(images[2])),
              const SizedBox(width: gap),
              Expanded(child: _tile(images[3])),
            ],
          ),
        ),
      ],
    );
  }
}
