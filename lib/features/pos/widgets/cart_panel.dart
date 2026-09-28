import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format/formatters.dart';
import '../../../models/customer.dart';
import '../../../state/customer_provider.dart';
import '../../../state/pos_provider.dart';
import '../../../shared/widgets/empty_state.dart';

class CartPanel extends StatelessWidget {
  const CartPanel({super.key, required this.onCheckout});

  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final customers = context.watch<CustomerProvider>().customers;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Venta actual', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (!pos.isEmpty)
                  TextButton.icon(
                    onPressed: pos.clear,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Vaciar'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              key: ValueKey(pos.selectedCustomerId),
              initialValue: pos.selectedCustomerId ?? customers.first.id,
              decoration: const InputDecoration(labelText: 'Cliente'),
              items: [
                for (final Customer c in customers)
                  DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) => pos.setCustomer(value),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: pos.isEmpty
                ? const EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    message: 'Selecciona productos para agregarlos\na la venta.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: pos.cart.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = pos.cart[index];
                      return ListTile(
                        dense: true,
                        title: Text(item.product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${formatCurrency(item.product.price)} c/u'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              iconSize: 20,
                              onPressed: () => pos.decrementQuantity(item.product.id),
                            ),
                            Text('${item.quantity}', style: Theme.of(context).textTheme.titleSmall),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              iconSize: 20,
                              onPressed: () => pos.incrementQuantity(item.product.id),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 64,
                              child: Text(
                                formatCurrency(item.subtotal),
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      formatCurrency(pos.total),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: pos.isEmpty ? null : onCheckout,
                    icon: const Icon(Icons.point_of_sale),
                    label: const Text('Cobrar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
