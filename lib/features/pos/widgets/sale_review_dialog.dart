import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/format/formatters.dart';
import '../../../models/cart_item.dart';
import '../../../models/sale.dart';
import 'checkout_dialog.dart';

/// Qué decidió el vendedor al revisar el ticket.
enum SaleReviewDecision {
  /// Todo está bien: registrar la venta.
  confirm,

  /// Volver al cobro para corregir la forma de pago o lo que dio el cliente.
  back,

  /// Abandonar el cobro (el carrito se conserva para editarlo).
  cancel,
}

/// Paso de REVISIÓN antes de registrar la venta: muestra el ticket como saldrá
/// (productos, cantidades, total, forma de pago, lo que entregó el cliente y el
/// vuelto) para que el vendedor lo corrobore. Nada se guarda hasta confirmar.
///
/// Cerrar el cuadro con Esc equivale a volver al cobro (no se pierde lo escrito).
Future<SaleReviewDecision> showSaleReviewDialog(
  BuildContext context, {
  required List<CartItem> items,
  required int totalCents,
  required PaymentChoice payment,
  String? customerName,
}) async {
  final decision = await showDialog<SaleReviewDecision>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SaleReviewDialog(
      items: items,
      totalCents: totalCents,
      payment: payment,
      customerName: customerName,
    ),
  );
  return decision ?? SaleReviewDecision.back;
}

class _SaleReviewDialog extends StatelessWidget {
  const _SaleReviewDialog({
    required this.items,
    required this.totalCents,
    required this.payment,
    this.customerName,
  });

  final List<CartItem> items;
  final int totalCents;
  final PaymentChoice payment;
  final String? customerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCash = payment.method == PaymentMethod.cash;
    // Sin monto escrito se toma como pago exacto.
    final tendered = isCash ? (payment.tenderedCents ?? totalCents) : null;
    final change = tendered == null ? null : tendered - totalCents;
    final savings = items.fold<int>(0, (sum, item) => sum + item.savingsCents);
    final itemCount = items.fold<double>(0, (sum, item) => sum + item.quantity);

    return CallbackShortcuts(
      // Esc = volver al cobro (el cuadro no se cierra tocando fuera, para no
      // abandonar una venta por accidente).
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(SaleReviewDecision.back),
      },
      child: AlertDialog(
        title: const Text('Revisar venta'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verifica el ticket antes de registrar la venta.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              // Los renglones del ticket; si son muchos, se desplazan.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 52,
                                  child: Text(
                                    '${formatQuantity(item.quantity)}${item.product.allowsDecimals ? ' ${item.product.unit}' : ''} ×',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.product.name),
                                      Text(
                                        '${formatCurrency(item.product.price)} c/u'
                                        '${item.savingsCents > 0 ? ' · combo: ahorra ${formatCurrency(item.savingsCents / 100)}' : ''}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(formatCurrency(item.subtotal)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 24),
              if (savings > 0)
                _line(
                  'Ahorro por combos',
                  formatCurrency(savings / 100),
                  theme,
                ),
              _line(
                'Total (${formatQuantity(itemCount)} artículos)',
                formatCurrency(totalCents / 100),
                theme,
                big: true,
              ),
              const SizedBox(height: 8),
              _line('Forma de pago', payment.method.label, theme),
              if (customerName != null) _line('Cliente', customerName!, theme),
              if (tendered != null)
                _line('Recibido', formatCurrency(tendered / 100), theme),
              if (change != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: change > 0
                        ? Colors.green.shade50
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        change > 0 ? 'Vuelto a entregar' : 'Pago exacto',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        change > 0
                            ? formatCurrency(change / 100)
                            : formatCurrency(0),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: change > 0
                              ? Colors.green.shade800
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (payment.method == PaymentMethod.credit)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Se cargará a la cuenta del cliente (fiado): no entra dinero a la caja.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(SaleReviewDecision.cancel),
            child: Text('Cancelar', style: TextStyle(color: scheme.error)),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(SaleReviewDecision.back),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(isCash ? 'Corregir pago' : 'Volver'),
          ),
          // Enter confirma: con un cobro rápido son dos Enter (monto y confirmar).
          FilledButton.icon(
            autofocus: true,
            onPressed: () =>
                Navigator.of(context).pop(SaleReviewDecision.confirm),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirmar venta'),
          ),
        ],
      ),
    );
  }

  Widget _line(
    String label,
    String value,
    ThemeData theme, {
    bool big = false,
  }) {
    final style = big
        ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
