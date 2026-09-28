import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/formatters.dart';
import '../../models/cash_session.dart';
import '../../state/cash_provider.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/stat_card.dart';
import '../../shared/widgets/stat_grid.dart';
import 'widgets/close_cash_dialog.dart';
import 'widgets/movement_dialog.dart';
import 'widgets/open_cash_dialog.dart';

class CashScreen extends StatelessWidget {
  const CashScreen({super.key});

  Future<void> _openCash(BuildContext context, CashProvider provider) async {
    final amount = await showOpenCashDialog(context);
    if (amount != null) provider.openSession(amount);
  }

  Future<void> _registerMovement(BuildContext context, CashProvider provider, CashMovementType type) async {
    final result = await showMovementDialog(context, type: type);
    if (result != null) {
      provider.registerMovement(result.type, result.amount, result.note);
    }
  }

  Future<void> _closeCash(BuildContext context, CashProvider provider, CashSession session) async {
    final counted = await showCloseCashDialog(context, session);
    if (counted != null) provider.closeSession(counted);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CashProvider>();
    final session = provider.current;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Caja',
            subtitle: session != null
                ? 'Abierta desde ${dateTimeFormat.format(session.openedAt)}'
                : 'La caja está cerrada',
            actions: [
              if (session == null)
                FilledButton.icon(
                  onPressed: () => _openCash(context, provider),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Abrir caja'),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: () => _registerMovement(context, provider, CashMovementType.deposit),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Ingreso'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _registerMovement(context, provider, CashMovementType.withdrawal),
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Retiro'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _closeCash(context, provider, session),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Cerrar caja'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: session == null
                ? const EmptyState(
                    icon: Icons.point_of_sale_outlined,
                    message: 'Abre la caja para comenzar a registrar\nventas y movimientos de efectivo.',
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatGrid(
                          children: [
                            StatCard(
                              label: 'Fondo inicial',
                              value: formatCurrency(session.openingAmount),
                              icon: Icons.savings_outlined,
                            ),
                            StatCard(
                              label: 'Ventas',
                              value: formatCurrency(session.salesTotal),
                              icon: Icons.point_of_sale_outlined,
                              color: Colors.green,
                            ),
                            StatCard(
                              label: 'Ingresos / Retiros',
                              value:
                                  '+${formatCurrency(session.depositsTotal)} / -${formatCurrency(session.withdrawalsTotal)}',
                              icon: Icons.swap_vert,
                              color: Colors.orange,
                            ),
                            StatCard(
                              label: 'Esperado en caja',
                              value: formatCurrency(session.expectedAmount),
                              icon: Icons.account_balance_wallet_outlined,
                              color: Colors.blue,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text('Movimientos', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (session.movements.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: EmptyState(icon: Icons.receipt_long_outlined, message: 'Aún no hay movimientos.'),
                          )
                        else
                          Card(
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: session.movements.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final movement = session.movements.reversed.toList()[index];
                                final isNegative = movement.type == CashMovementType.withdrawal;
                                return ListTile(
                                  leading: Icon(
                                    switch (movement.type) {
                                      CashMovementType.sale => Icons.point_of_sale,
                                      CashMovementType.deposit => Icons.arrow_downward,
                                      CashMovementType.withdrawal => Icons.arrow_upward,
                                    },
                                  ),
                                  title: Text(movement.note),
                                  subtitle: Text(dateTimeFormat.format(movement.time)),
                                  trailing: Text(
                                    '${isNegative ? '-' : '+'}${formatCurrency(movement.amount)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isNegative ? Theme.of(context).colorScheme.error : Colors.green,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
