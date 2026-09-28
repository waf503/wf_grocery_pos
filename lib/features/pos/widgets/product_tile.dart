import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../models/product.dart';

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap});

  final Product product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outOfStock = product.stock <= 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: outOfStock ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                formatCurrency(product.price),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                outOfStock ? 'Sin existencias' : '${product.stock} ${product.unit} disp.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: outOfStock ? scheme.error : scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
