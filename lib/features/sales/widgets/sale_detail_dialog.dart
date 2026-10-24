import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../models/sale.dart';

/// Detalle de una venta. Devuelve el motivo escrito si el usuario eligió
/// anularla; `null` si solo la consultó o canceló.
Future<String?> showSaleDetailDialog(BuildContext context, Sale sale) {
  return showDialog<String>(
    context: context,
    builder: (context) => _SaleDetailDialog(sale: sale),
  );
}

class _SaleDetailDialog extends StatefulWidget {
  const _SaleDetailDialog({required this.sale});

  final Sale sale;

  @override
  State<_SaleDetailDialog> createState() => _SaleDetailDialogState();
}

class _SaleDetailDialogState extends State<_SaleDetailDialog> {
  final _reason = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _confirmingVoid = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String get _voidConsequences {
    switch (widget.sale.paymentMethod) {
      case PaymentMethod.cash:
        return 'Se devuelven las existencias y se registra un retiro en la caja abierta.';
      case PaymentMethod.credit:
        return 'Se devuelven las existencias y se descuenta la deuda del cliente.';
      case PaymentMethod.card:
        return 'Se devuelven las existencias. El reembolso de la tarjeta se hace fuera del sistema.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(sale.receiptNumber)),
          if (sale.isVoided)
            Chip(
              label: const Text('ANULADA'),
              backgroundColor: scheme.errorContainer,
              labelStyle: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.bold),
            ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateTimeFormat.format(sale.date)),
              Text('Pago: ${sale.paymentMethod.label}'),
              if (sale.tenderedCents != null) ...[
                Text('Recibido: ${formatCurrency(sale.tendered!)}'),
                if ((sale.changeCents ?? 0) > 0) Text('Vuelto: ${formatCurrency(sale.change!)}'),
              ],
              if (sale.customerName != null) Text('Cliente: ${sale.customerName}'),
              const SizedBox(height: 12),
              for (final item in sale.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text('${formatQuantity(item.quantity)}x ${item.productName}')),
                      Text(formatCurrency(item.subtotal)),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(formatCurrency(sale.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              if (sale.isVoided) ...[
                const SizedBox(height: 12),
                Text(
                  'Anulada el ${dateTimeFormat.format(sale.voidedAt!)}\nMotivo: ${sale.voidReason ?? '-'}',
                  style: TextStyle(color: scheme.error),
                ),
              ],
              if (_confirmingVoid) ...[
                const SizedBox(height: 16),
                Text(_voidConsequences, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _reason,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Motivo de la anulación'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_confirmingVoid ? 'Cancelar' : 'Cerrar'),
        ),
        if (!sale.isVoided && !_confirmingVoid)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () => setState(() => _confirmingVoid = true),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Anular venta'),
          ),
        if (_confirmingVoid)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () {
              if (_formKey.currentState!.validate()) Navigator.of(context).pop(_reason.text.trim());
            },
            child: const Text('Confirmar anulación'),
          ),
      ],
    );
  }
}
