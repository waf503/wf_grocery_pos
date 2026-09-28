import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format/formatters.dart';
import '../../state/cash_provider.dart';
import '../../state/inventory_provider.dart';
import '../../state/sales_provider.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/stat_card.dart';
import '../../shared/widgets/stat_grid.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();
    final inventory = context.watch<InventoryProvider>();
    final cash = context.watch<CashProvider>();
    final lowStock = inventory.lowStockProducts;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Inicio', subtitle: 'Resumen general de tu tienda'),
          const SizedBox(height: 20),
          StatGrid(
            children: [
              StatCard(
                label: 'Ventas de hoy',
                value: formatCurrency(sales.todayTotal),
                subtitle: '${sales.todayCount} ventas',
                icon: Icons.point_of_sale_outlined,
                color: Colors.green,
              ),
              StatCard(
                label: 'Productos',
                value: '${inventory.products.length}',
                subtitle: 'en catálogo',
                icon: Icons.inventory_2_outlined,
              ),
              StatCard(
                label: 'Stock bajo',
                value: '${lowStock.length}',
                subtitle: 'productos por reabastecer',
                icon: Icons.warning_amber_rounded,
                color: lowStock.isEmpty ? Colors.green : Colors.orange,
              ),
              StatCard(
                label: 'Caja',
                value: cash.isOpen ? 'Abierta' : 'Cerrada',
                subtitle: cash.isOpen ? formatCurrency(cash.current!.expectedAmount) : 'Sin sesión activa',
                icon: Icons.account_balance_wallet_outlined,
                color: cash.isOpen ? Colors.blue : Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final lowStockCard = Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Productos con stock bajo', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (lowStock.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: EmptyState(icon: Icons.check_circle_outline, message: 'Todo el inventario está en buen nivel.'),
                        )
                      else
                        for (final product in lowStock)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                            title: Text(product.name),
                            trailing: Text('${product.stock} ${product.unit}'),
                          ),
                    ],
                  ),
                ),
              );
              final quickActionsCard = Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Accesos rápidos', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: () => context.go('/pos'),
                            icon: const Icon(Icons.point_of_sale),
                            label: const Text('Nueva venta'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.go('/inventory'),
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('Ver inventario'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.go('/cash'),
                            icon: const Icon(Icons.account_balance_wallet_outlined),
                            label: const Text('Ir a caja'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );

              if (constraints.maxWidth < 700) {
                return Column(
                  children: [
                    lowStockCard,
                    const SizedBox(height: 16),
                    quickActionsCard,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: lowStockCard),
                  const SizedBox(width: 16),
                  Expanded(child: quickActionsCard),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
