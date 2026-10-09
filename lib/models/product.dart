import '../core/money.dart';

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
    this.quantityStep = 1,
    required this.priceCents,
    required this.costCents,
    required this.stock,
    this.minStock = 5,
    this.barcode,
    this.tags = '',
    required this.createdAt,
    required this.updatedAt,
    this.isGeneric = false,
  });

  /// Renglón de VENTA GENÉRICA: algo que no está en el inventario, con el
  /// nombre y el precio que escribe el cajero. No es un producto real (no se
  /// guarda en el inventario ni tiene existencias); solo vive en el carrito.
  factory Product.generic({required String name, required int priceCents}) {
    final now = DateTime.now();
    return Product(
      id: 'generic_${now.microsecondsSinceEpoch}',
      name: name,
      categoryId: '',
      category: 'Varios',
      unitId: '',
      unit: 'pz',
      priceCents: priceCents,
      costCents: 0,
      stock: 0,
      createdAt: now,
      updatedAt: now,
      isGeneric: true,
    );
  }

  final String id;
  final String name;
  final String categoryId;
  final String category;
  final String unitId;

  /// Etiqueta de la unidad (abreviatura o nombre), ya resuelta para mostrar.
  final String unit;
  final bool allowsDecimals;

  /// Incremento mínimo de venta de su unidad (0.5 = de media en media).
  final double quantityStep;

  /// Precio de venta y costo en centavos enteros.
  final int priceCents;
  final int costCents;
  double stock;
  final double minStock;
  final String? barcode;
  final String tags;
  final bool isGeneric;
  final DateTime createdAt;

  /// Última edición del producto; si nunca se editó, su fecha de creación.
  final DateTime updatedAt;

  double get price => fromCents(priceCents);
  double get cost => fromCents(costCents);

  bool get isLowStock => stock <= minStock;
}
