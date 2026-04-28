// PixelVault — Inventory edit dialog.
//
// Modal dialog used from the inventory list when an admin taps the edit
// icon on an equipment card. It presents a two-step flow:
//
//   1. Edit mode    — lets the user change quantity (via +/- buttons or a
//                     text field), storage location, brand, and category.
//   2. Confirm mode — shows a diff of what changed and requires the user
//                     to confirm before the changes are returned.
//
// The dialog returns an [InventoryEditResult] (or null if cancelled) via
// [Navigator.pop]. Callers should inspect [InventoryEditResult.changed] to
// decide whether to persist the update.

import 'dart:ui'; // For ImageFilter used by BackdropFilter.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // FilteringTextInputFormatter + Uint8List.
import 'package:image_picker/image_picker.dart';

import '../services/data_repository.dart';
import '../widgets/smart_image.dart';

import '../services/clipboard_image_service.dart' as clipboard;

/// Result returned by [showInventoryEditDialog] after the user confirms.
///
/// [changed] is true if any of [quantity], [storage], [brand],
/// [category], or the cover image differs from the initial values.
/// [removed] is true when the user confirmed removal of the item — in
/// that case the caller should delete the equipment entirely and ignore
/// the other fields. [newImageBytes] is non-null only when the user
/// replaced the cover image; the caller is responsible for AVIF
/// conversion + upload.
class InventoryEditResult {
  final int quantity;
  final String storage;
  final String brand;
  final String category;
  final bool changed;
  final bool removed;
  final Uint8List? newImageBytes;

  InventoryEditResult({
    required this.quantity,
    required this.storage,
    required this.brand,
    required this.category,
    required this.changed,
    this.removed = false,
    this.newImageBytes,
  });
}

/// Opens the inventory edit dialog.
///
/// Returns the user's edits wrapped in an [InventoryEditResult], or `null`
/// if the user dismissed the dialog via Cancel. The dialog is intentionally
/// not barrier-dismissible — cancel must be explicit so a stray tap can't
/// discard in-progress edits.
Future<InventoryEditResult?> showInventoryEditDialog(
  BuildContext context, {
  required String equipmentName,
  required int initialQuantity,
  required String initialStorage,
  required String initialBrand,
  required String initialCategory,
  String initialCoverImagePath = '',
}) {
  return showDialog<InventoryEditResult>(
    context: context,
    barrierColor: Colors.black54, // Slight darken so the dialog pops.
    barrierDismissible: false,
    builder: (context) => _InventoryEditDialog(
      equipmentName: equipmentName,
      initialQuantity: initialQuantity,
      initialStorage: initialStorage,
      initialBrand: initialBrand,
      initialCategory: initialCategory,
      initialCoverImagePath: initialCoverImagePath,
    ),
  );
}

/// Internal dialog steps: edit form → save-confirm diff OR remove-confirm.
enum _StepMode { edit, confirm, removeConfirm }

class _InventoryEditDialog extends StatefulWidget {
  final String equipmentName;
  final int initialQuantity;
  final String initialStorage;
  final String initialBrand;
  final String initialCategory;
  final String initialCoverImagePath;

  const _InventoryEditDialog({
    required this.equipmentName,
    required this.initialQuantity,
    required this.initialStorage,
    required this.initialBrand,
    required this.initialCategory,
    required this.initialCoverImagePath,
  });

  @override
  State<_InventoryEditDialog> createState() => _InventoryEditDialogState();
}

class _InventoryEditDialogState extends State<_InventoryEditDialog> {
  // Controllers keep the editable fields wired to both the text inputs
  // and the helper buttons (+/-, reset).
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _storageCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _categoryCtrl;

  _StepMode _mode = _StepMode.edit;

  /// In-memory bytes of a replacement cover image the user picked or
  /// pasted. Null means "keep the existing image". The raw bytes are
  /// forwarded to the caller which handles AVIF conversion + upload.
  Uint8List? _imageBytes;

  final ImagePicker _imagePicker = ImagePicker();

  // Autocomplete data for brand/category fields.
  late final List<String> _allBrands;
  late final List<String> _allCategories;
  List<String> _brandSuggestions = const [];
  List<String> _categorySuggestions = const [];

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.initialQuantity}');
    _storageCtrl = TextEditingController(text: widget.initialStorage);
    _brandCtrl = TextEditingController(text: widget.initialBrand);
    _categoryCtrl = TextEditingController(text: widget.initialCategory);

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

    _brandCtrl.addListener(() {
      final t = _brandCtrl.text;
      setState(() {
        _brandSuggestions = (t.isEmpty || t == widget.initialBrand)
            ? const []
            : _allBrands
                .where((b) =>
                    b.toLowerCase().contains(t.toLowerCase()) && b != t)
                .toList();
      });
    });

    _categoryCtrl.addListener(() {
      final t = _categoryCtrl.text;
      setState(() {
        _categorySuggestions = (t.isEmpty || t == widget.initialCategory)
            ? const []
            : _allCategories
                .where((c) =>
                    c.toLowerCase().contains(t.toLowerCase()) && c != t)
                .toList();
      });
    });
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _storageCtrl.dispose();
    _brandCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  // ── Image mutators ────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final XFile? picked =
        await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _imageBytes = bytes);
  }

  Future<void> _pasteImage() async {
    try {
      final images = await clipboard.getClipboardImages();
      if (images.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No image found in clipboard')),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _imageBytes = images.first);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clipboard paste failed: $e')),
      );
    }
  }

  void _resetImage() => setState(() => _imageBytes = null);

  // ── Step transitions ──────────────────────────────────────────────────

  /// Handler for the "Review" button in edit mode.
  ///
  /// If the user cleared the quantity field entirely we restore the
  /// initial value so we never ship an empty / NaN quantity to the
  /// confirmation step.
  void _onSavePressed() {
    if (_qtyCtrl.text.isEmpty) {
      _qtyCtrl.text = '${widget.initialQuantity}';
    }
    setState(() => _mode = _StepMode.confirm);
  }

  /// Handler for the final "Save" button in confirm mode. Pops the dialog
  /// with the accumulated edits wrapped in an [InventoryEditResult].
  void _onConfirmPressed() {
    // Fall back to the initial quantity if the field somehow contains an
    // unparseable value — defensive, the digitsOnly formatter should
    // prevent this in practice.
    final int currentQty =
        int.tryParse(_qtyCtrl.text) ?? widget.initialQuantity;
    final String currentStorage = _storageCtrl.text.trim();
    final String currentBrand = _brandCtrl.text.trim();
    final String currentCategory = _categoryCtrl.text.trim();

    final bool changed =
        (currentQty != widget.initialQuantity) ||
        (currentStorage != widget.initialStorage) ||
        (currentBrand != widget.initialBrand) ||
        (currentCategory != widget.initialCategory) ||
        (_imageBytes != null);

    Navigator.of(context).pop(
      InventoryEditResult(
        quantity: currentQty,
        storage: currentStorage,
        brand: currentBrand,
        category: currentCategory,
        changed: changed,
        newImageBytes: _imageBytes,
      ),
    );
  }

  /// Handler for the "Back" button in confirm mode — returns to edit.
  void _onBackToEdit() => setState(() => _mode = _StepMode.edit);

  /// Transition to the remove-confirm step where the user must explicitly
  /// acknowledge that the equipment guide will be wiped alongside the
  /// inventory entry.
  void _onRemovePressed() => setState(() => _mode = _StepMode.removeConfirm);

  /// Final confirmation for removal — pops with `removed: true`.
  void _onRemoveConfirmed() {
    Navigator.of(context).pop(
      InventoryEditResult(
        quantity: widget.initialQuantity,
        storage: widget.initialStorage,
        brand: widget.initialBrand,
        category: widget.initialCategory,
        changed: false,
        removed: true,
      ),
    );
  }

  // ── Field mutators ────────────────────────────────────────────────────

  /// Increment/decrement the quantity field, clamped at zero so we never
  /// show a negative stock count.
  void _adjustQuantity(int delta) {
    final int current =
        int.tryParse(_qtyCtrl.text) ?? widget.initialQuantity;
    final int newVal = current + delta;
    _qtyCtrl.text = '${newVal < 0 ? 0 : newVal}';
  }

  /// Reset the quantity input back to the value the dialog opened with.
  void _resetQuantity() => _qtyCtrl.text = '${widget.initialQuantity}';

  /// Reset the storage input back to the value the dialog opened with.
  void _resetStorage() => _storageCtrl.text = widget.initialStorage;

  void _resetBrand() {
    _brandCtrl.text = widget.initialBrand;
    setState(() => _brandSuggestions = const []);
  }

  void _resetCategory() {
    _categoryCtrl.text = widget.initialCategory;
    setState(() => _categorySuggestions = const []);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Glassmorphism wrapper — the Dialog itself is fully transparent so
    // the BackdropFilter can blur everything beneath it.
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                // Dark semi-transparent base so the blur still carries a
                // strong glass tint instead of washing out.
                color: Colors.grey.shade900.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header — one label per step.
                  Text(
                    switch (_mode) {
                      _StepMode.edit => 'Edit Inventory',
                      _StepMode.confirm => 'Confirm Changes',
                      _StepMode.removeConfirm => 'Remove Item',
                    },
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.equipmentName,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Body — one view per step. Wrapped in a flexible
                  // scroll container so the brand/category fields don't
                  // overflow on shorter viewports.
                  Flexible(
                    child: SingleChildScrollView(
                      child: switch (_mode) {
                        _StepMode.edit => _buildEditForm(),
                        _StepMode.confirm => _buildConfirmView(),
                        _StepMode.removeConfirm => _buildRemoveConfirmView(),
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action bar. In edit mode, a red "Remove Item" button
                  // sits on the bottom-left; the Cancel / primary button
                  // group is right-aligned via a Spacer. The other two
                  // modes keep the simpler right-aligned layout.
                  Row(
                    children: [
                      if (_mode == _StepMode.edit)
                        ElevatedButton(
                          onPressed: _onRemovePressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Remove Item'),
                        ),
                      const Spacer(),
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
                      if (_mode == _StepMode.edit)
                        ElevatedButton(
                          onPressed: _onSavePressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(
                              0xFF0047BB,
                            ), // Brand Blue
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Review'),
                        )
                      else if (_mode == _StepMode.confirm) ...[
                        TextButton(
                          onPressed: _onBackToEdit,
                          child: const Text(
                            'Back',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _onConfirmPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Save'),
                        ),
                      ] else ...[
                        TextButton(
                          onPressed: _onBackToEdit,
                          child: const Text(
                            'Back',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _onRemoveConfirmed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Remove'),
                        ),
                      ],
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

  /// Edit-mode body: cover image preview with upload/paste controls,
  /// quantity stepper, storage / brand / category text fields, and a
  /// destructive Remove Item button at the bottom. Each editable field
  /// has a reset-to-initial helper.
  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Cover image preview + controls ──
        _buildImageSection(),
        const SizedBox(height: 16),

        // ── Quantity label + reset ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Quantity',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              onPressed: _resetQuantity,
              tooltip: 'Reset Quantity',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Quantity stepper row: [−] [text field] [+] ──
        // The text field accepts direct typing (digits-only) while the
        // buttons offer one-tap steps for quick adjustments.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CircleIconButton(
                icon: Icons.remove,
                onTap: () => _adjustQuantity(-1),
              ),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  // Digits only — the tryParse fallback in
                  // _onConfirmPressed is purely defensive thanks to this.
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              _CircleIconButton(
                icon: Icons.add,
                onTap: () => _adjustQuantity(1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Storage label + reset ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Storage Location',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              onPressed: _resetStorage,
              tooltip: 'Reset Storage',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Storage free-text input ──
        TextField(
          controller: _storageCtrl,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            hintText: 'e.g. A1, Shelf B...',
            hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Brand label + reset + autocomplete ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Brand',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              onPressed: _resetBrand,
              tooltip: 'Reset Brand',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AutocompleteField(
          controller: _brandCtrl,
          hint: 'Brand name',
          suggestions: _brandSuggestions,
          onSelect: (v) {
            _brandCtrl.text = v;
            _brandCtrl.selection = TextSelection.collapsed(offset: v.length);
            setState(() => _brandSuggestions = const []);
          },
        ),
        const SizedBox(height: 16),

        // ── Category label + reset + autocomplete ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Category',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              onPressed: _resetCategory,
              tooltip: 'Reset Category',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AutocompleteField(
          controller: _categoryCtrl,
          hint: 'Category',
          suggestions: _categorySuggestions,
          onSelect: (v) {
            _categoryCtrl.text = v;
            _categoryCtrl.selection = TextSelection.collapsed(offset: v.length);
            setState(() => _categorySuggestions = const []);
          },
        ),
      ],
    );
  }

  /// Cover-image controls. Mirrors the inventory create dialog: a
  /// glass-bordered 180px container that shows upload/paste buttons
  /// when empty and a fit-to-height preview (with a close button) once
  /// an image is staged.
  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cover Image',
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
                      // Fit-to-height so the full image is visible
                      // vertically, matching the create dialog.
                      Center(
                        child: SmartImage.memory(_imageBytes!,
                            fit: BoxFit.fitHeight),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _resetImage,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 18),
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
                        color: Colors.white.withValues(alpha: 0.2),
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
      ],
    );
  }

  /// Destructive confirmation step explaining that the equipment guide
  /// will also be deleted.
  Widget _buildRemoveConfirmView() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.4),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                'Remove this item?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'Any equipment guide created for this item will be removed '
            'as well, including every cover and section image. This '
            'cannot be undone.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// Confirm-mode body: renders a list of diff rows for any field that
  /// actually changed. If nothing differs we show a "No changes" hint so
  /// the user can still step back or cancel cleanly.
  Widget _buildConfirmView() {
    final int currentQty =
        int.tryParse(_qtyCtrl.text) ?? widget.initialQuantity;
    final String currentStorage = _storageCtrl.text.trim();
    final String currentBrand = _brandCtrl.text.trim();
    final String currentCategory = _categoryCtrl.text.trim();

    final List<Widget> changes = [];

    if (currentQty != widget.initialQuantity) {
      changes.add(
        _DiffRow(
          label: 'Quantity',
          oldValue: '${widget.initialQuantity}',
          newValue: '$currentQty',
        ),
      );
    }

    if (currentStorage != widget.initialStorage) {
      changes.add(
        _DiffRow(
          label: 'Storage',
          oldValue: widget.initialStorage.isEmpty
              ? '(none)'
              : widget.initialStorage,
          newValue: currentStorage.isEmpty ? '(none)' : currentStorage,
        ),
      );
    }

    if (currentBrand != widget.initialBrand) {
      changes.add(
        _DiffRow(
          label: 'Brand',
          oldValue: widget.initialBrand.isEmpty ? '(none)' : widget.initialBrand,
          newValue: currentBrand.isEmpty ? '(none)' : currentBrand,
        ),
      );
    }

    if (currentCategory != widget.initialCategory) {
      changes.add(
        _DiffRow(
          label: 'Category',
          oldValue: widget.initialCategory.isEmpty
              ? '(none)'
              : widget.initialCategory,
          newValue: currentCategory.isEmpty ? '(none)' : currentCategory,
        ),
      );
    }

    if (_imageBytes != null) {
      changes.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(Icons.image, size: 16, color: Colors.greenAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cover image will be replaced.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (changes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'No changes made.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'Confirm changes:',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          ...changes,
        ],
      ),
    );
  }
}

/// Small round icon button used for the quantity +/- stepper. Uses an
/// [InkWell] for the ripple and a thin dark border so it reads clearly
/// on the white stepper background.
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: Colors.black),
        ),
      ),
    );
  }
}

/// Half of the cover-image glass container: icon + two-line label,
/// tappable. Mirrors the widget with the same name in the inventory
/// create dialog so the two flows look identical.
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
            Icon(icon,
                color: Colors.white.withValues(alpha: 0.7), size: 36),
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

/// Single row of the confirmation diff. Renders as:
///
///     label: oldValue  →  newValue
///
/// with the old value struck through in red and the new value highlighted
/// in green so the change direction is immediately obvious.
class _DiffRow extends StatelessWidget {
  final String label;
  final String oldValue;
  final String newValue;

  const _DiffRow({
    required this.label,
    required this.oldValue,
    required this.newValue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.white),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  TextSpan(
                    text: oldValue,
                    style: const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.redAccent,
                    ),
                  ),
                  const TextSpan(text: '  →  '),
                  TextSpan(
                    text: newValue,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text field with a simple suggestion drop-down underneath. Used for
/// the brand and category inputs so the admin can re-use existing
/// taxonomy values without typos. Mirrors the autocomplete pattern in
/// the inventory create dialog.
class _AutocompleteField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final List<String> suggestions;
  final ValueChanged<String> onSelect;

  const _AutocompleteField({
    required this.controller,
    required this.hint,
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
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
              itemBuilder: (ctx, i) => ListTile(
                dense: true,
                title: Text(
                  suggestions[i],
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => onSelect(suggestions[i]),
              ),
            ),
          ),
      ],
    );
  }
}
