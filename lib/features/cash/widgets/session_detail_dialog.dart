import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format/formatters.dart';
import '../../../models/cash_session.dart';
import '../../../models/sale.dart';
import '../../../state/sales_provider.dart';
import 'session_sales_list.dart';
import 'session_breakdown.dart';

/// Resultado del cierre (justo después de cerrar) y detalle de un turno del
/// historial: desglose, diferencia, ventas por método de pago y movimientos.
Future<void> showSessionDetailDialog(
  BuildContext context,
  CashSession session, {
  String title = 'Detalle del turno',
}) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Abierta ${dateTimeFormat.format(session.openedAt)}'
                '${session.closedAt != null ? '  ·  Cerrada ${dateTimeFormat.format(session.closedAt!)}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (session.openedBy != null || session.closedBy != null)
                Text(
                  [
                    if (session.openedBy != null) 'Abrió: ${session.openedBy}',
                    if (session.closedBy != null) 'Cerró: ${session.closedBy}',
                  ].join('  ·  '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              SessionBreakdown(session: session),
              const SizedBox(height: 16),
              StreamBuilder<List<Sale>>(
                stream: context.read<SalesProvider>().watchSession(session.id),
                builder: (context, snapshot) {
                  final sales = snapshot.data ?? const [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ventas por método de pago',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      PaymentMethodSummary(sales: sales),
                      const Divider(),
                      SessionSalesList(sales: sales),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Movimientos (${session.movements.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              if (session.movements.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Sin movimientos.'),
                )
              else
                for (final m in session.movements)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${m.type.label} · ${m.note}'),
                    subtitle: Text(
                      '${dateTimeFormat.format(m.time)}${m.createdBy != null ? ' · ${m.createdBy}' : ''}',
                    ),
                    trailing: Text(
                      '${m.type.isOutflow ? '-' : '+'}${formatCurrency(m.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: m.type.isOutflow
                            ? Theme.of(context).colorScheme.error
                            : Colors.green.shade700,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
