import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/formatters.dart';
import '../../models/cash_session.dart';
import '../../models/sale.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/feedback_alert.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/stat_card.dart';
import '../../shared/widgets/stat_grid.dart';
import '../../state/cash_provider.dart';
import '../../state/sales_provider.dart';
import 'data/cash_repository.dart';
import 'widgets/cash_history_view.dart';
import 'widgets/close_cash_dialog.dart';
import 'widgets/movement_dialog.dart';
import 'widgets/open_cash_dialog.dart';
import 'widgets/session_detail_dialog.dart';
import 'widgets/session_sales_list.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  bool _showHistory = false;

  Future<void> _openCash(CashProvider provider) async {
    final amount = await showOpenCashDialog(context);
    if (amount != null) await provider.openSession(amount);
  }

  Future<void> _registerMovement(CashProvider provider, CashMovementType type) async {
    final result = await showMovementDialog(context, type: type);
    if (result == null) return;
    try {
      await provider.registerMovement(result.type, result.amount, result.note);
    } on InsufficientCashException catch (e) {
      if (!mounted) return;
      FeedbackAlert.show(
        context,
        type: FeedbackType.error,
        title: 'Efectivo insuficiente',
        message: 'En caja hay ${formatCurrency(e.availableCents / 100)}',
      );
    }
  }

  Future<void> _closeCash(CashProvider provider, CashSession session) async {
    final counted = await showCloseCashDialog(context, session);
    if (counted == null || !mounted) return;
    final CashSession? closed;
    try {
      closed = await provider.closeSession(counted);
    } on CashSessionNotOpenException catch (e) {
      if (!mounted) return;
      FeedbackAlert.show(context, type: FeedbackType.warning, title: e.toString());
      return;
    }
    if (closed == null || !mounted) return;
    await showSessionDetailDialog(context, closed, title: 'Caja cerrada');
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
            subtitle: _showHistory
                ? 'Historial de turnos cerrados'
                : session != null
                    ? 'Abierta desde ${dateTimeFormat.format(session.openedAt)}'
                    : 'La caja está cerrada',
            actions: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.point_of_sale), label: Text('Turno actual')),
                  ButtonSegment(value: true, icon: Icon(Icons.history), label: Text('Historial')),
                ],
                selected: {_showHistory},
                onSelectionChanged: (value) => setState(() => _showHistory = value.first),
              ),
              if (!_showHistory) ...[
                if (session == null)
                  FilledButton.icon(
                    onPressed: () => _openCash(provider),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Abrir caja'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: () => _registerMovement(provider, CashMovementType.deposit),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Ingreso'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _registerMovement(provider, CashMovementType.withdrawal),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Retiro'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _closeCash(provider, session),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Cerrar caja'),
                  ),
                ],
              ],
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _showHistory
                ? const CashHistoryView()
                : session == null
                    ? const EmptyState(
                        icon: Icons.point_of_sale_outlined,
                        message: 'Abre la caja para comenzar a registrar\nventas y movimientos de efectivo.',
                      )
                    : _CurrentSession(session: session),
          ),
        ],
      ),
    );
  }
}

class _CurrentSession extends StatelessWidget {
  const _CurrentSession({required this.session});

  final CashSession session;

  @override
  Widget build(BuildContext context) {
    final movements = session.movements.reversed.toList();
    final scheme = Theme.of(context).colorScheme;
    final inflows = session.depositsTotal + session.customerPaymentsTotal;
    final outflows = session.withdrawalsTotal + session.voidsTotal;

    return StreamBuilder<List<Sale>>(
      stream: context.read<SalesProvider>().watchSession(session.id),
      builder: (context, snapshot) {
        final sales = snapshot.data ?? const [];
        final cashSales = totalsByPaymentMethod(sales)[PaymentMethod.cash]!;
        return SingleChildScrollView(
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
                    label: 'Total ventas',
                    value: formatCurrency(activeSalesTotalCents(sales) / 100),
                    subtitle: '${activeSalesCount(sales)} ventas (todos los métodos de pago)',
                    icon: Icons.point_of_sale_outlined,
                    color: Colors.green,
                  ),
                  StatCard(
                    label: 'Ventas cash',
                    value: formatCurrency(cashSales.totalCents / 100),
                    subtitle: '${cashSales.count} ventas',
                    icon: Icons.payments_outlined,
                    color: Colors.teal,
                  ),
                  StatCard(
                    label: 'Entradas / Salidas',
                    value: '+${formatCurrency(inflows)} / -${formatCurrency(outflows)}',
                    icon: Icons.swap_vert,
                    color: Colors.orange,
                  ),
                  StatCard(
                    label: 'Total en caja',
                    value: formatCurrency(session.expectedAmount),
                    subtitle: 'Solo efectivo',
                    icon: Icons.account_balance_wallet_outlined,
                    color: Colors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Ventas por método de pago', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: PaymentMethodSummary(sales: sales),
                ),
              ),
              const SizedBox(height: 24),
              Text('Resumen de ventas', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SessionSalesList(sales: sales),
                ),
              ),
              const SizedBox(height: 24),
              Text('Movimientos de efectivo', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (movements.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: EmptyState(icon: Icons.receipt_long_outlined, message: 'Aún no hay movimientos.'),
                )
              else
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: movements.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final movement = movements[index];
                      final outflow = movement.type.isOutflow;
                      return ListTile(
                        leading: Icon(
                          switch (movement.type) {
                            CashMovementType.sale => Icons.point_of_sale,
                            CashMovementType.deposit => Icons.arrow_downward,
                            CashMovementType.withdrawal => Icons.arrow_upward,
                            CashMovementType.customerPayment => Icons.payments_outlined,
                            CashMovementType.saleVoid => Icons.undo,
                          },
                        ),
                        title: Text(movement.note),
                        subtitle: Text('${movement.type.label} · ${dateTimeFormat.format(movement.time)}'),
                        trailing: Text(
                          '${outflow ? '-' : '+'}${formatCurrency(movement.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: outflow ? scheme.error : Colors.green,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
