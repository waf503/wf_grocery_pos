import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/category_provider.dart';
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

  Future<void> _addProduct(InventoryProvider inventory, CategoryProvider categories) async {
    final result = await showProductFormDialog(
      context,
      families: inventory.families,
      categories: categories.flatIndented,
    );
    if (result == null) return;
    await inventory.addProduct(
      familyName: result.familyName,
      categoryId: result.categoryId,
      presentation: result.presentation,
      unit: result.unit,
      price: result.price,
      cost: result.cost,
      stock: result.stock,
      minStock: result.minStock,
      barcode: result.barcode,
    );
  }

  Future<void> _editProduct(
    InventoryProvider inventory,
    CategoryProvider categories,
    Product product,
  ) async {
    final result = await showProductFormDialog(
      context,
      families: inventory.families,
      categories: categories.flatIndented,
      existing: product,
    );
    if (result == null) return;
    await inventory.updateProduct(
      product.copyWith(
        presentation: result.presentation,
        unit: result.unit,
        price: result.price,
        cost: result.cost,
        stock: result.stock,
        minStock: result.minStock,
        barcode: result.barcode,
      ),
    );
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
    if (confirmed == true) await inventory.deleteProduct(product.id);
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final categoryProvider = context.watch<CategoryProvider>();
    final products = inventory.search(query: _query, category: _category);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Inventario',
            subtitle: '${inventory.products.length} presentaciones registradas',
            actions: [
              FilledButton.icon(
                onPressed: () => _addProduct(inventory, categoryProvider),
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
                    const DropdownMenuItem(value: 'Todas', child: Text('Todas')),
                    for (final c in categoryProvider.flatIndented)
                      DropdownMenuItem(
                        value: c.name,
                        child: Text('${'—  ' * categoryProvider.depthOf(c)}${c.name}'),
                      ),
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
              onEdit: (p) => _editProduct(inventory, categoryProvider, p),
              onDelete: (p) => _deleteProduct(inventory, p),
            ),
          ),
        ],
      ),
    );
  }
}
