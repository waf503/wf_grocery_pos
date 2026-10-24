import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../models/cash_session.dart';

/// Desglose del efectivo de un turno: de dónde sale el total en caja y, si
/// la caja ya se cerró, lo contado y la diferencia. Se reutiliza en el
/// cierre, en el resultado del cierre y en el detalle del historial.
class SessionBreakdown extends StatelessWidget {
  const SessionBreakdown({super.key, required this.session});

  final CashSession session;

  @override
  Widget build(BuildContext context) {
    final difference = session.difference;
    return Column(
      children: [
        _Row('Fondo inicial', session.openingAmount),
        // Las ventas en efectivo suman lo que ENTREGÓ el cliente; el vuelto
        // aparece aparte como salida. Sin vueltos es simplemente lo vendido.
        _Row(session.changeCents > 0 ? 'Efectivo recibido en ventas' : 'Ventas en efectivo', session.salesTotal),
        if (session.changeCents > 0) _Row('Vueltos entregados', -session.changeTotal),
        if (session.depositsCents > 0) _Row('Ingresos', session.depositsTotal),
        if (session.customerPaymentsCents > 0) _Row('Abonos de clientes', session.customerPaymentsTotal),
        if (session.withdrawalsCents > 0) _Row('Retiros', -session.withdrawalsTotal),
        if (session.voidsCents > 0) _Row('Devoluciones por anulación', -session.voidsTotal),
        const Divider(),
        _Row('Total en caja', session.expectedAmount, bold: true),
        if (session.closingCountedAmount != null) _Row('Contado', session.closingCountedAmount!, bold: true),
        if (difference != null) _DifferenceRow(difference: difference),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});

  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(formatCurrency(value), style: style)],
      ),
    );
  }
}

class _DifferenceRow extends StatelessWidget {
  const _DifferenceRow({required this.difference});

  /// En dólares: positivo = sobrante, negativo = faltante.
  final double difference;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBalanced = difference == 0;
    final label = isBalanced ? 'Caja cuadrada' : (difference > 0 ? 'Sobrante' : 'Faltante');
    final color = isBalanced ? Colors.green.shade700 : (difference > 0 ? Colors.orange.shade800 : scheme.error);
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(isBalanced ? formatCurrency(0) : formatCurrency(difference.abs()), style: style),
        ],
      ),
    );
  }
}
