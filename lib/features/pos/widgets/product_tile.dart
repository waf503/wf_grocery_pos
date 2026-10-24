import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../models/product.dart';
import '../../../shared/widgets/product_thumbnail.dart';

/// Tarjeta de producto del POS. Siempre tiene la misma estructura, con o sin
/// imagen, para que la cuadrícula quede alineada:
/// imagen (zona fija) → nombre (2 líneas) → precio y existencias.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.onTap,
    required this.categoryColor,
  });

  final Product product;
  final VoidCallback? onTap;

  /// Color de la categoría del producto: tiñe la tarjeta y pinta su franja
  /// superior, para reconocer la categoría de un vistazo.
  final Color categoryColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final outOfStock = product.stock <= 0;

    return Opacity(
      opacity: outOfStock ? 0.55 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        color: Color.alphaBlend(categoryColor.withValues(alpha: 0.14), scheme.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: categoryColor.withValues(alpha: 0.55)),
        ),
        child: InkWell(
          onTap: outOfStock ? null : onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: categoryColor, width: 6)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // La zona de imagen ocupa el alto que sobra (la foto completa
                  // sobre fondo blanco, o un ícono si no tiene), así que la tarjeta
                  // se ve igual con o sin imagen y en cualquier ancho de columna.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => ProductThumbnail(
                        product: product,
                        width: double.infinity,
                        height: box.maxHeight,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Dos líneas reservadas siempre, aunque el nombre sea corto.
                  SizedBox(
                    height: 38,
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatCurrency(product.price),
                        style: textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          outOfStock
                              ? 'Agotado'
                              : product.isPresentation
                                  ? '${formatQuantity(product.stock)} disp.'
                                  : '${formatQuantity(product.stock)} ${product.unit}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: outOfStock ? scheme.error : scheme.onSurfaceVariant,
                            fontWeight: outOfStock ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
