import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/inventory_provider.dart';

/// Miniatura del producto. Si no tiene imagen (o aún carga) muestra un ícono
/// neutro del mismo tamaño, para que las filas y tarjetas queden alineadas.
///
/// Por defecto es un cuadrado de [size]; con [width]/[height] puede ser un
/// rectángulo (por ejemplo, ocupar todo el ancho de una tarjeta). Con
/// [BoxFit.contain] la foto se ve completa sobre fondo blanco, sin recortes.
class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    required this.product,
    this.size = 40,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final Product product;
  final double size;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);
    final w = width ?? size;
    final h = height ?? size;
    final iconSize = (h < (w.isFinite ? w : h) ? h : (w.isFinite ? w : h)) * 0.45;
    final placeholder = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: radius),
      child: Icon(Icons.inventory_2_outlined, size: iconSize, color: scheme.onSurfaceVariant),
    );
    if (!product.hasImage) return placeholder;

    return FutureBuilder<Uint8List?>(
      future: context.read<InventoryProvider>().imageFor(product),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return placeholder;
        return ClipRRect(
          borderRadius: radius,
          child: Container(
            width: w,
            height: h,
            color: fit == BoxFit.contain ? Colors.white : null,
            child: Image.memory(
              bytes,
              fit: fit,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder,
            ),
          ),
        );
      },
    );
  }
}
