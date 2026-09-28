import 'package:flutter/material.dart';

import '../../../models/product.dart';
import '../../../shared/widgets/empty_state.dart';
import 'product_tile.dart';

class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.products, required this.onSelect});

  final List<Product> products;
  final ValueChanged<Product> onSelect;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        message: 'No se encontraron productos con ese criterio.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return ProductTile(product: product, onTap: () => onSelect(product));
      },
    );
  }
}
