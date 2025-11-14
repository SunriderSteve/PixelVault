import 'package:flutter/material.dart';

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
  late int _draftQuantity; // user editable quantity
  late String _draftCabinet; // user editable cabinet
  _StepMode _mode = _StepMode.edit; // current dialog state

  final TextEditingController _qtyCtl = TextEditingController();
  final TextEditingController _cabCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draftQuantity = widget.initialQuantity;
    _draftCabinet = widget.initialCabinet;
    _qtyCtl.text = _draftQuantity.toString();
    _cabCtl.text = _draftCabinet;
  }

  @override
  void dispose() {
    _qtyCtl.dispose();
    _cabCtl.dispose();
    super.dispose();
  }

  bool get _hasChanges =>
      _draftQuantity != widget.initialQuantity ||
      _draftCabinet != widget.initialCabinet;

  void _applyQty(int delta) {
    final next = (_draftQuantity + delta).clamp(0, 1 << 31);
    setState(() {
      _draftQuantity = next;
      _qtyCtl.text = _draftQuantity.toString();
    });
  }

  void _onQtyTextChanged(String v) {
    final parsed = int.tryParse(v);
    setState(() {
      _draftQuantity = (parsed == null || parsed < 0) ? 0 : parsed;
      if (_draftQuantity.toString() != v) {
        _qtyCtl.text = _draftQuantity.toString();
        _qtyCtl.selection = TextSelection.fromPosition(
          TextPosition(offset: _qtyCtl.text.length),
        );
      }
    });
  }

  void _onCabinetChanged(String v) {
    setState(() => _draftCabinet = v);
  }

  void _onReset() {
    setState(() {
      _draftQuantity = widget.initialQuantity;
      _draftCabinet = widget.initialCabinet;
      _qtyCtl.text = _draftQuantity.toString();
      _cabCtl.text = _draftCabinet;
      _mode = _StepMode.edit;
    });
  }

  void _onCancel() {
    Navigator.of(context).pop(null);
  }

  void _onPrimarySave() {
    if (!_hasChanges) {
      Navigator.of(context).pop(null); // treat as cancel when no changes
      return;
    }
    setState(() => _mode = _StepMode.confirm);
  }

  void _onFinalSave() {
    // writing to Gist not implemented yet
    // close dialog and return result to caller
    final res = InventoryEditResult(
      quantity: _draftQuantity,
      cabinet: _draftCabinet,
      changed: _hasChanges,
    );
    Navigator.of(context).pop(res);
  }

  @override
  Widget build(BuildContext context) {
    final isConfirm = _mode == _StepMode.confirm;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(isConfirm ? 'Confirm changes' : 'Edit inventory'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      content: isConfirm
          ? _buildConfirmContent(theme)
          : _buildEditContent(theme),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        Row(
          children: [
            TextButton(onPressed: _onReset, child: const Text('Reset')),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                if (isConfirm) {
                  setState(() => _mode = _StepMode.edit); // back to edit
                } else {
                  _onCancel();
                }
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
        FilledButton(
          onPressed: isConfirm ? _onFinalSave : _onPrimarySave,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildEditContent(ThemeData theme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.equipmentName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          Text('Quantity', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              _NudgeButton(label: '-10', onTap: () => _applyQty(-10)),
              const SizedBox(width: 8),
              _NudgeButton(label: '-1', onTap: () => _applyQty(-1)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _qtyCtl,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: false,
                    decimal: false,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Enter quantity',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _onQtyTextChanged,
                ),
              ),
              const SizedBox(width: 12),
              _NudgeButton(label: '+1', onTap: () => _applyQty(1)),
              const SizedBox(width: 8),
              _NudgeButton(label: '+10', onTap: () => _applyQty(10)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Cabinet', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _cabCtl,
            decoration: const InputDecoration(
              hintText: 'e.g. A1, B3',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _onCabinetChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmContent(ThemeData theme) {
    final changes = <Widget>[];

    if (_draftQuantity != widget.initialQuantity) {
      changes.add(
        _DiffRow(
          label: 'Quantity',
          oldValue: widget.initialQuantity.toString(),
          newValue: _draftQuantity.toString(),
        ),
      );
    }
    if (_draftCabinet != widget.initialCabinet) {
      changes.add(
        _DiffRow(
          label: 'Cabinet',
          oldValue: widget.initialCabinet,
          newValue: _draftCabinet,
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Are you sure you want to make the following change(s)?'),
          const SizedBox(height: 12),
          ...changes,
        ],
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NudgeButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton(onPressed: onTap, child: Text(label)),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(text: '$label: '),
            TextSpan(text: oldValue),
            const TextSpan(text: '  >>  '),
            const TextSpan(text: ''), // spacer to avoid formatting confusion
            TextSpan(
              text: newValue,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
