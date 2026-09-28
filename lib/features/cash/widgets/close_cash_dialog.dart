import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../models/cash_session.dart';

Future<double?> showCloseCashDialog(BuildContext context, CashSession session) {
  final controller = TextEditingController(text: session.expectedAmount.toStringAsFixed(2));
  final formKey = GlobalKey<FormState>();
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cerrar caja'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow(context, 'Fondo inicial', session.openingAmount),
              _summaryRow(context, 'Ventas', session.salesTotal),
              _summaryRow(context, 'Ingresos', session.depositsTotal),
              _summaryRow(context, 'Retiros', -session.withdrawalsTotal),
              const Divider(),
              _summaryRow(context, 'Esperado en caja', session.expectedAmount, bold: true),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Monto contado físicamente'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => double.tryParse(v ?? '') == null ? 'Ingresa un monto válido' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(context).pop(double.parse(controller.text));
            }
          },
          child: const Text('Cerrar caja'),
        ),
      ],
    ),
  );
}

Widget _summaryRow(BuildContext context, String label, double value, {bool bold = false}) {
  final style = bold
      ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
      : Theme.of(context).textTheme.bodyMedium;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(formatCurrency(value), style: style),
      ],
    ),
  );
}
