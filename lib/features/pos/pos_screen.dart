import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/formatters.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../shared/widgets/feedback_alert.dart';
import '../../state/cash_provider.dart';
import '../../state/category_provider.dart';
import '../../state/customer_provider.dart';
import '../../state/inventory_provider.dart';
import '../../state/pos_provider.dart';
import '../../state/sales_provider.dart';
import '../sales/data/sale_repository.dart';
import 'widgets/cart_panel.dart';
import 'widgets/checkout_dialog.dart';
import 'widgets/generic_item_dialog.dart';
import 'widgets/quantity_dialog.dart';
import 'widgets/sale_review_dialog.dart';
import 'widgets/product_grid.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _scanController = TextEditingController();
  final _scanFocus = FocusNode();
  String _query = '';
  String _category = 'Todas';

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  /// Un solo campo hace de buscador y de escáner. Mientras se escribe,
  /// filtra la grilla. Al pulsar Enter (el lector de códigos lo envía solo
  /// al terminar de teclear) se agrega al carrito si el texto identifica un
  /// producto de forma única: un código de barras exacto, o una búsqueda que
  /// deja un solo resultado.
  void _onSubmit(String raw) {
    final text = raw.trim();
    _scanFocus.requestFocus();
    if (text.isEmpty) return;

    final inventory = context.read<InventoryProvider>();
    Product? product;
    for (final p in inventory.products) {
      if (p.barcode == text) {
        product = p;
        break;
      }
    }
    product ??= () {
      final matches = inventory.search(query: text, category: _category);
      return matches.length == 1 ? matches.first : null;
    }();

    if (product == null) {
      // Un código escaneado que no existe se descarta para que el siguiente
      // escaneo no se pegue a este; un texto de búsqueda se conserva.
      if (RegExp(r'^\d{6,}$').hasMatch(text)) {
        _clearField();
        FeedbackAlert.show(
          context,
          type: FeedbackType.error,
          title: 'Código no registrado',
          message: text,
        );
      }
      return;
    }
    _clearField();
    _addToCart(product);
  }

  /// Venta de algo que no está en el inventario: el cajero escribe
  /// descripción, precio y cantidad, y entra al carrito como un renglón más.
  Future<void> _addGeneric() async {
    final item = await showGenericItemDialog(context);
    if (!mounted) return;
    if (item != null) {
      context.read<PosProvider>().addGeneric(
            name: item.name,
            priceCents: item.priceCents,
            quantity: item.quantity,
          );
      FeedbackAlert.show(
        context,
        type: FeedbackType.success,
        title: item.name,
        message: '${formatCurrency(item.priceCents / 100)} · venta genérica',
      );
    }
    _scanFocus.requestFocus();
  }

  void _clearField() {
    _scanController.clear();
    setState(() => _query = '');
  }

  Future<void> _addToCart(Product product) async {
    final pos = context.read<PosProvider>();
    if (product.stock <= 0) {
      FeedbackAlert.show(
        context,
        type: FeedbackType.error,
        title: 'Sin existencias',
        message: product.name,
      );
      return;
    }
    var inCart = 0.0;
    for (final item in pos.cart) {
      if (item.product.id == product.id) inCart = item.quantity;
    }

    // Las existencias son del producto BASE y se comparten entre sus
    // presentaciones (unidad, cajetilla, paquete): se descuenta lo que ya hay
    // en el carrito de cualquiera de ellas y se ve cuántas de ESTA caben aún.
    final inventory = context.read<InventoryProvider>();
    final remainingUnits = inventory.poolStock(product) - pos.poolUnitsInCart(product.poolId);
    final canAddMore = product.poolFactor == 1
        ? remainingUnits
        : (remainingUnits / product.poolFactor).floorToDouble();

    // Los productos por peso (libras, kilos...) piden la cantidad; los de
    // pieza suman 1 con cada clic o escaneo.
    var quantity = 1.0;
    if (product.allowsDecimals) {
      final entered = await showQuantityDialog(
        context,
        product: product,
        available: inCart + canAddMore,
      );
      if (!mounted) return;
      if (entered == null) {
        _scanFocus.requestFocus();
        return;
      }
      quantity = entered;
    }

    if (quantity > canAddMore + 1e-9) {
      FeedbackAlert.show(
        context,
        type: FeedbackType.warning,
        title: 'Existencias insuficientes',
        message: canAddMore <= 0
            ? 'Ya no quedan ${product.name} (todo está en el carrito)'
            : 'Solo se pueden agregar ${formatQuantity(canAddMore)} más de ${product.name}',
      );
      _scanFocus.requestFocus();
      return;
    }
    pos.addProduct(product, quantity: quantity);
    FeedbackAlert.show(
      context,
      type: FeedbackType.success,
      title: product.name,
      message: '${formatCurrency(product.price)}  ·  ${formatQuantity(inCart + quantity)}'
          '${product.allowsDecimals ? ' ${product.unit}' : ''} en el carrito',
    );
    _scanFocus.requestFocus();
  }

  Future<void> _checkout() async {
    final cash = context.read<CashProvider>();
    final session = cash.current;
    if (session == null) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Caja cerrada'),
          content: const Text('Debes abrir la caja antes de registrar una venta.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    final pos = context.read<PosProvider>();
    final customers = context.read<CustomerProvider>();
    final customer = customers.byId(pos.selectedCustomerId);
    // Cobro → REVISIÓN → registro. Nada se guarda hasta que el vendedor
    // confirma el ticket; desde la revisión puede volver a corregir el pago
    // (se reabre con lo que ya había escrito) o cancelar (el carrito queda).
    PaymentChoice? chosen;
    while (true) {
      chosen = await showPaymentMethodDialog(
        context,
        total: pos.total,
        customerName: customer?.name,
        initial: chosen,
      );
      if (chosen == null || !mounted) return;

      // El fiado exige un cliente registrado (no "Público general").
      if (chosen.method == PaymentMethod.credit && customer == null) {
        FeedbackAlert.show(
          context,
          type: FeedbackType.warning,
          title: 'Selecciona un cliente',
          message: 'Para vender a crédito elige un cliente en la venta',
        );
        return;
      }

      final decision = await showSaleReviewDialog(
        context,
        items: pos.cart,
        totalCents: pos.totalCents,
        payment: chosen,
        customerName: customer?.name,
      );
      if (!mounted) return;
      if (decision == SaleReviewDecision.confirm) break;
      if (decision == SaleReviewDecision.cancel) {
        _scanFocus.requestFocus();
        return;
      }
      // back: se vuelve a abrir el cobro con lo que había escrito.
    }
    final payment = chosen;
    final method = payment.method;

    final lines = [
      for (final item in pos.cart)
        SaleLine(
          productId: item.product.isGeneric ? null : item.product.id,
          productName: item.product.name,
          quantity: item.quantity,
          unitPriceCents: item.product.priceCents,
          unitCostCents: item.product.costCents,
          // Con los combos aplicados (ej. 2 por $0.25), igual que el carrito.
          fixedSubtotalCents: item.subtotalCents,
        ),
    ];

    // La venta, el descuento de existencias y el movimiento de caja se
    // guardan juntos en una transacción: o pasa todo o no pasa nada.
    final Sale sale;
    try {
      sale = await context.read<SalesProvider>().registerSale(
            sessionId: session.id,
            lines: lines,
            paymentMethod: method,
            customerId: customer?.id,
            customerName: customer?.name,
            tenderedCents: payment.tenderedCents,
          );
    } on InsufficientTenderException catch (e) {
      if (!mounted) return;
      FeedbackAlert.show(
        context,
        type: FeedbackType.error,
        title: 'El efectivo no alcanza',
        message: 'Faltan ${formatCurrency(e.missingCents / 100)}',
      );
      return;
    } on InsufficientStockException catch (e) {
      if (!mounted) return;
      FeedbackAlert.show(
        context,
        type: FeedbackType.error,
        title: 'Existencias insuficientes',
        message: 'Solo hay ${formatQuantity(e.available)} de ${e.productName}',
      );
      return;
    } on ProductNotFoundException catch (e) {
      if (!mounted) return;
      FeedbackAlert.show(
        context,
        type: FeedbackType.error,
        title: 'Producto no disponible',
        message: e.productName,
      );
      return;
    } on CreditRequiresCustomerException catch (e) {
      if (!mounted) return;
      FeedbackAlert.show(context, type: FeedbackType.warning, title: e.toString());
      return;
    } on CashSessionClosedException {
      if (!mounted) return;
      FeedbackAlert.show(context, type: FeedbackType.error, title: 'La caja está cerrada');
      return;
    }

    pos.clear();
    if (!mounted) return;
    await showReceiptDialog(context, sale);
    if (mounted) _scanFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final categoryProvider = context.watch<CategoryProvider>();
    final products = inventory.search(query: _query, category: _category);

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _scanController,
                          focusNode: _scanFocus,
                          autofocus: true,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.qr_code_scanner),
                            hintText: 'Escanea un código o busca por nombre...',
                          ),
                          onChanged: (value) => setState(() => _query = value),
                          onSubmitted: _onSubmit,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: _addGeneric,
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Venta genérica'),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: const Text('Todas'),
                          selected: _category == 'Todas',
                          onSelected: (_) => setState(() => _category = 'Todas'),
                        ),
                      ),
                      for (final cat in categoryProvider.flatIndented)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            avatar: CircleAvatar(
                              radius: 7,
                              backgroundColor: Color(categoryProvider.colorValueFor(cat.id)),
                            ),
                            label: Text(cat.name),
                            selected: _category == cat.name,
                            onSelected: (_) => setState(() => _category = cat.name),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ProductGrid(
                    products: products,
                    categoryColorFor: categoryProvider.colorValueFor,
                    onSelect: _addToCart,
                  ),
                ),
              ],
            ),
          ),
          CartPanel(onCheckout: _checkout),
        ],
      ),
    );
  }
}
