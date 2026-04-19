// PixelVault — Inventory edit dialog.
//
// Modal dialog used from the inventory list when an admin taps the edit
// icon on an equipment card. It presents a two-step flow:
//
//   1. Edit mode    — lets the user change quantity (via +/- buttons or a
//                     text field) and storage location (free-text).
//   2. Confirm mode — shows a diff of what changed and requires the user
//                     to confirm before the changes are returned.
//
// The dialog returns an [InventoryEditResult] (or null if cancelled) via
// [Navigator.pop]. Callers should inspect [InventoryEditResult.changed] to
// decide whether to persist the update.

import 'dart:ui'; // For ImageFilter used by BackdropFilter.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // FilteringTextInputFormatter.

/// Result returned by [showInventoryEditDialog] after the user confirms.
///
/// [changed] is true if either [quantity] or [storage] differs from the
/// initial values the dialog was opened with. Callers can short-circuit
/// persistence when this flag is false.
class InventoryEditResult {
  final int quantity;
  final String storage;
  final bool changed;

  InventoryEditResult({
    required this.quantity,
    required this.storage,
    required this.changed,
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
}) {
  return showDialog<InventoryEditResult>(
    context: context,
    barrierColor: Colors.black54, // Slight darken so the dialog pops.
    barrierDismissible: false,
    builder: (context) => _InventoryEditDialog(
      equipmentName: equipmentName,
      initialQuantity: initialQuantity,
      initialStorage: initialStorage,
    ),
  );
}

/// Internal two-step state: edit form → confirmation diff.
enum _StepMode { edit, confirm }

class _InventoryEditDialog extends StatefulWidget {
  final String equipmentName;
  final int initialQuantity;
  final String initialStorage;

  const _InventoryEditDialog({
    required this.equipmentName,
    required this.initialQuantity,
    required this.initialStorage,
  });

  @override
  State<_InventoryEditDialog> createState() => _InventoryEditDialogState();
}

class _InventoryEditDialogState extends State<_InventoryEditDialog> {
  // Controllers keep the quantity and storage fields editable from both
  // the text inputs and the helper buttons (+/-, reset).
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _storageCtrl;

  _StepMode _mode = _StepMode.edit;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.initialQuantity}');
    _storageCtrl = TextEditingController(text: widget.initialStorage);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _storageCtrl.dispose();
    super.dispose();
  }

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

    final bool changed =
        (currentQty != widget.initialQuantity) ||
        (currentStorage != widget.initialStorage);

    Navigator.of(context).pop(
      InventoryEditResult(
        quantity: currentQty,
        storage: currentStorage,
        changed: changed,
      ),
    );
  }

  /// Handler for the "Back" button in confirm mode — returns to edit.
  void _onBackToEdit() => setState(() => _mode = _StepMode.edit);

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

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Glassmorphism wrapper — the Dialog itself is fully transparent so
    // the BackdropFilter can blur everything beneath it.
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
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
                // Header — swaps between "Edit Inventory" and "Confirm
                // Changes" depending on the current step.
                Text(
                  _mode == _StepMode.edit
                      ? 'Edit Inventory'
                      : 'Confirm Changes',
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

                // Body — either the edit form or the confirmation diff.
                if (_mode == _StepMode.edit)
                  _buildEditForm()
                else
                  _buildConfirmView(),

                const SizedBox(height: 24),

                // Action bar. Cancel is always present; the primary
                // button(s) depend on the current step. Using a spread
                // in the else branch avoids an extra nested Row.
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
                    else ...[
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
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Edit-mode body: quantity stepper + storage text field, each with a
  /// "reset to initial value" button for quick undo.
  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            color: Colors.white.withValues(alpha: 0.05),
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
                    color: Colors.white,
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
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. A1, Shelf B...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
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
      ],
    );
  }

  /// Confirm-mode body: renders a list of diff rows for any field that
  /// actually changed. If nothing differs we show a "No changes" hint so
  /// the user can still step back or cancel cleanly.
  Widget _buildConfirmView() {
    final int currentQty =
        int.tryParse(_qtyCtrl.text) ?? widget.initialQuantity;
    final String currentStorage = _storageCtrl.text.trim();

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
/// [InkWell] for the ripple and a thin white border for the glass look.
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: Colors.white),
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
