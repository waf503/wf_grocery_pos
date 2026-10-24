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
  static const double _listPadding = 8;

  final _scrollController = ScrollController();
  int _seenAddSerial = 0;

  /// Una llave por renglón: como el nombre completo del producto puede ocupar
  /// una, dos o tres líneas, los renglones NO miden lo mismo y para mostrar el
  /// último agregado se le pide al propio renglón que se haga visible.
  final Map<String, GlobalKey> _rowKeys = {};

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
  /// cantidad subió). Si ya se ve completo, no se mueve nada.
  void _revealLastAdded(PosProvider pos) {
    if (pos.addSerial == _seenAddSerial) return;
    _seenAddSerial = pos.addSerial;
    final activeId = pos.activeProductId;
    if (activeId == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _rowKeys[activeId]?.currentContext;
      if (!mounted || rowContext == null || !_scrollController.hasClients) return;
      const duration = Duration(milliseconds: 220);
      // Si está más abajo de lo que se ve, se alinea al final; si quedó más
      // arriba, al comienzo. Si ya está a la vista, ninguna de las dos mueve nada.
      Scrollable.ensureVisible(
        rowContext,
        duration: duration,
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        rowContext,
        duration: duration,
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    _rowKeys.removeWhere((id, _) => !pos.cart.any((item) => item.product.id == id));
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
                      return _CartRow(
                        key: _rowKeys.putIfAbsent(item.product.id, GlobalKey.new),
                        item: item,
                        color: rowColor,
                        stripeColor: isActive ? categoryColor : null,
                        onDecrement: () => pos.decrementQuantity(item.product.id),
                        onIncrement: () => pos.incrementQuantity(item.product.id),
                        onRemove: () => pos.removeItem(item.product.id),
                        onEditQuantity: () => _editQuantity(context, pos, item),
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

/// Un renglón del carrito. Se acomoda en tres filas para que quepa el NOMBRE
/// COMPLETO del producto (sin cortarlo con "..."):
///
///   Nombre del producto, en las líneas que haga falta
///   $3.80 c/u · combo: ahorra $0.10
///   [−] 2 [+]                          $7.60  [papelera]
class _CartRow extends StatelessWidget {
  const _CartRow({
    super.key,
    required this.item,
    required this.color,
    required this.stripeColor,
    required this.onDecrement,
    required this.onIncrement,
    required this.onRemove,
    required this.onEditQuantity,
  });

  final CartItem item;
  final Color color;

  /// Franja izquierda del producto activo (color de su categoría).
  final Color? stripeColor;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onRemove;
  final VoidCallback onEditQuantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final product = item.product;

    final priceLine = product.allowsDecimals
        ? '${formatCurrency(product.price)} / ${product.unit}'
        : '${formatCurrency(product.price)} c/u'
            '${product.isGeneric ? ' · genérico' : ''}'
            '${item.savingsCents > 0 ? ' · combo: ahorra ${formatCurrency(item.savingsCents / 100)}' : ''}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          left: stripeColor != null ? BorderSide(color: stripeColor!, width: 6) : BorderSide.none,
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nombre completo: se parte en las líneas necesarias.
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                product.name,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                priceLine,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  iconSize: 22,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Quitar una',
                  onPressed: onDecrement,
                ),
                product.allowsDecimals
                    // Por peso: tocar la cantidad permite teclear una exacta
                    // (p. ej. 2.5 lb).
                    ? Tooltip(
                        message: 'Cambiar cantidad',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: onEditQuantity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Text(
                              '${formatQuantity(item.quantity)} ${product.unit}',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ),
                      )
                    : Text(formatQuantity(item.quantity), style: theme.textTheme.titleSmall),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  iconSize: 22,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Agregar una',
                  onPressed: onIncrement,
                ),
                const Spacer(),
                Text(
                  formatCurrency(item.subtotal),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                // Quita el renglón completo, sin importar la cantidad.
                IconButton(
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  iconSize: 22,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Quitar del carrito',
                  onPressed: onRemove,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
