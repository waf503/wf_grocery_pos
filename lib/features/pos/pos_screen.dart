import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/mock_data.dart';
import '../../models/sale.dart';
import '../../state/cash_provider.dart';
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
  final _searchController = TextEditingController();
  String _query = '';
  String _category = 'Todas';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      inventory.decreaseStock(item.product.id, item.quantity);
    }
    cash.registerSale(total, note: 'Venta ${sale.id}');
    if (method == PaymentMethod.credit && pos.selectedCustomerId != null) {
      customers.addToBalance(pos.selectedCustomerId!, total);
    }

    pos.clear();
    if (!mounted) return;
    await showReceiptDialog(context, sale);
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
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
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar por nombre o código de barras...',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final cat in ['Todas', ...productCategories])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(cat),
                            selected: _category == cat,
                            onSelected: (_) => setState(() => _category = cat),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ProductGrid(
                    products: products,
                    onSelect: (product) => context.read<PosProvider>().addProduct(product),
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
