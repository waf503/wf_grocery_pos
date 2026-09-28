import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/mock_data.dart';
import '../../models/product.dart';
import '../../state/inventory_provider.dart';
import '../../shared/widgets/section_header.dart';
import 'widgets/product_form_dialog.dart';
import 'widgets/product_table.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _query = '';
  String _category = 'Todas';

  Future<void> _addProduct(InventoryProvider inventory) async {
    final product = await showProductFormDialog(context, nextId: inventory.nextId);
    if (product != null) inventory.addProduct(product);
  }

  Future<void> _editProduct(InventoryProvider inventory, Product product) async {
    final updated = await showProductFormDialog(context, existing: product, nextId: inventory.nextId);
    if (updated != null) inventory.updateProduct(updated);
  }

  Future<void> _deleteProduct(InventoryProvider inventory, Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Seguro que deseas eliminar "${product.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) inventory.deleteProduct(product.id);
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final products = inventory.search(query: _query, category: _category);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Inventario',
            subtitle: '${inventory.products.length} productos registrados',
            actions: [
              FilledButton.icon(
                onPressed: () => _addProduct(inventory),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo producto'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por nombre o código de barras...',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    for (final c in ['Todas', ...productCategories]) DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (value) => setState(() => _category = value!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ProductTable(
              products: products,
              onEdit: (p) => _editProduct(inventory, p),
              onDelete: (p) => _deleteProduct(inventory, p),
            ),
          ),
        ],
      ),
    );
  }
}
