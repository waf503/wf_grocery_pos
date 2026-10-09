import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../models/sale.dart';

/// Total de las ventas vigentes (las anuladas no cuentan), en centavos y
/// sin importar el método de pago.
int activeSalesTotalCents(List<Sale> sales) =>
    sales.where((s) => !s.isVoided).fold(0, (sum, s) => sum + s.totalCents);

int activeSalesCount(List<Sale> sales) => sales.where((s) => !s.isVoided).length;

/// Cantidad y total de las ventas vigentes de un método de pago.
typedef MethodTotal = ({int count, int totalCents});

/// Ventas vigentes agrupadas por método de pago; siempre incluye los tres
/// métodos (en cero si no hubo ventas).
Map<PaymentMethod, MethodTotal> totalsByPaymentMethod(List<Sale> sales) {
  final result = {for (final m in PaymentMethod.values) m: (count: 0, totalCents: 0)};
  for (final sale in sales) {
    if (sale.isVoided) continue;
    final current = result[sale.paymentMethod]!;
    result[sale.paymentMethod] = (count: current.count + 1, totalCents: current.totalCents + sale.totalCents);
  }
  return result;
}

/// Ventas del turno por método de pago. Solo el efectivo mueve la caja; el
/// pago electrónico y el fiado son informativos (para cuadrar contra el
/// datáfono y saber cuánto se dio a crédito).
class PaymentMethodSummary extends StatelessWidget {
  const PaymentMethodSummary({super.key, required this.sales});

  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final totals = totalsByPaymentMethod(sales);
    return Column(
      children: [
        for (final entry in totals.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text('${entry.key.label} (${entry.value.count})')),
                Text(formatCurrency(entry.value.totalCents / 100)),
              ],
            ),
          ),
        const Divider(),
        Row(
          children: [
            Expanded(
              child: Text(
                'Total ventas (${activeSalesCount(sales)})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              formatCurrency(activeSalesTotalCents(sales) / 100),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}

/// Resumen de las ventas hechas en un turno: folio, hora, método de pago,
/// cliente y total de cada una. Las anuladas se muestran tachadas.
class SessionSalesList extends StatelessWidget {
  const SessionSalesList({super.key, required this.sales, this.shrinkWrap = true});

  final List<Sale> sales;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (sales.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Aún no hay ventas en este turno.'),
      );
    }
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sales.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final sale = sales[index];
        final strike = sale.isVoided
            ? TextStyle(decoration: TextDecoration.lineThrough, color: scheme.onSurfaceVariant)
            : null;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            sale.isVoided ? Icons.cancel_outlined : Icons.receipt_long_outlined,
            color: sale.isVoided ? scheme.error : null,
          ),
          title: Text(
            '${sale.receiptNumber} · ${formatQuantity(sale.itemCount)} artículos · ${sale.paymentMethod.label}',
            style: strike,
          ),
          subtitle: Text([
            dateTimeFormat.format(sale.date),
            if (sale.customerName != null) sale.customerName!,
            if (sale.isVoided) 'ANULADA',
          ].join(' · ')),
          trailing: Text(
            formatCurrency(sale.total),
            style: TextStyle(fontWeight: FontWeight.bold, decoration: strike?.decoration),
          ),
        );
      },
    );
  }
}
