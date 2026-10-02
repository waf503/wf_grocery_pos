/// Un producto vendible, tal como lo ve toda la app (Inventario, POS,
/// carrito, Dashboard, Reportes). El `name` ya incluye la presentación
/// ("Coca-Cola Lata 355ml"); `category` es el nombre resuelto de la
/// categoría, y `tags` son las palabras normalizadas que se usan para
/// sugerir nombres al escribir.
class Product {
  Product({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.category,
    required this.unitId,
    required this.unit,
    this.allowsDecimals = false,
    required this.price,
    required this.cost,
    required this.stock,
    this.minStock = 5,
    this.barcode,
    this.tags = '',
  });

  final String id;
  final String name;
  final String categoryId;
  final String category;
  final String unitId;

  /// Etiqueta de la unidad (abreviatura o nombre), ya resuelta para mostrar.
  final String unit;
  final bool allowsDecimals;
  final double price;
  final double cost;
  double stock;
  final double minStock;
  final String? barcode;
  final String tags;

  bool get isLowStock => stock <= minStock;
}
