class Product {
  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.price,
    required this.cost,
    required this.stock,
    this.minStock = 5,
    this.barcode,
  });

  final String id;
  final String name;
  final String category;
  final String unit;
  final double price;
  final double cost;
  int stock;
  final int minStock;
  final String? barcode;

  bool get isLowStock => stock <= minStock;

  Product copyWith({
    String? name,
    String? category,
    String? unit,
    double? price,
    double? cost,
    int? stock,
    int? minStock,
    String? barcode,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      barcode: barcode ?? this.barcode,
    );
  }
}
