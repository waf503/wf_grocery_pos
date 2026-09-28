import 'package:flutter/material.dart';

import '../../../models/cash_session.dart';

class CashMovementResult {
  CashMovementResult(this.type, this.amount, this.note);
  final CashMovementType type;
  final double amount;
  final String note;
}

Future<CashMovementResult?> showMovementDialog(BuildContext context, {required CashMovementType type}) {
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final title = type == CashMovementType.deposit ? 'Registrar ingreso' : 'Registrar retiro';

  return showDialog<CashMovementResult>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: amountController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Monto'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final value = double.tryParse(v ?? '');
                if (value == null || value <= 0) return 'Ingresa un monto válido';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Motivo'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(context).pop(
                CashMovementResult(type, double.parse(amountController.text), noteController.text.trim()),
              );
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}
