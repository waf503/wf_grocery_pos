import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/formatters.dart';
import '../../core/money.dart';
import '../../models/cash_session.dart';
import '../../models/sale.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/feedback_alert.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/stat_card.dart';
import '../../shared/widgets/stat_grid.dart';
import '../../state/auth_provider.dart';
import '../../state/cash_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/sales_provider.dart';
import '../auth/widgets/admin_pin_dialog.dart';
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

  /// Sin sistema de usuarios (pruebas) se actúa como administrador.
  bool get _isAdmin => context.read<AuthProvider?>()?.isAdmin ?? true;

  String? get _userName => context.read<AuthProvider?>()?.currentUser?.name;

  Future<void> _openCash(CashProvider provider) async {
    final amount = await showOpenCashDialog(context);
    if (amount != null) await provider.openSession(amount, openedBy: _userName);
  }

  Future<void> _registerMovement(
    CashProvider provider,
    CashMovementType type,
  ) async {
    final result = await showMovementDialog(context, type: type);
    if (result == null || !mounted) return;

    // Estándar de tiendas: el cajero hace retiros e ingresos pequeños por su
    // cuenta; arriba del tope necesita la autorización (PIN) de un administrador.
    var note = result.note;
    final limitCents =
        context.read<SettingsProvider?>()?.cashMovementLimitCents ??
        SettingsProvider.defaultCashMovementLimitCents;
    if (!_isAdmin && toCents(result.amount) > limitCents) {
      final admin = await showAdminPinDialog(
        context,
        title:
            'Autorizar ${type == CashMovementType.deposit ? 'ingreso' : 'retiro'}',
        message:
            'Los ${type == CashMovementType.deposit ? 'ingresos' : 'retiros'} de más de '
            '${formatCurrency(limitCents / 100)} necesitan el PIN de un administrador.',
      );
      if (admin == null || !mounted) return;
      note = '$note (autorizó ${admin.name})';
    }

    try {
      await provider.registerMovement(
        result.type,
        result.amount,
        note,
        createdBy: _userName,
      );
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
    final isAdmin = _isAdmin;
    final counted = await showCloseCashDialog(
      context,
      session,
      blind: !isAdmin,
    );
    if (counted == null || !mounted) return;
    final CashSession? closed;
    try {
      closed = await provider.closeSession(counted, closedBy: _userName);
    } on CashSessionNotOpenException catch (e) {
      if (!mounted) return;
      FeedbackAlert.show(
        context,
        type: FeedbackType.warning,
        title: e.toString(),
      );
      return;
    }
    if (closed == null || !mounted) return;
    if (isAdmin) {
      await showSessionDetailDialog(context, closed, title: 'Caja cerrada');
    } else {
      // Cierre a ciegas: el cajero no ve el cuadre; lo revisa el administrador.
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Caja cerrada'),
          content: const Text(
            'Se registró el conteo. El administrador revisará el cuadre del turno.',
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
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CashProvider>();
    final session = provider.current;
    final isAdmin = context.watch<AuthProvider?>()?.isAdmin ?? true;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Caja',
            subtitle: _showHistory && isAdmin
                ? 'Historial de turnos cerrados'
                : session != null
                ? 'Abierta desde ${dateTimeFormat.format(session.openedAt)}'
                : 'La caja está cerrada',
            actions: [
              // El historial de turnos (con sus sobrantes y faltantes) es del administrador.
              if (isAdmin)
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.point_of_sale),
                      label: Text('Turno actual'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.history),
                      label: Text('Historial'),
                    ),
                  ],
                  selected: {_showHistory},
                  onSelectionChanged: (value) =>
                      setState(() => _showHistory = value.first),
                ),
              if (!_showHistory || !isAdmin) ...[
                if (session == null)
                  FilledButton.icon(
                    onPressed: () => _openCash(provider),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Abrir caja'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: () =>
                        _registerMovement(provider, CashMovementType.deposit),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Ingreso'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _registerMovement(
                      provider,
                      CashMovementType.withdrawal,
                    ),
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
            child: _showHistory && isAdmin
                ? const CashHistoryView()
                : session == null
                ? const EmptyState(
                    icon: Icons.point_of_sale_outlined,
                    message: 'Abre la caja para comenzar a registrar\nventas y movimientos de efectivo.',
                  )
                : _CurrentSession(session: session, showTotals: isAdmin),
          ),
        ],
      ),
    );
  }
}

class _CurrentSession extends StatelessWidget {
  const _CurrentSession({required this.session, required this.showTotals});

  final CashSession session;

  /// El cajero no ve el efectivo esperado ni las entradas/salidas (cierre a ciegas).
  final bool showTotals;

  @override
  Widget build(BuildContext context) {
    // El cajero solo ve los movimientos manuales: la suma de ventas y vueltos
    // le daría el efectivo esperado.
    final movements = session.movements
        .where(
          (m) =>
              showTotals ||
              m.type == CashMovementType.deposit ||
              m.type == CashMovementType.withdrawal,
        )
        .toList()
        .reversed
        .toList();
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
                    subtitle:
                        '${activeSalesCount(sales)} ventas (todos los métodos de pago)',
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
                  if (showTotals)
                    StatCard(
                      label: 'Entradas / Salidas',
                      value:
                          '+${formatCurrency(inflows)} / -${formatCurrency(outflows)}',
                      icon: Icons.swap_vert,
                      color: Colors.orange,
                    ),
                  if (showTotals)
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
              Text(
                'Ventas por método de pago',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: PaymentMethodSummary(sales: sales),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Resumen de ventas',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: SessionSalesList(sales: sales),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Movimientos de efectivo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (movements.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: 'Aún no hay movimientos.',
                  ),
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
                        leading: Icon(switch (movement.type) {
                          CashMovementType.sale => Icons.point_of_sale,
                          CashMovementType.deposit => Icons.arrow_downward,
                          CashMovementType.withdrawal => Icons.arrow_upward,
                          CashMovementType.customerPayment =>
                            Icons.payments_outlined,
                          CashMovementType.saleVoid => Icons.undo,
                          CashMovementType.change => Icons.currency_exchange,
                        }),
                        title: Text(movement.note),
                        subtitle: Text(
                          '${movement.type.label} · ${dateTimeFormat.format(movement.time)}'
                          '${movement.createdBy != null ? ' · ${movement.createdBy}' : ''}',
                        ),
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
