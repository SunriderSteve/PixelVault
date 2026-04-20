// PixelVault — Add Equipment to Production Shoot dialog.
//
// Two-page flow inside a single dialog:
//   1. Selection page — searchable, filterable equipment grid. Users
//      multi-select items, then tap "Next" to proceed to review.
//   2. Review page — scrollable list of selected items. Each row shows
//      the equipment name, info tags, an adjustable bring-quantity
//      (±1 / ±10 / text input, clamped to 1..stock), and a remove
//      button. Removed items can be restored via "Undo Removal". A
//      back button returns to the selection page with selections intact.
//
// Returns a `Map<String, int>` of { equipId → qty }, or null on cancel.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_avif/flutter_avif.dart';


import '../models/equipment_model.dart';
import '../services/data_repository.dart';

const Color _kBrandBlue = Color(0xFF0047BB);

class ProductionShootAddDialog extends StatefulWidget {
  final Set<String> alreadyAdded;
  final String shootName;

  const ProductionShootAddDialog({
    super.key,
    required this.alreadyAdded,
    required this.shootName,
  });

  @override
  State<ProductionShootAddDialog> createState() =>
      _ProductionShootAddDialogState();
}

class _ProductionShootAddDialogState extends State<ProductionShootAddDialog> {
  // ── Selection page state ──────────────────────────────────────
  final TextEditingController _search = TextEditingController();
  bool _sortAsc = true;
  bool _showFilters = false;
  int _activeTab = 0; // 0 = Category, 1 = Brand
  final Set<String> _selectedCategories = {};
  final Set<String> _selectedBrands = {};

  late final List<Equipment> _all;
  late List<Equipment> _filtered;
  late final List<String> _allCategories;
  late final List<String> _allBrands;

  final Set<String> _selected = {}; // IDs the user has ticked

  // ── Review page state ─────────────────────────────────────────
  bool _onReviewPage = false;
  final Map<String, int> _qtys = {}; // equipId -> bring qty
  final List<String> _removed = []; // removed IDs (for undo)

  @override
  void initState() {
    super.initState();
    _all = List.of(DataRepository().getAllEquipment());
    _allCategories = _all.map((e) => e.category).toSet().toList()..sort();
    _allBrands = _all.map((e) => e.brand).toSet().toList()..sort();
    _filtered = List.of(_all)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _search.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final query = _search.text.toLowerCase();
    setState(() {
      _filtered =
          _all.where((e) {
            final matchesSearch = e.name.toLowerCase().contains(query);
            final matchesCat =
                _selectedCategories.isEmpty ||
                _selectedCategories.contains(e.category);
            final matchesBrand =
                _selectedBrands.isEmpty || _selectedBrands.contains(e.brand);
            return matchesSearch && matchesCat && matchesBrand;
          }).toList()..sort((a, b) {
            final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return _sortAsc ? cmp : -cmp;
          });
    });
  }

  void _goToReview() {
    // Initialise qtys for newly selected items (default 1).
    for (final id in _selected) {
      _qtys.putIfAbsent(id, () => 1);
    }
    // Remove qtys for deselected items.
    _qtys.removeWhere((id, _) => !_selected.contains(id));
    _removed.clear();
    setState(() => _onReviewPage = true);
  }

  void _goBackToSelection() {
    // Restore any removed items back into _selected.
    for (final id in _removed) {
      _selected.add(id);
    }
    _removed.clear();
    setState(() => _onReviewPage = false);
  }

  // ── Read-only equipment info ────────────────────────────────

  void _showReadOnlyInfo(Equipment equip) {
    showDialog(
      context: context,
      builder: (_) => _ReadOnlyEquipmentInfoPopup(equipment: equip),
    );
  }

  // ── Custom item ───────────────────────────────────────────────

  Future<void> _openCustomItemDialog() async {
    final result = await showDialog<_CustomItemResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CustomItemDialog(),
    );

    if (!mounted || result == null) return;

    try {
      await DataRepository().addCustomEquipmentToShoot(
        widget.shootName,
        result.name,
        result.qty,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "${result.name}" to shoot')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add custom item: $e')));
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double dialogWidth = math.min(size.width * 0.92, 800);
    final double dialogHeight = size.height * 0.85;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            decoration: BoxDecoration(
              color: Colors.grey.shade900.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: _onReviewPage
                ? _buildReviewPage()
                : _buildSelectionPage(dialogWidth),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PAGE 1 — Equipment selection grid
  // ══════════════════════════════════════════════════════════════

  Widget _buildSelectionPage(double dialogWidth) {
    final int cols = math.max(2, (dialogWidth / 200).floor());
    final int totalFilters =
        _selectedCategories.length + _selectedBrands.length;

    return Column(
      children: [
        // ── Header ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 8, top: 12),
          child: Row(
            children: [
              const Text(
                'Add Equipment',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        // ── Search bar ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search equipment',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white54,
                        size: 20,
                      ),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Colors.white54,
                                size: 18,
                              ),
                              onPressed: _search.clear,
                            ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: () {
                    _sortAsc = !_sortAsc;
                    _applyFilters();
                  },
                  tooltip: _sortAsc ? 'Sort Z-A' : 'Sort A-Z',
                ),
                GestureDetector(
                  onTap: () => setState(() => _showFilters = !_showFilters),
                  child: Stack(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.filter_alt,
                          color: Colors.white54,
                          size: 22,
                        ),
                      ),
                      if (totalFilters > 0)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: CircleAvatar(
                            radius: 7,
                            backgroundColor: Colors.red,
                            child: Text(
                              '$totalFilters',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
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

        // ── Filter panel ───────────────────────────────────
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _MiniTabButton(
                        label: 'Category',
                        selected: _activeTab == 0,
                        onTap: () => setState(() => _activeTab = 0),
                      ),
                      const SizedBox(width: 8),
                      _MiniTabButton(
                        label: 'Brand',
                        selected: _activeTab == 1,
                        onTap: () => setState(() => _activeTab = 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_activeTab == 0)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _allCategories.map((c) {
                        final sel = _selectedCategories.contains(c);
                        return _MiniFilterChip(
                          label: c,
                          selected: sel,
                          onSelected: (v) {
                            if (v) {
                              _selectedCategories.add(c);
                            } else {
                              _selectedCategories.remove(c);
                            }
                            _applyFilters();
                          },
                        );
                      }).toList(),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _allBrands.map((b) {
                        final sel = _selectedBrands.contains(b);
                        return _MiniFilterChip(
                          label: b,
                          selected: sel,
                          onSelected: (v) {
                            if (v) {
                              _selectedBrands.add(b);
                            } else {
                              _selectedBrands.remove(b);
                            }
                            _applyFilters();
                          },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        _selectedCategories.clear();
                        _selectedBrands.clear();
                        _applyFilters();
                      },
                      child: const Text(
                        'Clear All',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Equipment grid ─────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.75,
              ),
              itemCount: _filtered.length + 1, // +1 for custom item card
              itemBuilder: (context, index) {
                // First card is always the "Add custom item" card.
                if (index == 0) {
                  return _AddCustomItemCard(onTap: _openCustomItemDialog);
                }
                final equip = _filtered[index - 1];
                final isAdded = widget.alreadyAdded.contains(equip.id);
                final isSelected = _selected.contains(equip.id);
                return _EquipGridTile(
                  equipment: equip,
                  isAdded: isAdded,
                  isSelected: isSelected,
                  onTap: isAdded
                      ? null
                      : () {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(equip.id);
                            } else {
                              _selected.add(equip.id);
                            }
                          });
                        },
                );
              },
            ),
          ),
        ),

        // ── Bottom action bar ──────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            children: [
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selected.clear()),
                  child: const Text(
                    'Clear Selection',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              const Spacer(),
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '${_selected.length} selected',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selected.isEmpty ? null : _goToReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrandBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kBrandBlue.withValues(alpha: 0.3),
                  disabledForegroundColor: Colors.white38,
                ),
                child: const Text('Next'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PAGE 2 — Review selected equipment
  // ══════════════════════════════════════════════════════════════

  Widget _buildReviewPage() {
    final repo = DataRepository();

    // Active items (selected minus removed).
    final activeIds = _selected.where((id) => !_removed.contains(id)).toList()
      ..sort((a, b) {
        final ea = repo.getEquipmentById(a);
        final eb = repo.getEquipmentById(b);
        return (ea?.name ?? '').compareTo(eb?.name ?? '');
      });

    return Column(
      children: [
        // ── Header ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: _goBackToSelection,
                tooltip: 'Back to selection',
              ),
              const SizedBox(width: 4),
              const Text(
                'Review Selection',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        // ── Undo bar (shown when items have been removed) ───
        if (_removed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orangeAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_removed.length} item${_removed.length == 1 ? '' : 's'} removed',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selected.addAll(_removed);
                        for (final id in _removed) {
                          _qtys.putIfAbsent(id, () => 1);
                        }
                        _removed.clear();
                      });
                    },
                    child: const Text(
                      'Undo Removal',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Equipment list ──────────────────────────────────
        Expanded(
          child: activeIds.isEmpty
              ? const Center(
                  child: Text(
                    'All items removed.\nGo back to select more.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 15),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: activeIds.length,
                  itemBuilder: (context, index) {
                    final id = activeIds[index];
                    final equip = repo.getEquipmentById(id);
                    if (equip == null) return const SizedBox.shrink();
                    final maxQty = equip.quantity ?? 1;
                    final qty = _qtys[id] ?? 1;

                    return _ReviewRow(
                      equipment: equip,
                      qty: qty,
                      maxQty: maxQty < 1 ? 1 : maxQty,
                      onQtyChanged: (v) {
                        setState(() => _qtys[id] = v);
                      },
                      onRemove: () {
                        setState(() {
                          _selected.remove(id);
                          _removed.add(id);
                        });
                      },
                      onInfoTap: () => _showReadOnlyInfo(equip),
                    );
                  },
                ),
        ),

        // ── Bottom action bar ───────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${activeIds.length} item${activeIds.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: activeIds.isEmpty
                    ? null
                    : () {
                        final result = <String, int>{};
                        for (final id in activeIds) {
                          result[id] = _qtys[id] ?? 1;
                        }
                        Navigator.of(context).pop(result);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrandBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kBrandBlue.withValues(alpha: 0.3),
                  disabledForegroundColor: Colors.white38,
                ),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Review row — equipment name, tags, qty controls, remove button
// ══════════════════════════════════════════════════════════════════

class _ReviewRow extends StatelessWidget {
  final Equipment equipment;
  final int qty;
  final int maxQty;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onRemove;
  final VoidCallback onInfoTap;

  const _ReviewRow({
    required this.equipment,
    required this.qty,
    required this.maxQty,
    required this.onQtyChanged,
    required this.onRemove,
    required this.onInfoTap,
  });

  void _adjust(int delta) {
    final clamped = (qty + delta).clamp(1, maxQty);
    if (clamped != qty) onQtyChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final int stock = equipment.quantity ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Main content (left side)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Equipment name
                        Text(
                          equipment.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Tags row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _ReviewTag(
                              label: equipment.category,
                              color: Colors.deepPurple,
                            ),
                            _ReviewTag(
                              label: 'Stock: $stock',
                              color: stock > 0 ? Colors.green : Colors.red,
                            ),
                            _ReviewTag(
                              label: equipment.brand,
                              color: Colors.lightBlueAccent,
                            ),
                            if (equipment.storage != null &&
                                equipment.storage!.isNotEmpty)
                              _ReviewTag(
                                label: 'Storage: ${equipment.storage}',
                                color: Colors.orange,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Qty controls row
                        Row(
                          children: [
                            const Text(
                              'Bring:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _CircleQtyButton(
                              icon: Icons.remove,
                              onTap: () => _adjust(-1),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 48,
                              height: 32,
                              child: TextField(
                                controller: TextEditingController(text: '$qty'),
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
                                  onQtyChanged(parsed.clamp(1, maxQty));
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            _CircleQtyButton(
                              icon: Icons.add,
                              onTap: () => _adjust(1),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Info button (vertically centered)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: IconButton(
                      icon: const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: onInfoTap,
                      tooltip: 'View details',
                    ),
                  ),

                  // Right column: remove button (top) + max qty (bottom)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        onPressed: onRemove,
                        tooltip: 'Remove',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'max $maxQty',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
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

// ── Circular +/- button ─────────────────────────────────────────

class _CircleQtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleQtyButton({required this.icon, required this.onTap});

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

// ── Review tag (similar to detail page _Tag) ────────────────────

class _ReviewTag extends StatelessWidget {
  final String label;
  final Color color;

  const _ReviewTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final Color textColor = color == Colors.green
        ? Colors.greenAccent
        : color == Colors.red
        ? Colors.redAccent
        : color == Colors.orange
        ? Colors.orangeAccent
        : color == Colors.lightBlueAccent
        ? Colors.lightBlueAccent.shade100
        : color == Colors.deepPurple
        ? Colors.deepPurpleAccent.shade100
        : Colors.white70;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Equipment grid tile ──────────────────────────────────────────────

class _EquipGridTile extends StatelessWidget {
  final Equipment equipment;
  final bool isAdded;
  final bool isSelected;
  final VoidCallback? onTap;

  const _EquipGridTile({
    required this.equipment,
    required this.isAdded,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imagePath = equipment.coverImages.isNotEmpty
        ? equipment.coverImages.first
        : '';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? _kBrandBlue
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Equipment image
              if (imagePath.isNotEmpty)
                AvifImage.network(
                  DataRepository().imageUrl(imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Container(color: Colors.grey.shade800),
                )
              else
                Container(color: Colors.grey.shade800),

              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),

              // "Added" darkened overlay
              if (isAdded) ...[
                Container(color: Colors.black.withValues(alpha: 0.6)),
                const Center(
                  child: Text(
                    'Added',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],

              // Selected checkmark
              if (isSelected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: _kBrandBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),

              // Bottom info
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      equipment.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${equipment.category} • ${equipment.brand}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mini tab button for filter panel ─────────────────────────────────

class _MiniTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MiniTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.white : Colors.white38,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── "Add custom item" grid card ──────────────────────────────────────

class _AddCustomItemCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddCustomItemCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: Colors.white54, size: 40),
            SizedBox(height: 8),
            Text(
              'Add custom item\nto shoot',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Custom item result ──────────────────────────────────────────────

class _CustomItemResult {
  final String name;
  final int qty;
  _CustomItemResult({required this.name, required this.qty});
}

// ── Custom item dialog ──────────────────────────────────────────────

class _CustomItemDialog extends StatefulWidget {
  const _CustomItemDialog();

  @override
  State<_CustomItemDialog> createState() => _CustomItemDialogState();
}

class _CustomItemDialogState extends State<_CustomItemDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  int _qty = 1;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _canAdd => _nameCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade900.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add Custom Item',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Name field
                const Text(
                  'Item Name',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g. Extension cord, Screwdriver...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Quantity row
                Row(
                  children: [
                    const Text(
                      'Quantity:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _CircleQtyButton(
                      icon: Icons.remove,
                      onTap: () {
                        if (_qty > 1) setState(() => _qty--);
                      },
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      height: 32,
                      child: TextField(
                        controller: TextEditingController(text: '$_qty'),
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
                          setState(() => _qty = parsed < 1 ? 1 : parsed);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CircleQtyButton(
                      icon: Icons.add,
                      onTap: () => setState(() => _qty++),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _canAdd
                          ? () {
                              Navigator.of(context).pop(
                                _CustomItemResult(
                                  name: _nameCtrl.text.trim(),
                                  qty: _qty,
                                ),
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrandBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kBrandBlue.withValues(
                          alpha: 0.3,
                        ),
                        disabledForegroundColor: Colors.white38,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Add to Shoot'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mini filter chip ─────────────────────────────────────────────────

// ══════════════════════════════════════════════════════════════════
// Read-only equipment info popup (no qty editor or remove button)
// ══════════════════════════════════════════════════════════════════

class _ReadOnlyEquipmentInfoPopup extends StatelessWidget {
  final Equipment equipment;

  const _ReadOnlyEquipmentInfoPopup({required this.equipment});

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
            child: AvifImage.network(
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

  @override
  Widget build(BuildContext context) {
    final String imagePath = equipment.coverImages.isNotEmpty
        ? equipment.coverImages.first
        : '';
    final int qty = equipment.quantity ?? 0;

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

                // Equipment photo
                if (imagePath.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _showFullImage(context, imagePath),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: AvifImage.network(
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
                        color: Colors.white.withValues(alpha: 1),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ] else
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
                        equipment.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ReadOnlyInfoRow(
                        label: 'Category',
                        value: equipment.category,
                      ),
                      _ReadOnlyInfoRow(label: 'Brand', value: equipment.brand),
                      _ReadOnlyInfoRow(
                        label: 'Stock',
                        value: qty > 0 ? '$qty' : 'Out of Stock',
                      ),
                      if (equipment.storage != null &&
                          equipment.storage!.isNotEmpty)
                        _ReadOnlyInfoRow(
                          label: 'Storage',
                          value: equipment.storage!,
                        ),
                      if (equipment.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          equipment.description,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
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

class _ReadOnlyInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyInfoRow({required this.label, required this.value});

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

class _MiniFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _MiniFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: onSelected,
      backgroundColor: Colors.black.withValues(alpha: 0.3),
      selectedColor: _kBrandBlue,
      checkmarkColor: Colors.white,
      labelStyle: const TextStyle(color: Colors.white),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? Colors.transparent : Colors.white24),
      ),
    );
  }
}
