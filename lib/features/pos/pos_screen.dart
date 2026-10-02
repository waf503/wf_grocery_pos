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
import 'widgets/cart_panel.dart';
import 'widgets/checkout_dialog.dart';
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

  void _clearField() {
    _scanController.clear();
    setState(() => _query = '');
  }

  void _addToCart(Product product) {
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
    var inCart = 0;
    for (final item in pos.cart) {
      if (item.product.id == product.id) inCart = item.quantity;
    }
    if (inCart + 1 > product.stock) {
      FeedbackAlert.show(
        context,
        type: FeedbackType.warning,
        title: 'Existencias insuficientes',
        message: 'Solo hay ${product.stock} de ${product.name}',
      );
      return;
    }
    pos.addProduct(product);
    FeedbackAlert.show(
      context,
      type: FeedbackType.success,
      title: product.name,
      message: '${formatCurrency(product.price)}  ·  ${inCart + 1} en el carrito',
    );
  }

  Future<void> _checkout() async {
    final cash = context.read<CashProvider>();
    if (!cash.isOpen) {
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
    final total = pos.total;
    final method = await showPaymentMethodDialog(context, total: total);
    if (method == null || !mounted) return;

    final customers = context.read<CustomerProvider>();
    String? customerName;
    for (final c in customers.customers) {
      if (c.id == pos.selectedCustomerId) {
        customerName = c.name;
        break;
      }
    }

    final sale = Sale(
      id: context.read<SalesProvider>().nextId(),
      date: DateTime.now(),
      items: [
        for (final item in pos.cart)
          SaleItem(
            productName: item.product.name,
            quantity: item.quantity,
            unitPrice: item.product.price,
          ),
      ],
      total: total,
      paymentMethod: method,
      customerName: customerName,
    );

    context.read<SalesProvider>().addSale(sale);
    final inventory = context.read<InventoryProvider>();
    for (final item in pos.cart) {
      inventory.decreaseStock(item.product.id, item.quantity.toDouble());
    }
    cash.registerSale(total, note: 'Venta ${sale.id}');
    if (method == PaymentMethod.credit && pos.selectedCustomerId != null) {
      customers.addToBalance(pos.selectedCustomerId!, total);
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
                    onSelect: (product) {
                      _addToCart(product);
                      _scanFocus.requestFocus();
                    },
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
