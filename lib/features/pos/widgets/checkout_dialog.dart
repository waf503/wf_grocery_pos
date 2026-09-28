import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../models/sale.dart';

Future<PaymentMethod?> showPaymentMethodDialog(BuildContext context, {required double total}) {
  return showDialog<PaymentMethod>(
    context: context,
    builder: (context) => _PaymentMethodDialog(total: total),
  );
}

class _PaymentMethodDialog extends StatefulWidget {
  const _PaymentMethodDialog({required this.total});

  final double total;

  @override
  State<_PaymentMethodDialog> createState() => _PaymentMethodDialogState();
}

class _PaymentMethodDialogState extends State<_PaymentMethodDialog> {
  PaymentMethod _selected = PaymentMethod.cash;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cobrar venta'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatCurrency(widget.total),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Forma de pago'),
            const SizedBox(height: 8),
            RadioGroup<PaymentMethod>(
              groupValue: _selected,
              onChanged: (value) => setState(() => _selected = value!),
              child: Column(
                children: [
                  for (final method in PaymentMethod.values)
                    RadioListTile<PaymentMethod>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(method.label),
                      value: method,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

Future<void> showReceiptDialog(BuildContext context, Sale sale) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Venta registrada'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 32),
                Text(dateTimeFormat.format(sale.date)),
              ],
            ),
            const SizedBox(height: 12),
            ...sale.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text('${item.quantity}x ${item.productName}')),
                    Text(formatCurrency(item.subtotal)),
                  ],
                ),
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  formatCurrency(sale.total),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Pago: ${sale.paymentMethod.label}'),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Listo'),
        ),
      ],
    ),
  );
}
