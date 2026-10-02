import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../models/product.dart';
import '../../../shared/widgets/empty_state.dart';

const double _checkWidth = 56;
const double _priceWidth = 120;
const double _costWidth = 120;
const double _stockWidth = 150;
const double _actionsWidth = 110;

/// Tabla plana de Inventario: una fila por producto, con selección múltiple.
class ProductTable extends StatelessWidget {
  const ProductTable({
    super.key,
    required this.products,
    required this.onEdit,
    required this.onDelete,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  final List<Product> products;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onDelete;
  final Set<String> selectedIds;
  final void Function(Set<String> ids) onSelectionChanged;

  /// `true` si todos, `null` si algunos y `false` si ninguno está seleccionado.
  bool? get _selectionState {
    final selected = products.where((p) => selectedIds.contains(p.id)).length;
    if (selected == 0) return false;
    return selected == products.length ? true : null;
  }

  void _setSelected(Iterable<Product> items, bool selected) {
    final next = {...selectedIds};
    for (final p in items) {
      selected ? next.add(p.id) : next.remove(p.id);
    }
    onSelectionChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const EmptyState(icon: Icons.inventory_2_outlined, message: 'No hay productos que coincidan.');
    }
    final sorted = [...products]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(constraints.maxWidth, 860),
            child: Column(
              children: [
                _HeaderRow(
                  selection: _selectionState,
                  onToggleAll: () => _setSelected(products, _selectionState != true),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = sorted[index];
                      return _ProductRow(
                        product: product,
                        selected: selectedIds.contains(product.id),
                        onSelectedChanged: (value) => _setSelected([product], value),
                        onEdit: () => onEdit(product),
                        onDelete: () => onDelete(product),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Estructura de columnas compartida por el encabezado y las filas.
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.check,
    required this.product,
    required this.category,
    required this.price,
    required this.cost,
    required this.stock,
    required this.actions,
    this.color,
    this.onTap,
    this.height = 60,
  });

  final Widget check;
  final Widget product;
  final Widget category;
  final Widget price;
  final Widget cost;
  final Widget stock;
  final Widget actions;
  final Color? color;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              SizedBox(width: _checkWidth, child: Center(child: check)),
              Expanded(flex: 4, child: Align(alignment: Alignment.centerLeft, child: product)),
              Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: category)),
              SizedBox(width: _priceWidth, child: Align(alignment: Alignment.centerRight, child: price)),
              SizedBox(width: _costWidth, child: Align(alignment: Alignment.centerRight, child: cost)),
              SizedBox(width: _stockWidth, child: Align(alignment: Alignment.center, child: stock)),
              SizedBox(width: _actionsWidth, child: Align(alignment: Alignment.centerRight, child: actions)),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.selection, required this.onToggleAll});

  final bool? selection;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: scheme.onSurfaceVariant,
        );
    return _RowShell(
      height: 48,
      color: scheme.surfaceContainerHighest,
      check: Checkbox(tristate: true, value: selection, onChanged: (_) => onToggleAll()),
      product: Text('Producto', style: style),
      category: Text('Categoría', style: style),
      price: Text('Precio', style: style),
      cost: Text('Costo', style: style),
      stock: Text('Stock', style: style),
      actions: const SizedBox.shrink(),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.selected,
    required this.onSelectedChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final Product product;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final barcode = product.barcode;
    return _RowShell(
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
      onTap: () => onSelectedChanged(!selected),
      check: Checkbox(value: selected, onChanged: (v) => onSelectedChanged(v ?? false)),
      product: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product.name,
            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          if (barcode != null && barcode.isNotEmpty)
            Text(
              barcode,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      category: Text(product.category, overflow: TextOverflow.ellipsis),
      price: Text(formatCurrency(product.price), style: const TextStyle(fontWeight: FontWeight.w600)),
      cost: Text(formatCurrency(product.cost), style: TextStyle(color: scheme.onSurfaceVariant)),
      stock: _StockPill(product: product),
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: onEdit),
          IconButton(
            icon: Icon(Icons.delete_outline, color: scheme.error),
            tooltip: 'Eliminar',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _StockPill extends StatelessWidget {
  const _StockPill({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final low = product.isLowStock;
    final background = low ? scheme.errorContainer : scheme.surfaceContainerHigh;
    final foreground = low ? scheme.onErrorContainer : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (low) ...[
            Icon(Icons.warning_amber_rounded, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            '${formatQuantity(product.stock)} ${product.unit}',
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
