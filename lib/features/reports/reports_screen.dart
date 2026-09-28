import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/formatters.dart';
import '../../models/sale.dart';
import '../../state/sales_provider.dart';
import '../../shared/widgets/section_header.dart';
import 'widgets/sales_bar_chart.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();
    final weekData = sales.lastDaysTotals(7);
    final topProducts = sales.topProducts();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Reportes', subtitle: 'Desempeño de ventas de los últimos 7 días'),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ventas por día', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  SizedBox(height: 260, child: SalesBarChart(data: weekData)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Productos más vendidos', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (topProducts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Aún no hay ventas registradas.'),
                    )
                  else
                    for (final entry in topProducts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(entry.key)),
                            Text('${entry.value} unidades', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ventas recientes', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (sales.sales.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Aún no hay ventas registradas.'),
                    )
                  else
                    for (final sale in sales.sales.take(10))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text('${sale.itemCount} artículos · ${sale.paymentMethod.label}'),
                        subtitle: Text(dateTimeFormat.format(sale.date)),
                        trailing: Text(
                          formatCurrency(sale.total),
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
