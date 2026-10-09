import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format/formatters.dart';
import '../../../models/cart_item.dart';
import '../../../models/customer.dart';
import '../../../state/category_provider.dart';
import '../../../state/customer_provider.dart';
import '../../../state/pos_provider.dart';
import '../../../shared/widgets/empty_state.dart';
import 'quantity_dialog.dart';

class CartPanel extends StatefulWidget {
  const CartPanel({super.key, required this.onCheckout});

  final VoidCallback onCheckout;

  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<CartPanel> {
  static const double _rowHeight = 64;
  static const double _listPadding = 8;

  final _scrollController = ScrollController();
  int _seenAddSerial = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Permite teclear la cantidad exacta de un producto por peso.
  Future<void> _editQuantity(BuildContext context, PosProvider pos, CartItem item) async {
    final entered = await showQuantityDialog(
      context,
      product: item.product,
      available: item.product.stock,
      initial: item.quantity,
      confirmLabel: 'Aceptar',
    );
    if (entered != null) pos.setQuantity(item.product.id, entered);
  }

  /// Cada vez que se agrega un producto, desplaza la lista lo justo para
  /// que su renglón quede visible (el nuevo al final, o el existente cuya
  /// cantidad subió).
  void _revealLastAdded(PosProvider pos) {
    if (pos.addSerial == _seenAddSerial) return;
    _seenAddSerial = pos.addSerial;
    final index = pos.cart.indexWhere(
      (item) => item.product.id == pos.activeProductId,
    );
    if (index < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final top = _listPadding + index * _rowHeight;
      final bottom = top + _rowHeight + _listPadding;
      double? target;
      if (top < position.pixels) {
        target = top - _listPadding;
      } else if (bottom > position.pixels + position.viewportDimension) {
        target = bottom - position.viewportDimension;
      }
      if (target == null) return;
      _scrollController.animateTo(
        target.clamp(0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    _revealLastAdded(pos);
    final customers = context.watch<CustomerProvider>().customers;
    final categories = context.watch<CategoryProvider>();
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
                Text(
                  'Venta actual',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
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
            child: DropdownButtonFormField<String?>(
              key: ValueKey(pos.selectedCustomerId),
              // Si el cliente seleccionado ya no existe, vuelve a "Público general".
              initialValue: customers.any((c) => c.id == pos.selectedCustomerId)
                  ? pos.selectedCustomerId
                  : null,
              decoration: const InputDecoration(labelText: 'Cliente'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Público general')),
                for (final Customer c in customers)
                  DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
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
                    message:
                        'Selecciona productos para agregarlos\na la venta.',
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(_listPadding),
                    itemExtent: _rowHeight,
                    itemCount: pos.cart.length,
                    itemBuilder: (context, index) {
                      final item = pos.cart[index];
                      // Renglones alternados (gris neutro) para no perder la
                      // línea al leer de lado a lado. Solo el producto activo
                      // (el último cuya cantidad se tocó: agregar, + o −) toma
                      // el color de su categoría, fondo + franja izquierda.
                      final isActive = item.product.id == pos.activeProductId;
                      final categoryColor = Color(
                        categories.colorValueFor(item.product.categoryId),
                      );
                      final rowColor = isActive
                          ? Color.alphaBlend(
                              categoryColor.withValues(alpha: 0.28),
                              scheme.surface,
                            )
                          : (index.isEven ? scheme.surface : scheme.surfaceContainerHighest);
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: rowColor,
                          border: Border(
                            left: isActive
                                ? BorderSide(color: categoryColor, width: 6)
                                : BorderSide.none,
                            bottom: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          title: Text(
                            item.product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.product.allowsDecimals
                                ? '${formatCurrency(item.product.price)} / ${item.product.unit}'
                                : '${formatCurrency(item.product.price)} c/u'
                                    '${item.product.isGeneric ? ' · genérico' : ''}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                iconSize: 20,
                                onPressed: () =>
                                    pos.decrementQuantity(item.product.id),
                              ),
                              item.product.allowsDecimals
                                  // Por peso: tocar la cantidad permite teclear
                                  // una exacta (p. ej. 2.5 lb).
                                  ? Tooltip(
                                      message: 'Cambiar cantidad',
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => _editQuantity(context, pos, item),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                          child: Text(
                                            '${formatQuantity(item.quantity)} ${item.product.unit}',
                                            style: Theme.of(context).textTheme.titleSmall,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Text(
                                      formatQuantity(item.quantity),
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                iconSize: 20,
                                onPressed: () =>
                                    pos.incrementQuantity(item.product.id),
                              ),
                              const SizedBox(width: 4),
                              SizedBox(
                                width: 64,
                                child: Text(
                                  formatCurrency(item.subtotal),
                                  textAlign: TextAlign.right,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              // Quita el renglón completo, sin importar la cantidad.
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: scheme.error),
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Quitar del carrito',
                                onPressed: () => pos.removeItem(item.product.id),
                              ),
                            ],
                          ),
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
                    Text(
                      'Total',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      formatCurrency(pos.total),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
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
                    onPressed: pos.isEmpty ? null : widget.onCheckout,
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
