// PixelVault — Production Shoot detail page.
//
// Shows the equipment list for a single production shoot, grouped into
// collapsible category sections. Each row has a checkbox (for strikethrough),
// equipment name, quantity/brand/storage tags, and an info button that
// opens a popup with the equipment photo and details.
//
// An "Add" button at the top opens a multi-select equipment picker dialog.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/smart_image.dart';
import 'package:go_router/go_router.dart';

import '../models/equipment_model.dart';
import '../services/data_repository.dart';
import '../services/production_shoots_client.dart';
import 'production_shoot_add_dialog.dart';

const Color _kBrandBlue = Color(0xFF0047BB);

class ProductionShootDetailPage extends StatefulWidget {
  final String shootName;
  const ProductionShootDetailPage({super.key, required this.shootName});

  @override
  State<ProductionShootDetailPage> createState() =>
      _ProductionShootDetailPageState();
}

class _ProductionShootDetailPageState extends State<ProductionShootDetailPage> {
  Map<String, ShootEquip> _items = {}; // equipId -> ShootEquip
  final Set<String> _collapsedCategories = {};
  bool _exiting = false; // Guard against double-pop on rapid epoch ticks.

  @override
  void initState() {
    super.initState();
    _items = Map.from(DataRepository().getShoot(widget.shootName) ?? {});
    DataRepository().shootsEpoch.addListener(_onChanged);
  }

  @override
  void dispose() {
    DataRepository().shootsEpoch.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted || _exiting) return;
    final shoot = DataRepository().getShoot(widget.shootName);
    if (shoot == null) {
      // Shoot was renamed or deleted by another user — go back.
      _exiting = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This shoot was renamed or deleted by another user.'),
        ),
      );
      context.pop();
      return;
    }
    setState(() {
      _items = Map.from(shoot);
    });
  }

  Future<void> _toggleCheck(String equipId, bool checked) async {
    try {
      await DataRepository().toggleShootEquipCheck(
        widget.shootName,
        equipId,
        checked,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  Future<void> _openAddDialog() async {
    final alreadyAdded = _items.keys.toSet();
    final Map<String, int>? result = await showDialog<Map<String, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductionShootAddDialog(
        alreadyAdded: alreadyAdded,
        shootName: widget.shootName,
      ),
    );

    if (!mounted || result == null || result.isEmpty) return;

    try {
      await DataRepository().addEquipmentToShoot(widget.shootName, result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${result.length} item${result.length == 1 ? '' : 's'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
    }
  }

  Future<void> _removeEquipment(String equipId, String equipName) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'Remove Item?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove "$equipName" from this shoot?',
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
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    try {
      await DataRepository().removeEquipmentFromShoot(
        widget.shootName,
        equipId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove: $e')));
    }
  }

  void _showEquipmentInfo(Equipment equip) {
    final shootEquip = _items[equip.id];
    final currentQty = shootEquip?.qty ?? 1;
    showDialog(
      context: context,
      builder: (ctx) => _EquipmentInfoPopup(
        equipment: equip,
        currentBringQty: currentQty,
        shootName: widget.shootName,
        onRemove: () {
          Navigator.of(ctx).pop();
          _removeEquipment(equip.id, equip.name);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = DataRepository();

    // Resolve equipment objects and group by category. Custom items
    // (ids starting with "custom_") don't exist in the catalog — we
    // build a minimal Equipment placeholder for them using the name
    // stored in ShootEquip.
    final Map<String, List<MapEntry<Equipment, ShootEquip>>> byCategory = {};
    final sortedIds = _items.keys.toList()..sort();
    for (final id in sortedIds) {
      final shootEquip = _items[id] ?? ShootEquip();
      Equipment? equip = repo.getEquipmentById(id);
      if (equip == null &&
          id.startsWith('custom_') &&
          shootEquip.name != null) {
        equip = Equipment(
          id: id,
          name: shootEquip.name!,
          category: 'Custom',
          brand: '',
          coverImages: const [],
          description: '',
          sections: const [],
          related: const [],
        );
      }
      if (equip == null) continue;
      final cat = equip.category.isNotEmpty ? equip.category : 'Other';
      byCategory.putIfAbsent(cat, () => []);
      byCategory[cat]!.add(MapEntry(equip, shootEquip));
    }
    final categoryNames = byCategory.keys.toList()..sort();

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
                      title: Text(
                        widget.shootName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
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
                    tooltip: 'Add Equipment',
                    onPressed: _openAddDialog,
                  ),
                ],
              ),

              if (_items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No equipment added yet.\nTap + to add equipment.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ),
                )
              else ...[
                // Progress counter
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Builder(
                      builder: (_) {
                        final total = _items.length;
                        final checked = _items.values
                            .where((v) => v.checked)
                            .length;
                        final left = total - checked;
                        final allDone = left == 0;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: allDone
                                  ? Colors.green.withValues(alpha: 0.25)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: allDone
                                    ? Colors.greenAccent
                                    : Colors.white.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              '$left/$total Left',
                              style: TextStyle(
                                color: allDone
                                    ? Colors.greenAccent
                                    : Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 8),
                    for (final cat in categoryNames) ...[
                      // Category header
                      _CategoryHeader(
                        category: cat,
                        entries: byCategory[cat]!,
                        isCollapsed: _collapsedCategories.contains(cat),
                        onToggle: () {
                          setState(() {
                            if (_collapsedCategories.contains(cat)) {
                              _collapsedCategories.remove(cat);
                            } else {
                              _collapsedCategories.add(cat);
                            }
                          });
                        },
                      ),
                      // Equipment rows (if not collapsed)
                      if (!_collapsedCategories.contains(cat))
                        for (final entry in byCategory[cat]!)
                          _EquipmentRow(
                            equipment: entry.key,
                            checked: entry.value.checked,
                            bringQty: entry.value.qty,
                            onCheckChanged: (v) =>
                                _toggleCheck(entry.key.id, v),
                            onInfoTap: () => _showEquipmentInfo(entry.key),
                            onRemove: () =>
                                _removeEquipment(entry.key.id, entry.key.name),
                          ),
                    ],
                    const SizedBox(height: 24),
                  ]),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Category header ──────────────────────────────────────────────────

class _CategoryHeader extends StatelessWidget {
  final String category;
  final List<MapEntry<Equipment, ShootEquip>> entries;
  final bool isCollapsed;
  final VoidCallback onToggle;

  const _CategoryHeader({
    required this.category,
    required this.entries,
    required this.isCollapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final total = entries.length;
    final checked = entries.where((e) => e.value.checked).length;
    final left = total - checked;
    final allDone = left == 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCollapsed
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    color: Colors.white70,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    category,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: allDone
                          ? Colors.green.withValues(alpha: 0.25)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: allDone
                            ? Colors.greenAccent
                            : Colors.white.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '$left/$total Left',
                      style: TextStyle(
                        color: allDone ? Colors.greenAccent : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Equipment row ────────────────────────────────────────────────────

class _EquipmentRow extends StatelessWidget {
  final Equipment equipment;
  final bool checked;
  final int bringQty;
  final ValueChanged<bool> onCheckChanged;
  final VoidCallback onInfoTap;
  final VoidCallback onRemove;

  const _EquipmentRow({
    required this.equipment,
    required this.checked,
    this.bringQty = 1,
    required this.onCheckChanged,
    required this.onInfoTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final int qty = equipment.quantity ?? 0;
    final bool isCustom = equipment.id.startsWith('custom_');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                // Checkbox
                Checkbox(
                  value: checked,
                  onChanged: (v) => onCheckChanged(v ?? false),
                  activeColor: _kBrandBlue,
                  checkColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),

                // Equipment info (left side)
                Expanded(
                  child: GestureDetector(
                    onLongPress: onRemove,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Equipment name with optional strikethrough
                        Text(
                          equipment.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: checked ? Colors.white38 : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            decoration: checked
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            decorationColor: Colors.white38,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Tags row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _Tag(label: 'Need: $bringQty', color: Colors.cyan),
                            if (isCustom)
                              const _Tag(label: 'Custom', color: Colors.purple)
                            else ...[
                              _Tag(
                                label: 'Stock: $qty',
                                color: qty > 0 ? Colors.green : Colors.red,
                              ),
                              _Tag(
                                label: equipment.brand,
                                color: Colors.lightBlueAccent,
                              ),
                              if (equipment.storage != null &&
                                  equipment.storage!.isNotEmpty)
                                _Tag(
                                  label: 'Storage: ${equipment.storage}',
                                  color: Colors.orange,
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Info button (right side)
                IconButton(
                  icon: const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: onInfoTap,
                  tooltip: 'View details',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Colored tag chip ─────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 1)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color == Colors.green
              ? Colors.greenAccent
              : color == Colors.red
              ? Colors.redAccent
              : color == Colors.orange
              ? Colors.amber.shade200
              : color == Colors.cyan
              ? Colors.cyanAccent
              : color == Colors.lightBlueAccent
              ? const Color.fromARGB(255, 192, 233, 251)
              : color == Colors.purple
              ? Colors.purple.shade100
              : Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Equipment info popup ─────────────────────────────────────────────

class _EquipmentInfoPopup extends StatefulWidget {
  final Equipment equipment;
  final int currentBringQty;
  final String shootName;
  final VoidCallback onRemove;

  const _EquipmentInfoPopup({
    required this.equipment,
    required this.currentBringQty,
    required this.shootName,
    required this.onRemove,
  });

  @override
  State<_EquipmentInfoPopup> createState() => _EquipmentInfoPopupState();
}

class _EquipmentInfoPopupState extends State<_EquipmentInfoPopup> {
  late int _bringQty;
  late int _originalQty;

  bool get _qtyChanged => _bringQty != _originalQty;

  bool get _isCustom => widget.equipment.id.startsWith('custom_');

  int get _maxQty {
    // Custom items have no stock concept — allow any reasonable qty.
    if (_isCustom) return 999;
    final stock = widget.equipment.quantity ?? 1;
    return stock < 1 ? 1 : stock;
  }

  @override
  void initState() {
    super.initState();
    _originalQty = widget.currentBringQty;
    _bringQty = widget.currentBringQty;
  }

  void _adjustQty(int delta) {
    setState(() {
      _bringQty = (_bringQty + delta).clamp(1, _maxQty);
    });
  }

  void _showFullImage(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SmartImage.network(
              DataRepository().imageUrl(imagePath),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Container(
                color: Colors.grey.shade800,
                child: const Icon(
                  Icons.image_not_supported,
                  color: Colors.white38,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmQtyChange() async {
    try {
      await DataRepository().updateShootEquipQty(
        widget.shootName,
        widget.equipment.id,
        _bringQty,
      );
      if (!mounted) return;
      setState(() => _originalQty = _bringQty);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String imagePath = widget.equipment.coverImages.isNotEmpty
        ? widget.equipment.coverImages.first
        : '';
    final int qty = widget.equipment.quantity ?? 0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            decoration: BoxDecoration(
              color: Colors.grey.shade900.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),

                // Equipment photo (hidden for custom items)
                if (!_isCustom && imagePath.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _showFullImage(context, imagePath),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: SmartImage.network(
                            DataRepository().imageUrl(imagePath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.grey.shade800,
                              child: const Icon(
                                Icons.image_not_supported,
                                color: Colors.white38,
                                size: 48,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Press to view full image',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ] else if (!_isCustom)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.white38,
                        size: 48,
                      ),
                    ),
                  ),

                // Equipment details
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.equipment.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_isCustom)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Custom item',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (!_isCustom) ...[
                        _InfoRow(
                          label: 'Category',
                          value: widget.equipment.category,
                        ),
                        _InfoRow(label: 'Brand', value: widget.equipment.brand),
                        _InfoRow(
                          label: 'Stock',
                          value: qty > 0 ? '$qty' : 'Out of Stock',
                        ),
                        if (widget.equipment.storage != null &&
                            widget.equipment.storage!.isNotEmpty)
                          _InfoRow(
                            label: 'Storage',
                            value: widget.equipment.storage!,
                          ),
                        if (widget.equipment.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            widget.equipment.description,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],

                      // ── Bring qty editor ──────────────────────
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text(
                            'Need to bring:',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // -1 circular button
                          _PopupCircleBtn(
                            icon: Icons.remove,
                            onTap: () => _adjustQty(-1),
                          ),
                          const SizedBox(width: 8),
                          // Editable qty field
                          SizedBox(
                            width: 48,
                            height: 32,
                            child: TextField(
                              controller: TextEditingController(
                                text: '$_bringQty',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                contentPadding: EdgeInsets.zero,
                                filled: true,
                                fillColor: Colors.grey.shade300,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (v) {
                                final parsed = int.tryParse(v) ?? 1;
                                setState(() {
                                  _bringQty = parsed.clamp(1, _maxQty);
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // +1 circular button
                          _PopupCircleBtn(
                            icon: Icons.add,
                            onTap: () => _adjustQty(1),
                          ),
                          const Spacer(),
                          if (_qtyChanged)
                            TextButton(
                              onPressed: () {
                                setState(() => _bringQty = _originalQty);
                              },
                              child: const Text(
                                'Undo',
                                style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),

                      // ── Action buttons ────────────────────────
                      const SizedBox(height: 16),
                      if (_qtyChanged)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: widget.onRemove,
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 18,
                                ),
                                label: const Text('Remove'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: const BorderSide(
                                    color: Colors.redAccent,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _confirmQtyChange,
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('Confirm'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: widget.onRemove,
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 18,
                            ),
                            label: const Text('Remove from Shoot'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Circular +/- button for popup ───────────────────────────────────

class _PopupCircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _PopupCircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
