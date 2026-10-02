import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/category_provider.dart';
import '../../state/inventory_provider.dart';
import '../../state/unit_provider.dart';
import '../../shared/widgets/section_header.dart';
import 'widgets/inventory_summary.dart';
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
  Set<String> _selectedIds = {};
  final _scanController = TextEditingController();
  final _scanFocus = FocusNode();

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  /// Un solo campo hace de buscador y de escáner. Mientras se escribe filtra
  /// la tabla. Al pulsar Enter (el lector de códigos lo envía solo al
  /// terminar): un código existente abre la edición de ese producto (para
  /// sumar stock o corregir), un código nuevo abre el alta con el código ya
  /// cargado, y un texto que deja un único resultado abre ese producto.
  Future<void> _onSubmit(
    String raw,
    InventoryProvider inventory,
    CategoryProvider categories,
  ) async {
    final text = raw.trim();
    _scanFocus.requestFocus();
    if (text.isEmpty) return;

    Product? found;
    for (final p in inventory.products) {
      if (p.barcode == text) {
        found = p;
        break;
      }
    }
    final looksLikeBarcode = RegExp(r'^\d{6,}$').hasMatch(text);
    if (found == null && !looksLikeBarcode) {
      final matches = inventory.search(query: text, category: _category);
      if (matches.length == 1) found = matches.first;
    }
    if (found == null && !looksLikeBarcode) return;

    _scanController.clear();
    setState(() => _query = '');
    if (found != null) {
      await _editProduct(inventory, categories, found);
    } else {
      await _addProduct(inventory, categories, barcode: text);
    }
    if (mounted) _scanFocus.requestFocus();
  }

  Future<void> _addProduct(
    InventoryProvider inventory,
    CategoryProvider categories, {
    String? barcode,
  }) async {
    final result = await showProductFormDialog(
      context,
      categories: categories.flatIndented,
      units: context.read<UnitProvider>().units,
      suggestionsFor: inventory.suggestionsFor,
      generateBarcode: inventory.generateInternalBarcode,
      isBarcodeTaken: inventory.isBarcodeTaken,
      initialBarcode: barcode,
    );
    if (result == null) return;
    await inventory.addProduct(
      name: result.name,
      categoryId: result.categoryId,
      unitId: result.unitId,
      priceCents: result.priceCents,
      costCents: result.costCents,
      stock: result.stock,
      minStock: result.minStock,
      barcode: result.barcode,
      extraTags: result.extraTags,
    );
  }

  Future<void> _editProduct(
    InventoryProvider inventory,
    CategoryProvider categories,
    Product product,
  ) async {
    final result = await showProductFormDialog(
      context,
      categories: categories.flatIndented,
      units: context.read<UnitProvider>().units,
      suggestionsFor: inventory.suggestionsFor,
      generateBarcode: inventory.generateInternalBarcode,
      isBarcodeTaken: inventory.isBarcodeTaken,
      existing: product,
    );
    if (result == null) return;
    await inventory.updateProduct(
      id: product.id,
      name: result.name,
      categoryId: result.categoryId,
      unitId: result.unitId,
      priceCents: result.priceCents,
      costCents: result.costCents,
      stock: result.stock,
      minStock: result.minStock,
      barcode: result.barcode,
      extraTags: result.extraTags,
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
    if (confirmed == true) {
      await inventory.deleteProduct(product.id);
      if (mounted) setState(() => _selectedIds.remove(product.id));
    }
  }

  Future<void> _deleteSelected(InventoryProvider inventory, Set<String> ids) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar productos'),
        content: Text('¿Seguro que deseas eliminar ${ids.length} producto(s) seleccionado(s)?'),
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
    if (confirmed != true) return;
    await inventory.deleteProducts(ids);
    if (mounted) setState(() => _selectedIds = {});
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final categoryProvider = context.watch<CategoryProvider>();
    final scheme = Theme.of(context).colorScheme;
    final products = inventory.search(query: _query, category: _category);
    final existingIds = inventory.products.map((p) => p.id).toSet();
    final selectedIds = _selectedIds.intersection(existingIds);
    final inventoryValue = inventory.products.fold<double>(0, (sum, p) => sum + p.cost * p.stock);

    final summary = InventorySummary(
      totalCount: inventory.products.length,
      lowStockCount: inventory.lowStockProducts.length,
      inventoryValue: inventoryValue,
    );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Inventario',
            subtitle: 'Escanea para ingresar productos o administra tus existencias',
            actions: [
              FilledButton.icon(
                onPressed: () => _addProduct(inventory, categoryProvider),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo producto'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(height: 100, child: summary),
          const SizedBox(height: 20),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _scanController,
                            focusNode: _scanFocus,
                            autofocus: true,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.qr_code_scanner),
                              hintText: 'Escanea un código o busca por nombre...',
                            ),
                            onChanged: (value) => setState(() => _query = value),
                            onSubmitted: (value) => _onSubmit(value, inventory, categoryProvider),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _category,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.category_outlined),
                              labelText: 'Categoría',
                            ),
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
                  ),
                  if (selectedIds.isNotEmpty)
                    Container(
                      color: scheme.primaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            '${selectedIds.length} seleccionado(s)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() => _selectedIds = {}),
                            child: const Text('Deseleccionar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.error,
                              foregroundColor: scheme.onError,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            onPressed: () => _deleteSelected(inventory, selectedIds),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Eliminar'),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: ProductTable(
                      products: products,
                      onEdit: (p) => _editProduct(inventory, categoryProvider, p),
                      onDelete: (p) => _deleteProduct(inventory, p),
                      selectedIds: selectedIds,
                      onSelectionChanged: (ids) => setState(() => _selectedIds = ids),
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
