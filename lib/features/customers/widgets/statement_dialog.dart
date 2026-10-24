import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format/formatters.dart';
import '../../../models/customer.dart';
import '../../../state/customer_provider.dart';

/// Estado de cuenta del cliente: cargos (fiado), abonos y anulaciones.
Future<void> showStatementDialog(BuildContext context, Customer customer) {
  return showDialog(
    context: context,
    builder: (context) => _StatementDialog(customerId: customer.id),
  );
}

class _StatementDialog extends StatelessWidget {
  const _StatementDialog({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomerProvider>();
    final customer = provider.byId(customerId);
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text('Estado de cuenta · ${customer?.name ?? ''}'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo pendiente: ${formatCurrency(customer?.balance ?? 0)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<CustomerMovement>>(
                stream: provider.watchMovements(customerId),
                builder: (context, snapshot) {
                  final movements = snapshot.data ?? const [];
                  if (movements.isEmpty) {
                    return const Center(child: Text('Sin movimientos todavía.'));
                  }
                  return ListView.separated(
                    itemCount: movements.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final m = movements[index];
                      final isCharge = m.type == CustomerMovementType.charge;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${m.type.label} · ${m.note}'),
                        subtitle: Text(
                          '${dateTimeFormat.format(m.date)}${m.receivedBy != null ? ' · recibió ${m.receivedBy}' : ''}',
                        ),
                        trailing: Text(
                          '${isCharge ? '+' : '-'}${formatCurrency(m.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isCharge ? scheme.error : Colors.green.shade700,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
      ],
    );
  }
}
