import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format/formatters.dart';
import '../../../models/cash_session.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../state/cash_provider.dart';
import 'session_detail_dialog.dart';

/// Historial de turnos cerrados (los 200 más recientes): total en caja, contado y
/// diferencia de cada uno. Al tocar un turno se abre su detalle.
class CashHistoryView extends StatelessWidget {
  const CashHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<CashSession>>(
      stream: context.read<CashProvider>().watchClosed(),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const [];
        if (sessions.isEmpty) {
          return const EmptyState(icon: Icons.history, message: 'Aún no hay turnos cerrados.');
        }
        return Card(
          child: ListView.separated(
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final s = sessions[index];
              final difference = s.differenceCents ?? 0;
              final balanced = difference == 0;
              return ListTile(
                onTap: () => showSessionDetailDialog(context, s),
                leading: Icon(
                  balanced ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                  color: balanced ? Colors.green.shade700 : (difference > 0 ? Colors.orange.shade800 : scheme.error),
                ),
                title: Text('${dateTimeFormat.format(s.openedAt)}  →  ${dateTimeFormat.format(s.closedAt!)}'),
                subtitle: Text(
                  'Total en caja ${formatCurrency(s.expectedAmount)} · Contado ${formatCurrency(s.closingCountedAmount ?? 0)}',
                ),
                trailing: Text(
                  balanced
                      ? 'Cuadrada'
                      : '${difference > 0 ? 'Sobrante' : 'Faltante'} ${formatCurrency(s.difference!.abs())}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: balanced ? Colors.green.shade700 : (difference > 0 ? Colors.orange.shade800 : scheme.error),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
