import '../core/money.dart';
import 'product_combo.dart';

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
    this.hasImage = false,
    this.imageSourceId,
    this.baseProductId,
    this.unitsPerPack = 1,
    this.combos = const [],
    double? poolUnits,
  }) : poolUnits = poolUnits ?? stock * unitsPerPack;

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

  /// Si es una PRESENTACIÓN (cajetilla, paquete...), el id de su producto
  /// base; sus [stock] y [minStock] están DERIVADOS de las existencias del
  /// base (cuántas presentaciones completas caben). Nulo en productos normales.
  final String? baseProductId;

  /// Cuántas unidades del POOL contiene una de este producto o presentación.
  /// El pool son las existencias del grupo, guardadas en la unidad más
  /// PEQUEÑA de todas (ej. cigarros sueltos): un paquete de 200 cigarros vale
  /// 200, una cajetilla de 20 vale 20 y el cigarro suelto vale 1. Cualquiera
  /// puede ser el producto "base" (el que guarda las existencias), incluso el
  /// más grande. 1 en un producto normal.
  final double unitsPerPack;

  /// Existencias del grupo completo, en unidades del pool (la unidad más
  /// pequeña), sin importar de cuál presentación se pregunte. [stock] es lo
  /// mismo pero medido en ESTA presentación (solo las completas).
  final double poolUnits;

  /// Promociones por cantidad (ej. 2 por $0.25).
  final List<ProductCombo> combos;

  bool get isPresentation => baseProductId != null;

  /// El producto cuyas existencias se descuentan al vender éste (él mismo, o
  /// su producto base si es una presentación).
  String get poolId => baseProductId ?? id;

  /// Cuántas unidades del pool consume vender UNA de éste.
  double get poolFactor => unitsPerPack <= 0 ? 1 : unitsPerPack;

  /// `true` si tiene miniatura (se pide con `InventoryProvider.imageFor`). Una
  /// presentación NO tiene la suya: comparte la del producto base, así que es
  /// `true` cuando el base la tiene.
  final bool hasImage;

  /// El producto que guarda la miniatura que se muestra: él mismo (nulo) o, en
  /// una presentación, su producto base.
  final String? imageSourceId;
  final DateTime createdAt;

  /// Última edición del producto; si nunca se editó, su fecha de creación.
  final DateTime updatedAt;

  double get price => fromCents(priceCents);
  double get cost => fromCents(costCents);

  bool get isLowStock => stock <= minStock;
}
