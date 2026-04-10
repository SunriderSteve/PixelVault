import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For FilteringTextInputFormatter

/// result returned after final Save
class InventoryEditResult {
  final int quantity;
  final String cabinet;
  final bool changed;

  InventoryEditResult({
    required this.quantity,
    required this.cabinet,
    required this.changed,
  });
}

/// open edit dialog for quantity and cabinet
Future<InventoryEditResult?> showInventoryEditDialog(
  BuildContext context, {
  required String equipmentName,
  required int initialQuantity,
  required String initialCabinet,
}) {
  return showDialog<InventoryEditResult>(
    context: context,
    barrierColor: Colors.black54, // Darken background slightly
    barrierDismissible: false,
    builder: (context) => _InventoryEditDialog(
      equipmentName: equipmentName,
      initialQuantity: initialQuantity,
      initialCabinet: initialCabinet,
    ),
  );
}

enum _StepMode { edit, confirm }

class _InventoryEditDialog extends StatefulWidget {
  final String equipmentName;
  final int initialQuantity;
  final String initialCabinet;

  const _InventoryEditDialog({
    required this.equipmentName,
    required this.initialQuantity,
    required this.initialCabinet,
  });

  @override
  State<_InventoryEditDialog> createState() => _InventoryEditDialogState();
}

class _InventoryEditDialogState extends State<_InventoryEditDialog> {
  // Use controllers for both fields to manage text input
  late TextEditingController _qtyCtrl;
  late TextEditingController _cabinetCtrl;

  _StepMode _mode = _StepMode.edit;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.initialQuantity}');
    _cabinetCtrl = TextEditingController(text: widget.initialCabinet);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _cabinetCtrl.dispose();
    super.dispose();
  }

  void _onSavePressed() {
    // Validate quantity on save: if empty or invalid, revert to initial
    if (_qtyCtrl.text.isEmpty) {
      _qtyCtrl.text = '${widget.initialQuantity}';
    }

    setState(() {
      _mode = _StepMode.confirm;
    });
  }

  void _onConfirmPressed() {
    final int currentQty =
        int.tryParse(_qtyCtrl.text) ?? widget.initialQuantity;
    final String currentCab = _cabinetCtrl.text.trim();

    final bool changed =
        (currentQty != widget.initialQuantity) ||
        (currentCab != widget.initialCabinet);

    Navigator.of(context).pop(
      InventoryEditResult(
        quantity: currentQty,
        cabinet: currentCab,
        changed: changed,
      ),
    );
  }

  void _onBackToEdit() {
    setState(() {
      _mode = _StepMode.edit;
    });
  }

  // Helper to safely increment/decrement
  void _adjustQuantity(int delta) {
    int current = int.tryParse(_qtyCtrl.text) ?? widget.initialQuantity;
    int newVal = current + delta;
    if (newVal < 0) newVal = 0;
    _qtyCtrl.text = '$newVal';
  }

  void _resetQuantity() {
    _qtyCtrl.text = '${widget.initialQuantity}';
  }

  void _resetCabinet() {
    _cabinetCtrl.text = widget.initialCabinet;
  }

  @override
  Widget build(BuildContext context) {
    // Glassmorphism Container
    return Dialog(
      backgroundColor: Colors.transparent, // Important for glass effect
      elevation: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade900.withValues(alpha:0.85), // Dark glass base
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha:0.1),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
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
                    color: Colors.white.withValues(alpha:0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Body Content
                if (_mode == _StepMode.edit)
                  _buildEditForm()
                else
                  _buildConfirmView(),

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(), // Cancel
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white.withValues(alpha:0.6)),
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
                    else
                      Row(
                        children: [
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

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quantity Controls
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
            // Reset Button
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CircleIconButton(
                icon: Icons.remove,
                onTap: () => _adjustQuantity(-1),
              ),
              // Editable Input Field
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

        // Cabinet Input
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Cabinet Location',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            // Reset Button
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              onPressed: _resetCabinet,
              tooltip: 'Reset Cabinet',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _cabinetCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. A1, Shelf B...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha:0.4)),
            filled: true,
            fillColor: Colors.white.withValues(alpha:0.05),
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

  Widget _buildConfirmView() {
    final changes = <Widget>[];
    final int currentQty =
        int.tryParse(_qtyCtrl.text) ?? widget.initialQuantity;
    final String currentCab = _cabinetCtrl.text.trim();

    if (currentQty != widget.initialQuantity) {
      changes.add(
        _DiffRow(
          label: 'Quantity',
          oldValue: '${widget.initialQuantity}',
          newValue: '$currentQty',
        ),
      );
    }

    if (currentCab != widget.initialCabinet) {
      changes.add(
        _DiffRow(
          label: 'Cabinet',
          oldValue: widget.initialCabinet.isEmpty
              ? '(none)'
              : widget.initialCabinet,
          newValue: currentCab.isEmpty ? '(none)' : currentCab,
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
        color: Colors.white.withValues(alpha:0.05),
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
            border: Border.all(color: Colors.white.withValues(alpha:0.3)),
          ),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

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
                    style: TextStyle(color: Colors.white.withValues(alpha:0.6)),
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
