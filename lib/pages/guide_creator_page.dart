// PixelVault — Guide creator page.
//
// Full-screen dialog for creating new guides (equipment, videography,
// or scenario). For equipment, the first step shows a picker grid of
// inventory items that don't yet have an equipment guide; for all
// types, the next step presents a creation form with cover images,
// text fields, and collapsible sections with inline markdown
// formatting.
//
// This file contains the UI and local state only — guide data is not
// persisted to the Gist in this version. The "Create" action validates
// the form, optionally asks for inventory details (equipment only),
// and closes with a success message.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:image_picker/image_picker.dart';

import '../models/equipment_model.dart';
import '../services/data_repository.dart';

// ══════════════════════════════════════════════════════════════════
// Constants
// ══════════════════════════════════════════════════════════════════

const _kBrandBlue = Color(0xFF0047BB);

// ══════════════════════════════════════════════════════════════════
// Enums & data classes
// ══════════════════════════════════════════════════════════════════

enum GuideType { equipment, videography, scenario }

/// A single image in the cover or section image row. Starts with
/// [loading] true while bytes are being read; once ready, [bytes]
/// is non-null and [loading] is false.
class _ImageEntry {
  Uint8List? bytes;
  String? assetPath; // Non-null for pre-existing cover images.
  bool loading;
  _ImageEntry({this.assetPath, this.loading = false});
  bool get isAsset => assetPath != null;
  bool get isReady => !loading && (bytes != null || isAsset);
}

/// Mutable state for one collapsible section in the creation form.
class _SectionData {
  final titleCtl = TextEditingController();
  final bodyCtl = TextEditingController();
  final bodyFocus = FocusNode();
  final List<_ImageEntry> images = [];
  void dispose() {
    titleCtl.dispose();
    bodyCtl.dispose();
    bodyFocus.dispose();
  }
}

/// Data bundle used to pre-populate the form when editing an existing guide.
class GuideEditData {
  final String name;
  final String brand;
  final String category;
  final List<String> coverImages;
  final List<({String title, String body, List<String> images})> sections;

  const GuideEditData({
    required this.name,
    this.brand = '',
    this.category = '',
    required this.coverImages,
    required this.sections,
  });
}

// ══════════════════════════════════════════════════════════════════
// Launch helpers
// ══════════════════════════════════════════════════════════════════

/// Open the guide creator as a full-screen slide-up dialog.
void showGuideCreator(BuildContext context, GuideType type) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (ctx, a1, a2, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)),
      child: child,
    ),
    pageBuilder: (ctx, _, _) => _GuideCreatorPage(type: type),
  );
}

/// Open the guide editor pre-populated with existing data.
void showGuideEditor(BuildContext context, GuideType type, GuideEditData data) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (ctx, a1, a2, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)),
      child: child,
    ),
    pageBuilder: (ctx, _, _) => _GuideCreatorPage(type: type, editData: data),
  );
}

// ══════════════════════════════════════════════════════════════════
// Main page
// ══════════════════════════════════════════════════════════════════

class _GuideCreatorPage extends StatefulWidget {
  final GuideType type;
  final GuideEditData? editData;
  const _GuideCreatorPage({required this.type, this.editData});

  @override
  State<_GuideCreatorPage> createState() => _GuideCreatorPageState();
}

class _GuideCreatorPageState extends State<_GuideCreatorPage> {
  // ── Edit mode ─────────────────────────────────────────────────
  bool get _isEditMode => widget.editData != null;

  // ── Step management ────────────────────────────────────────────
  bool _showForm = false;
  Equipment? _selectedEquipment;
  bool _isNewEquipment = false;

  // ── Form controllers ───────────────────────────────────────────
  final _nameCtl = TextEditingController();
  final _brandCtl = TextEditingController();
  final _categoryCtl = TextEditingController();
  final _nameFocus = FocusNode();
  final _brandFocus = FocusNode();
  final _categoryFocus = FocusNode();
  final List<_ImageEntry> _coverImages = [];
  final List<_SectionData> _sections = [];
  final _formKey = GlobalKey<FormState>();

  // ── Autocomplete state ─────────────────────────────────────────
  List<String> _brandSuggestions = [];
  List<String> _categorySuggestions = [];

  // ── Reference data ─────────────────────────────────────────────
  late final List<String> _allBrands;
  late final List<String> _allCategories;

  // ── Equipment picker state ─────────────────────────────────────
  final _pickerSearchCtl = TextEditingController();
  bool _pickerShowFilters = false;
  int _pickerActiveTab = 0;
  final Set<String> _pickerSelectedCategories = {};
  final Set<String> _pickerSelectedBrands = {};

  final _imagePicker = ImagePicker();

  // ── Lifecycle ──────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    if (widget.type != GuideType.equipment || _isEditMode) _showForm = true;

    final allEquip = DataRepository().getAllEquipment();
    _allBrands = allEquip
        .map((e) => e.brand)
        .where((b) => b.isNotEmpty && b != 'Unknown')
        .toSet()
        .toList()
      ..sort();
    _allCategories = allEquip
        .map((e) => e.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Pre-populate form when editing an existing guide.
    final edit = widget.editData;
    if (edit != null) {
      _nameCtl.text = edit.name;
      _brandCtl.text = edit.brand;
      _categoryCtl.text = edit.category;
      for (final img in edit.coverImages) {
        _coverImages.add(_ImageEntry(assetPath: img));
      }
      for (final sec in edit.sections) {
        final sd = _SectionData();
        sd.titleCtl.text = sec.title;
        sd.bodyCtl.text = sec.body;
        for (final img in sec.images) {
          sd.images.add(_ImageEntry(assetPath: img));
        }
        _sections.add(sd);
      }
    } else {
      _sections.add(_SectionData());
    }

    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && widget.type == GuideType.equipment) {
        _scanTitleForBrand();
      }
    });

    _brandCtl.addListener(() {
      final t = _brandCtl.text;
      setState(() {
        _brandSuggestions = t.isEmpty
            ? []
            : _allBrands
                  .where((b) => b.toLowerCase().contains(t.toLowerCase()))
                  .toList();
      });
    });

    _categoryCtl.addListener(() {
      final t = _categoryCtl.text;
      setState(() {
        _categorySuggestions = t.isEmpty
            ? []
            : _allCategories
                  .where((c) => c.toLowerCase().contains(t.toLowerCase()))
                  .toList();
      });
    });
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _brandCtl.dispose();
    _categoryCtl.dispose();
    _nameFocus.dispose();
    _brandFocus.dispose();
    _categoryFocus.dispose();
    _pickerSearchCtl.dispose();
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  // ── Brand auto-detect ──────────────────────────────────────────

  void _scanTitleForBrand() {
    if (_brandCtl.text.isNotEmpty) return;
    final words = _nameCtl.text.split(RegExp(r'\s+'));
    for (final word in words) {
      for (final brand in _allBrands) {
        if (word.toLowerCase() == brand.toLowerCase()) {
          _brandCtl.text = brand;
          return;
        }
      }
    }
  }

  // ── Image helpers ──────────────────────────────────────────────

  Future<void> _pickImages(List<_ImageEntry> target) async {
    final files = await _imagePicker.pickMultiImage();
    if (files.isEmpty) return;
    for (final file in files) {
      final entry = _ImageEntry(loading: true);
      setState(() => target.add(entry));
      try {
        final bytes = await file.readAsBytes();
        // Simulate AVIF conversion delay.
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        setState(() {
          entry.bytes = bytes;
          entry.loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => target.remove(entry));
      }
    }
  }

  Future<void> _addAssetImage(String assetPath) async {
    final entry = _ImageEntry(assetPath: assetPath, loading: true);
    setState(() => _coverImages.add(entry));
    try {
      final data = await rootBundle.load(assetPath);
      if (!mounted) return;
      setState(() {
        entry.bytes = data.buffer.asUint8List();
        entry.loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Keep the entry as asset-only — it may still display via Image.network.
        entry.loading = false;
      });
    }
  }

  void _removeImage(List<_ImageEntry> list, int index) {
    setState(() => list.removeAt(index));
  }

  void _reorderImage(List<_ImageEntry> list, int from, int to) {
    if (to < 0 || to >= list.length) return;
    setState(() {
      final item = list.removeAt(from);
      list.insert(to, item);
    });
  }

  // ── Formatting helpers ─────────────────────────────────────────

  void _wrapSelection(TextEditingController ctl, String prefix, String suffix) {
    final text = ctl.text;
    final sel = ctl.selection;
    if (!sel.isValid) return;

    if (sel.isCollapsed) {
      final newText = text.substring(0, sel.start) +
          prefix +
          suffix +
          text.substring(sel.start);
      ctl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + prefix.length),
      );
    } else {
      final selected = text.substring(sel.start, sel.end);
      final newText = text.substring(0, sel.start) +
          prefix +
          selected +
          suffix +
          text.substring(sel.end);
      ctl.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start + prefix.length,
          extentOffset: sel.end + prefix.length,
        ),
      );
    }
  }

  void _insertBullet(TextEditingController ctl) {
    final text = ctl.text;
    final pos = ctl.selection.start;
    if (pos < 0) return;

    int lineStart = text.lastIndexOf('\n', pos - 1) + 1;
    final newText =
        '${text.substring(0, lineStart)}• ${text.substring(lineStart)}';
    ctl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + 2),
    );
  }

  // ── Equipment picker → form transition ─────────────────────────

  void _selectFromInventory(Equipment eq) {
    _selectedEquipment = eq;
    _isNewEquipment = false;
    _nameCtl.text = eq.name;
    _brandCtl.text = eq.brand;
    _categoryCtl.text = eq.category;
    for (final img in eq.coverImages) {
      _addAssetImage(img);
    }
    setState(() => _showForm = true);
  }

  void _createNew() {
    _selectedEquipment = null;
    _isNewEquipment = true;
    setState(() => _showForm = true);
  }

  // ── Validation & submit ────────────────────────────────────────

  bool _validate() {
    final missing = <String>[];

    if (_nameCtl.text.trim().isEmpty) missing.add('Name');
    if (widget.type == GuideType.equipment) {
      if (_brandCtl.text.trim().isEmpty) missing.add('Brand');
      if (_categoryCtl.text.trim().isEmpty) missing.add('Category');
    }
    if (_coverImages.where((e) => e.isReady).isEmpty) {
      missing.add('Cover Image (at least one)');
    }
    if (_sections.isEmpty) {
      missing.add('Sections (at least one)');
    } else {
      for (int i = 0; i < _sections.length; i++) {
        final s = _sections[i];
        if (s.titleCtl.text.trim().isEmpty) {
          missing.add('Section ${i + 1} Title');
        }
        if (s.bodyCtl.text.trim().isEmpty) {
          missing.add('Section ${i + 1} Body');
        }
      }
    }

    if (missing.isNotEmpty) {
      _showError('Missing required fields: ${missing.join(', ')}');
      return false;
    }
    return true;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Future<void> _submit() async {
    if (!_validate()) return;

    // Equipment not linked to inventory → ask for quantity + storage.
    if (!_isEditMode &&
        widget.type == GuideType.equipment &&
        _selectedEquipment == null) {
      final result = await _showInventoryDialog();
      if (result == null) return; // User cancelled.
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isEditMode
            ? 'Guide updated successfully.'
            : 'Guide created successfully.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<Map<String, dynamic>?> _showInventoryDialog() {
    final qtyCtl = TextEditingController(text: '1');
    final storCtl = TextEditingController();

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add to Inventory',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This equipment does not exist in the Inventory List. '
              'It will be created there as well.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: qtyCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration('Quantity'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: storCtl,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration('Storage Location',
                  hint: 'e.g. A1, Shelf B'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {
              'quantity': int.tryParse(qtyCtl.text) ?? 1,
              'storage': storCtl.text,
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background gradient.
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
          // Blob glow.
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
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
          // Content — animated switch between picker and form.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _showForm
                ? _buildForm(key: const ValueKey('form'))
                : _buildEquipmentPicker(key: const ValueKey('picker')),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Equipment picker (step 1)
  // ══════════════════════════════════════════════════════════════

  Widget _buildEquipmentPicker({Key? key}) {
    final repo = DataRepository();
    final allEquip = repo.getAllEquipment();

    // Items marked with no_guide in the YAML are ones without guides.
    final unguidedAll = allEquip.where((e) => e.noGuide).toList();

    // Apply search + filters.
    final query = _pickerSearchCtl.text.toLowerCase();
    final unguided = unguidedAll.where((e) {
      if (query.isNotEmpty && !e.name.toLowerCase().contains(query)) {
        return false;
      }
      if (_pickerSelectedCategories.isNotEmpty &&
          !_pickerSelectedCategories.contains(e.category)) {
        return false;
      }
      if (_pickerSelectedBrands.isNotEmpty &&
          !_pickerSelectedBrands.contains(e.brand)) {
        return false;
      }
      return true;
    }).toList();

    final pickerCategories =
        unguidedAll.map((e) => e.category).where((c) => c.isNotEmpty).toSet().toList()..sort();
    final pickerBrands =
        unguidedAll.map((e) => e.brand).where((b) => b.isNotEmpty).toSet().toList()..sort();

    final totalFilters =
        _pickerSelectedCategories.length + _pickerSelectedBrands.length;

    const double maxTileWidth = 420;
    final int cols = math.max(
      2,
      (MediaQuery.of(context).size.width / maxTileWidth).floor(),
    );

    return CustomScrollView(
      key: key,
      slivers: [
        // App bar.
        SliverAppBar(
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          backgroundColor: Colors.transparent,
          pinned: true,
          flexibleSpace: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: FlexibleSpaceBar(
                title: const Text(
                  'Create Equipment Guide',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                background:
                    Container(color: Colors.black.withValues(alpha: 0.2)),
              ),
            ),
          ),
        ),

        // "Create New" button.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _createNew,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Create New Equipment Guide',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),

        // Search bar.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pickerSearchCtl,
                          style: const TextStyle(color: Colors.white),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search Inventory',
                            hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6)),
                            prefixIcon:
                                const Icon(Icons.search, color: Colors.white),
                            suffixIcon: _pickerSearchCtl.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear,
                                        color: Colors.white),
                                    onPressed: () {
                                      _pickerSearchCtl.clear();
                                      setState(() {});
                                    },
                                  ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(
                            () => _pickerShowFilters = !_pickerShowFilters),
                        child: Stack(
                          children: [
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.filter_alt,
                                  color: Colors.white, size: 28),
                            ),
                            if (totalFilters > 0)
                              Positioned(
                                right: 4,
                                top: 4,
                                child: CircleAvatar(
                                  radius: 8,
                                  backgroundColor: Colors.red,
                                  child: Text('$totalFilters',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 10)),
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
          ),
        ),

        // Filter panel.
        if (_pickerShowFilters)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildPickerTab('Category', 0),
                            const SizedBox(width: 16),
                            _buildPickerTab('Brand', 1),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: (_pickerActiveTab == 0
                                  ? pickerCategories
                                  : pickerBrands)
                              .map((label) {
                            final sel = _pickerActiveTab == 0
                                ? _pickerSelectedCategories
                                : _pickerSelectedBrands;
                            final isSelected = sel.contains(label);
                            return FilterChip(
                              label: Text(label),
                              selected: isSelected,
                              onSelected: (v) {
                                setState(() {
                                  v ? sel.add(label) : sel.remove(label);
                                });
                              },
                              backgroundColor:
                                  Colors.black.withValues(alpha: 0.3),
                              selectedColor: _kBrandBlue,
                              checkmarkColor: Colors.white,
                              labelStyle:
                                  const TextStyle(color: Colors.white),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                    color: isSelected
                                        ? Colors.transparent
                                        : Colors.white38),
                              ),
                            );
                          }).toList(),
                        ),
                        const Divider(color: Colors.white24, height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => setState(() {
                                _pickerSelectedCategories.clear();
                                _pickerSelectedBrands.clear();
                              }),
                              child: const Text('Clear All',
                                  style: TextStyle(color: Colors.white)),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: () =>
                                  setState(() => _pickerShowFilters = false),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kBrandBlue,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Done'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Grid or empty state.
        if (unguided.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  unguidedAll.isEmpty
                      ? 'All inventory items already have guides.\n'
                        'Use the button above to create a new one.'
                      : 'No items match your search.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                      height: 1.5),
                ),
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
                childAspectRatio: 3 / 2,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final eq = unguided[index];
                final img =
                    eq.coverImages.isNotEmpty ? eq.coverImages.first : '';
                return _buildPickerCard(eq, img);
              }, childCount: unguided.length),
            ),
          ),
      ],
    );
  }

  Widget _buildPickerTab(String label, int index) {
    final selected = _pickerActiveTab == index;
    return GestureDetector(
      onTap: () => setState(() => _pickerActiveTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? Colors.white : Colors.white54, width: 1),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildPickerCard(Equipment eq, String imagePath) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: imagePath.isNotEmpty
                ? AvifImage.network(DataRepository().imageUrl(imagePath), fit: BoxFit.cover)
                : Container(color: Colors.white.withValues(alpha: 0.1)),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(eq.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                              blurRadius: 4,
                              color: Colors.black,
                              offset: Offset(0, 1)),
                        ],
                      )),
                  const SizedBox(height: 2),
                  Text('${eq.brand} · ${eq.category}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12)),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _selectFromInventory(eq),
                highlightColor: Colors.white.withValues(alpha: 0.1),
                splashColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Creation form (step 2 / only step for video & scenario)
  // ══════════════════════════════════════════════════════════════

  Widget _buildForm({Key? key}) {
    final isEquipment = widget.type == GuideType.equipment;
    final String title;
    if (_isEditMode) {
      switch (widget.type) {
        case GuideType.equipment:
          title = 'Edit Equipment Guide';
        case GuideType.videography:
          title = 'Edit Videography Guide';
        case GuideType.scenario:
          title = 'Edit Production Scenario';
      }
    } else {
      switch (widget.type) {
        case GuideType.equipment:
          title = 'New Equipment Guide';
        case GuideType.videography:
          title = 'New Videography Guide';
        case GuideType.scenario:
          title = 'New Production Scenario';
      }
    }

    return CustomScrollView(
      key: key,
      slivers: [
        // App bar.
        SliverAppBar(
          leading: IconButton(
            icon: Icon(
              _isEditMode || (isEquipment && (_isNewEquipment || _selectedEquipment != null))
                  ? Icons.arrow_back
                  : Icons.close,
              color: Colors.white,
            ),
            onPressed: () {
              if (_isEditMode) {
                Navigator.of(context).pop();
                return;
              }
              if (isEquipment && _showForm && (_isNewEquipment || _selectedEquipment != null)) {
                // Go back to picker.
                setState(() {
                  _showForm = false;
                  _selectedEquipment = null;
                  _isNewEquipment = false;
                  _nameCtl.clear();
                  _brandCtl.clear();
                  _categoryCtl.clear();
                  _coverImages.clear();
                  for (final s in _sections) {
                    s.dispose();
                  }
                  _sections.clear();
                  _sections.add(_SectionData());
                });
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          backgroundColor: Colors.transparent,
          pinned: true,
          flexibleSpace: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: FlexibleSpaceBar(
                title: Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                background:
                    Container(color: Colors.black.withValues(alpha: 0.2)),
              ),
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Cover images ──────────────────────────────────
                  _buildSectionLabel('Cover Images *'),
                  const SizedBox(height: 8),
                  _buildImageRow(_coverImages),
                  const SizedBox(height: 24),

                  // ── Name ──────────────────────────────────────────
                  TextFormField(
                    controller: _nameCtl,
                    focusNode: _nameFocus,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('Name *'),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),

                  // ── Brand (equipment only) ────────────────────────
                  if (isEquipment) ...[
                    _buildAutocompleteField(
                      controller: _brandCtl,
                      focusNode: _brandFocus,
                      label: 'Brand *',
                      suggestions: _brandSuggestions,
                      onSelect: (v) {
                        _brandCtl.text = v;
                        _brandCtl.selection = TextSelection.collapsed(
                            offset: v.length);
                        setState(() => _brandSuggestions = []);
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Category (equipment only) ────────────────────
                    _buildAutocompleteField(
                      controller: _categoryCtl,
                      focusNode: _categoryFocus,
                      label: 'Category *',
                      suggestions: _categorySuggestions,
                      onSelect: (v) {
                        _categoryCtl.text = v;
                        _categoryCtl.selection = TextSelection.collapsed(
                            offset: v.length);
                        setState(() => _categorySuggestions = []);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Sections ──────────────────────────────────────
                  _buildSectionLabel('Sections *'),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _sections.length; i++) ...[
                    _buildSectionEditor(i),
                    const SizedBox(height: 12),
                  ],

                  // Add section button.
                  OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => _sections.add(_SectionData())),
                    icon: const Icon(Icons.add, color: Colors.white70),
                    label: const Text('Add Section',
                        style: TextStyle(color: Colors.white70)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.35)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Submit button ─────────────────────────────────
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBrandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    child: Text(_isEditMode
                        ? 'Save'
                        : isEquipment
                            ? 'Next'
                            : 'Create'),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Section editor ─────────────────────────────────────────────

  Widget _buildSectionEditor(int index) {
    final sec = _sections[index];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header row: label + delete.
              Row(
                children: [
                  Text('Section ${index + 1}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_sections.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 28),
                      iconSize: 32,
                      onPressed: () {
                        setState(() {
                          _sections[index].dispose();
                          _sections.removeAt(index);
                        });
                      },
                      tooltip: 'Remove section',
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Section title.
              TextField(
                controller: sec.titleCtl,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('Section Title'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),

              // Section images.
              _buildSectionLabel('Section Images'),
              const SizedBox(height: 6),
              _buildImageRow(sec.images),
              const SizedBox(height: 12),

              // Formatting toolbar.
              _buildFormattingToolbar(sec.bodyCtl, sec.bodyFocus),
              const SizedBox(height: 4),

              // Section body.
              TextField(
                controller: sec.bodyCtl,
                focusNode: sec.bodyFocus,
                maxLines: 8,
                minLines: 4,
                style: const TextStyle(color: Colors.white, height: 1.5),
                decoration: _fieldDecoration('Section Body')
                    .copyWith(alignLabelWithHint: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Image preview row ──────────────────────────────────────────

  Widget _buildImageRow(List<_ImageEntry> images) {
    return SizedBox(
      height: 120,
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.4),
          ),
          trackColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.1),
          ),
          trackVisibility: WidgetStateProperty.all(true),
          thickness: WidgetStateProperty.all(6),
          radius: const Radius.circular(3),
        ),
        child: Scrollbar(
          thumbVisibility: true,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 12),
            children: [
          for (int i = 0; i < images.length; i++)
            _buildImageThumb(images, i),
          // Add button.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _pickImages(images),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      style: BorderStyle.solid),
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 28),
                    const SizedBox(height: 4),
                    Text('Upload',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageThumb(List<_ImageEntry> list, int index) {
    final entry = list[index];
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          // Image or loading.
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 100,
              height: 100,
              child: entry.loading
                  ? Container(
                      color: Colors.white.withValues(alpha: 0.1),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                    )
                  : entry.bytes != null
                      ? Image.memory(entry.bytes!, fit: BoxFit.cover)
                      : entry.isAsset
                          ? AvifImage.network(
                              DataRepository().imageUrl(entry.assetPath!),
                              fit: BoxFit.cover)
                          : Container(
                              color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          // Remove button.
          if (!entry.loading)
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => _removeImage(list, index),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 14),
                ),
              ),
            ),
          // Reorder arrows.
          if (!entry.loading && list.length > 1)
            Positioned(
              bottom: 2,
              left: 2,
              right: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (index > 0)
                    _reorderArrow(Icons.chevron_left,
                        () => _reorderImage(list, index, index - 1))
                  else
                    const SizedBox(width: 22),
                  if (index < list.length - 1)
                    _reorderArrow(Icons.chevron_right,
                        () => _reorderImage(list, index, index + 1))
                  else
                    const SizedBox(width: 22),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _reorderArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }

  // ── Formatting toolbar ─────────────────────────────────────────

  Widget _buildFormattingToolbar(
      TextEditingController ctl, FocusNode focus) {
    Widget btn(String label, VoidCallback onTap, {IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            onTap();
            focus.requestFocus();
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: icon != null
                ? Icon(icon, color: Colors.white70, size: 16)
                : Text(label,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn('B', () => _wrapSelection(ctl, '**', '**')),
        btn('I', () => _wrapSelection(ctl, '*', '*')),
        btn('', () => _insertBullet(ctl), icon: Icons.format_list_bulleted),
      ],
    );
  }

  // ── Autocomplete text field ────────────────────────────────────

  Widget _buildAutocompleteField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required List<String> suggestions,
    required ValueChanged<String> onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration(label),
          inputFormatters: [_CapitalizeFirstFormatter()],
        ),
        if (suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (ctx, i) {
                return ListTile(
                  dense: true,
                  title: Text(suggestions[i],
                      style: const TextStyle(color: Colors.white)),
                  onTap: () => onSelect(suggestions[i]),
                );
              },
            ),
          ),
      ],
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────

  Widget _buildSectionLabel(String text) {
    return Text(text,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600));
  }
}

// ══════════════════════════════════════════════════════════════════
// Shared InputDecoration
// ══════════════════════════════════════════════════════════════════

InputDecoration _fieldDecoration(String label, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(color: Colors.white),
    hintStyle: const TextStyle(color: Colors.white54),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kBrandBlue),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.red),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════
// Input formatter: first letter always capitalised
// ══════════════════════════════════════════════════════════════════

class _CapitalizeFirstFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final cap =
        newValue.text[0].toUpperCase() + newValue.text.substring(1);
    if (cap == newValue.text) return newValue;
    return newValue.copyWith(text: cap);
  }
}
