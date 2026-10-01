/// Una variante vendible, aplanada para el resto de la app (POS, carrito,
/// Dashboard, Reportes). `id` es el id de la VARIANTE real en la base de
/// datos; `familyId`/`familyName`/`presentation`/`categoryId` son datos
/// extra que solo usa el módulo de Inventario para mostrar/editar el
/// producto "padre" al que pertenece — el resto de la app puede seguir
/// ignorándolos y usar `name`/`category` como antes (ya vienen combinados
/// o resueltos por nombre: "Coca-Cola — Lata 355ml", categoría "Bebidas").
class Product {
  Product({
    required this.id,
    required this.familyId,
    required this.familyName,
    required this.presentation,
    required this.name,
    required this.categoryId,
    required this.category,
    required this.unit,
    required this.price,
    required this.cost,
    required this.stock,
    this.minStock = 5,
    this.barcode,
  });

  final String id;
  final String familyId;
  final String familyName;
  final String presentation;
  final String name;
  final String categoryId;
  final String category;
  final String unit;
  final double price;
  final double cost;
  double stock;
  final double minStock;
  final String? barcode;

  bool get isLowStock => stock <= minStock;

  Product copyWith({
    String? presentation,
    String? unit,
    double? price,
    double? cost,
    double? stock,
    double? minStock,
    String? barcode,
  }) {
    final newPresentation = presentation ?? this.presentation;
    return Product(
      id: id,
      familyId: familyId,
      familyName: familyName,
      presentation: newPresentation,
      name: '$familyName — $newPresentation',
      categoryId: categoryId,
      category: category,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      barcode: barcode ?? this.barcode,
    );
  }
}
