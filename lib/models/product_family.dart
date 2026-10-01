/// El concepto general de un producto (ej. "Coca-Cola"), sin presentación.
/// Solo lo usa el módulo de Inventario para agrupar variantes; el resto de
/// la app (POS, carrito, Dashboard) sigue trabajando con [Product]
/// (definido en `product.dart`), que representa la variante ya aplanada.
class ProductFamily {
  ProductFamily({
    required this.id,
    required this.name,
    required this.categoryId,
    this.brand,
  });

  final String id;
  final String name;
  final String categoryId;
  final String? brand;

  @override
  String toString() => name;
}
