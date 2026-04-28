// PixelVault — Inventory equipment creation dialog.
//
// Full-screen dialog for creating new equipment entries directly in
// the inventory. This creates:
//   1. An equipment_guides.yaml entry with no_guide: true
//   2. An inventory_mutable.yaml entry with quantity (and optional storage)
//
// The dialog collects: name, brand, category, a single cover image
// (for local preview only — not persisted to gist), and quantity.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/avif_converter.dart' as avif;
import '../services/clipboard_image_service.dart' as clipboard;
import '../services/data_repository.dart';
import '../widgets/smart_image.dart';
import 'guide_creator_page.dart' show GuideType;

// ══════════════════════════════════════════════════════════════════
// Constants
// ══════════════════════════════════════════════════════════════════

const _kBrandBlue = Color(0xFF0047BB);

// ══════════════════════════════════════════════════════════════════
// Launch helper
// ══════════════════════════════════════════════════════════════════

/// Open the inventory creation dialog as a full-screen slide-up.
void showInventoryCreator(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (ctx, a1, a2, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)),
      child: child,
    ),
    pageBuilder: (ctx, _, _) => const _InventoryCreatePage(),
  );
}

// ══════════════════════════════════════════════════════════════════
// Main page
// ══════════════════════════════════════════════════════════════════

class _InventoryCreatePage extends StatefulWidget {
  const _InventoryCreatePage();

  @override
  State<_InventoryCreatePage> createState() => _InventoryCreatePageState();
}

class _InventoryCreatePageState extends State<_InventoryCreatePage> {
  final _nameCtl = TextEditingController();
  final _brandCtl = TextEditingController();
  final _categoryCtl = TextEditingController();
  final _qtyCtl = TextEditingController(text: '1');
  final _storageCtl = TextEditingController();

  final _nameFocus = FocusNode();
  final _brandFocus = FocusNode();
  final _categoryFocus = FocusNode();

  Uint8List? _imageBytes;
  bool _submitting = false;

  // Autocomplete state.
  List<String> _brandSuggestions = [];
  List<String> _categorySuggestions = [];
  late final List<String> _allBrands;
  late final List<String> _allCategories;

  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();

    final allEquip = DataRepository().getAllEquipment();
    _allBrands =
        allEquip
            .map((e) => e.brand)
            .where((b) => b.isNotEmpty && b != 'Unknown')
            .toSet()
            .toList()
          ..sort();
    _allCategories =
        allEquip
            .map((e) => e.category)
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _scanTitleForBrand();
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
    _qtyCtl.dispose();
    _storageCtl.dispose();
    _nameFocus.dispose();
    _brandFocus.dispose();
    _categoryFocus.dispose();
    super.dispose();
  }

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

  Future<void> _pickImage() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _imageBytes = bytes);
  }

  Future<void> _pasteImage() async {
    final images = await clipboard.getClipboardImages();
    if (!mounted) return;
    if (images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image found on clipboard')),
      );
      return;
    }
    setState(() => _imageBytes = images.first);
  }

  bool _validate() {
    final missing = <String>[];
    if (_nameCtl.text.trim().isEmpty) missing.add('Name');
    if (_brandCtl.text.trim().isEmpty) missing.add('Brand');
    if (_categoryCtl.text.trim().isEmpty) missing.add('Category');
    if (_imageBytes == null) missing.add('Cover Image');
    if (_qtyCtl.text.trim().isEmpty) missing.add('Quantity');

    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Missing required fields: ${missing.join(', ')}'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _submitting = true);

    try {
      final name = _nameCtl.text.trim();
      // Convert the image to AVIF (falls back to WebP) and build its
      // repo path. The conversion happens here (UI layer) because
      // avif_converter is web-only; the repository stays platform-neutral.
      final converted = await avif.convertToAvif(_imageBytes!);
      final id = DataRepository.generateId(name);
      final repoPath = DataRepository.coverImagePath(
        GuideType.equipment,
        id,
        0,
        converted.ext,
      );

      await DataRepository().createEquipment(
        name: name,
        brand: _brandCtl.text.trim(),
        category: _categoryCtl.text.trim(),
        quantity: int.tryParse(_qtyCtl.text) ?? 1,
        storage: _storageCtl.text.trim().isEmpty
            ? null
            : _storageCtl.text.trim(),
        coverImage: (bytes: converted.bytes, repoPath: repoPath),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Equipment created successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create equipment: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Quantity helpers ────────────────────────────────────────────

  void _adjustQuantity(int delta) {
    final int current = int.tryParse(_qtyCtl.text) ?? 1;
    final int newVal = current + delta;
    _qtyCtl.text = '${newVal < 0 ? 0 : newVal}';
    setState(() {});
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
          // Content.
          CustomScrollView(
            slivers: [
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
                        'New Inventory Item',
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
              ),

              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Info banner.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _kBrandBlue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _kBrandBlue.withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Creating an item here adds it to the '
                                    'Inventory List only. To create an '
                                    'equipment guide for it, use the '
                                    'Equipment Guides page.',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Cover image ────────────────────────────────
                      const Text(
                        'Cover Image *',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 180,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          child: _imageBytes != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // Fit-to-height so the full image is
                                    // visible vertically even if it means
                                    // some horizontal empty space.
                                    Center(
                                      child: SmartImage.memory(
                                        _imageBytes!,
                                        fit: BoxFit.fitHeight,
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: GestureDetector(
                                        onTap: () =>
                                            setState(() => _imageBytes = null),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.7,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: _ImagePickerAction(
                                        icon: Icons.add_photo_alternate,
                                        label: 'Upload from\ndevice',
                                        onTap: _pickImage,
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    Expanded(
                                      child: _ImagePickerAction(
                                        icon: Icons.content_paste,
                                        label: 'Paste from\nclipboard',
                                        onTap: _pasteImage,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Name ───────────────────────────────────────
                      TextField(
                        controller: _nameCtl,
                        focusNode: _nameFocus,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration('Name *'),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 16),

                      // ── Brand ──────────────────────────────────────
                      _buildAutocompleteField(
                        controller: _brandCtl,
                        focusNode: _brandFocus,
                        label: 'Brand *',
                        suggestions: _brandSuggestions,
                        onSelect: (v) {
                          _brandCtl.text = v;
                          _brandCtl.selection = TextSelection.collapsed(
                            offset: v.length,
                          );
                          setState(() => _brandSuggestions = []);
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── Category ───────────────────────────────────
                      _buildAutocompleteField(
                        controller: _categoryCtl,
                        focusNode: _categoryFocus,
                        label: 'Category *',
                        suggestions: _categorySuggestions,
                        onSelect: (v) {
                          _categoryCtl.text = v;
                          _categoryCtl.selection = TextSelection.collapsed(
                            offset: v.length,
                          );
                          setState(() => _categorySuggestions = []);
                        },
                      ),
                      const SizedBox(height: 24),

                      // ── Quantity ────────────────────────────────────
                      const Text(
                        'Quantity *',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _circleButton(
                                  Icons.remove,
                                  () => _adjustQuantity(-1),
                                ),
                                const SizedBox(width: 24),
                                SizedBox(
                                  width: 80,
                                  child: TextField(
                                    controller: _qtyCtl,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 24),
                                _circleButton(
                                  Icons.add,
                                  () => _adjustQuantity(1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Storage (optional) ─────────────────────────
                      TextField(
                        controller: _storageCtl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(
                          'Storage Location',
                          hint: 'e.g. A, Tripod Shelf...',
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Submit ──────────────────────────────────────
                      ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBrandBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _kBrandBlue.withValues(
                            alpha: 0.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Create'),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

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
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (ctx, i) {
                return ListTile(
                  dense: true,
                  title: Text(
                    suggestions[i],
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => onSelect(suggestions[i]),
                );
              },
            ),
          ),
      ],
    );
  }

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
    );
  }
}

class _ImagePickerAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ImagePickerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 36),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapitalizeFirstFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final cap = newValue.text[0].toUpperCase() + newValue.text.substring(1);
    if (cap == newValue.text) return newValue;
    return newValue.copyWith(text: cap);
  }
}
