import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/formatters.dart';
import '../../models/product.dart';
import '../../shared/widgets/feedback_alert.dart';
import '../../state/category_provider.dart';
import '../../state/inventory_provider.dart';
import '../../state/unit_provider.dart';
import '../../shared/widgets/section_header.dart';
import '../catalog/catalog_item.dart';
import '../catalog/data/product_lookup_service.dart';
import 'widgets/add_stock_dialog.dart';
import 'widgets/inventory_summary.dart';
import 'widgets/lookup_progress_dialog.dart';
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
  bool _lowStockOnly = false;
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
      await _addProduct(inventory, categories, barcode: text, suggested: await _lookupBarcode(text));
    }
    if (mounted) _scanFocus.requestFocus();
  }

  /// Busca información del código escaneado (memoria local e internet) para
  /// precargar el formulario. Nunca bloquea el alta: sin internet, sin
  /// resultado o si el usuario pulsa "Omitir", devuelve `null`.
  Future<CatalogItem?> _lookupBarcode(String code) async {
    if (!ProductLookupService.isLookupable(code)) return null;
    final service = context.read<ProductLookupService>();
    final result = await runLookupWithDialog(context, service.lookup(code));
    if (!mounted || result == null) return null;
    if (result.item == null) {
      FeedbackAlert.show(
        context,
        type: FeedbackType.warning,
        title: result.offline ? 'Sin conexión a internet' : 'Sin información de este código',
        message: 'Registra el producto manualmente',
      );
    }
    return result.item;
  }

  Future<void> _addProduct(
    InventoryProvider inventory,
    CategoryProvider categories, {
    String? barcode,
    CatalogItem? suggested,
  }) async {
    final result = await showProductFormDialog(
      context,
      categories: categories.flatIndented,
      units: context.read<UnitProvider>().units,
      suggestionsFor: inventory.suggestionsFor,
      generateBarcode: inventory.generateInternalBarcode,
      isBarcodeTaken: inventory.isBarcodeTaken,
      initialBarcode: barcode,
      suggested: suggested,
    );
    if (result == null) return;
    final id = await inventory.addProduct(
      name: result.name,
      categoryId: result.categoryId,
      unitId: result.unitId,
      priceCents: result.priceCents,
      costCents: result.costCents,
      stock: result.stock,
      minStock: result.minStock,
      barcode: result.barcode,
      extraTags: result.extraTags,
      image: result.image,
    );
    if (result.combos.isNotEmpty) await inventory.setCombos(id, result.combos);
    if (result.presentations.isNotEmpty || result.rootUnitsPerPack != 1) {
      await inventory.savePresentations(
        id,
        result.presentations,
        baseUnitsPerPack: result.rootUnitsPerPack,
        stockScale: result.stockScale,
      );
    }
  }

  /// Agregar inventario desde una fila: la presentación de esa fila queda
  /// elegida (cajetilla → cajetillas, paquete → paquetes, unidad → unidades).
  Future<void> _addStock(InventoryProvider inventory, Product product) async {
    final base = product.isPresentation ? inventory.byId(product.baseProductId!) : product;
    if (base == null) return;
    final entry = await showAddStockDialog(
      context,
      product: product,
      base: base,
      presentations: inventory.presentationsOf(base.id),
    );
    if (entry == null || !mounted) return;

    final units = await inventory.addStock(entry.target, entry.quantity, costCents: entry.costCents);
    if (!mounted) return;
    FeedbackAlert.show(
      context,
      type: FeedbackType.success,
      title: 'Inventario agregado',
      message: '${base.name}: +${formatQuantity(units)} ${base.unit} '
          '(ahora ${formatQuantity(base.stock + units)})'
          '${entry.costCents != null ? ' · costo actualizado' : ''}',
    );
  }

  Future<void> _editProduct(
    InventoryProvider inventory,
    CategoryProvider categories,
    Product product, {
    bool startWithNewPresentation = false,
  }) async {
    // Una presentación se edita desde su producto base (ahí están sus
    // existencias y sus hermanas), incluso si se llegó escaneando su código.
    if (product.isPresentation) product = inventory.byId(product.baseProductId!) ?? product;
    final existingImage = await inventory.imageFor(product);
    if (!mounted) return;
    final result = await showProductFormDialog(
      context,
      categories: categories.flatIndented,
      units: context.read<UnitProvider>().units,
      suggestionsFor: inventory.suggestionsFor,
      generateBarcode: inventory.generateInternalBarcode,
      isBarcodeTaken: inventory.isBarcodeTaken,
      existing: product,
      existingImage: existingImage,
      existingPresentations: inventory.presentationsOf(product.id),
      startWithNewPresentation: startWithNewPresentation,
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
      image: result.imageChanged ? result.image : null,
      removeImage: result.imageChanged && result.image == null,
    );
    // Siempre se reemplazan: así también se borran las que el usuario quitó.
    await inventory.setCombos(product.id, result.combos);
    await inventory.savePresentations(
      product.id,
      result.presentations,
      baseUnitsPerPack: result.rootUnitsPerPack,
      stockScale: result.stockScale,
    );
  }

  Future<void> _deleteProduct(InventoryProvider inventory, Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
          inventory.presentationsOf(product.id).isEmpty
              ? '¿Seguro que deseas eliminar "${product.name}"?'
              : '¿Seguro que deseas eliminar "${product.name}"? '
                  'También se eliminarán sus ${inventory.presentationsOf(product.id).length} presentaciones.',
        ),
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
    final products = inventory
        .search(query: _query, category: _category)
        .where((p) => !_lowStockOnly || p.isLowStock)
        .toList();
    final existingIds = inventory.products.map((p) => p.id).toSet();
    final selectedIds = _selectedIds.intersection(existingIds);
    // Las presentaciones comparten las existencias de su producto base: solo
    // se cuenta el base para no sumar dos veces lo mismo.
    // Valor del pool completo (incluye las unidades sueltas que no forman un empaque).
    final inventoryValue = inventory.baseProducts.fold<double>(0, (sum, p) => sum + p.poolUnits * p.cost / p.poolFactor);

    final summary = InventorySummary(
      totalCount: inventory.baseProducts.length,
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
          SizedBox(height: 112, child: summary),
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
                        const SizedBox(width: 12),
                        FilterChip(
                          avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                          label: Text('Stock bajo (${inventory.lowStockProducts.length})'),
                          selected: _lowStockOnly,
                          onSelected: (value) => setState(() => _lowStockOnly = value),
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
                      // Editar una presentación abre el producto base (ahí se
                      // cambian sus presentaciones y las existencias).
                      onEdit: (p) => _editProduct(
                        inventory,
                        categoryProvider,
                        p.isPresentation ? (inventory.byId(p.baseProductId!) ?? p) : p,
                      ),
                      onDelete: (p) => _deleteProduct(inventory, p),
                      onAddStock: (p) => _addStock(inventory, p),
                      onAddPresentation: (p) => _editProduct(
                        inventory,
                        categoryProvider,
                        p,
                        startWithNewPresentation: true,
                      ),
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
