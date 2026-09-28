import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../models/product.dart';
import '../../../shared/widgets/empty_state.dart';

class ProductTable extends StatelessWidget {
  const ProductTable({
    super.key,
    required this.products,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Product> products;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onDelete;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const EmptyState(icon: Icons.inventory_2_outlined, message: 'No hay productos que coincidan.');
    }
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 640),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Producto')),
              DataColumn(label: Text('Categoría')),
              DataColumn(label: Text('Precio'), numeric: true),
              DataColumn(label: Text('Costo'), numeric: true),
              DataColumn(label: Text('Stock'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final product in products)
                DataRow(
                  cells: [
                    DataCell(Text(product.name)),
                    DataCell(Text(product.category)),
                    DataCell(Text(formatCurrency(product.price))),
                    DataCell(Text(formatCurrency(product.cost))),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${product.stock} ${product.unit}'),
                          if (product.isLowStock) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                          ],
                        ],
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Editar',
                            onPressed: () => onEdit(product),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Eliminar',
                            onPressed: () => onDelete(product),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
