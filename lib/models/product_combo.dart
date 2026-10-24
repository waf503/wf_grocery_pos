/// Promoción por cantidad: [quantity] unidades por [priceCents] en total
/// (ej. 2 bolsas de agua por $0.25 aunque cada una cueste $0.15).
class ProductCombo {
  const ProductCombo({required this.quantity, required this.priceCents});

  final int quantity;

  /// Precio de todo el combo, en centavos.
  final int priceCents;

  @override
  bool operator ==(Object other) =>
      other is ProductCombo && other.quantity == quantity && other.priceCents == priceCents;

  @override
  int get hashCode => Object.hash(quantity, priceCents);
}

/// Una presentación de un producto base, tal como se captura en el formulario:
/// "Cajetilla" que contiene 20 unidades y se vende a $1.75. Comparte las
/// existencias del producto base (que se llevan en la unidad más pequeña).
class PresentationDraft {
  const PresentationDraft({
    this.id,
    required this.name,
    required this.unitsPerPack,
    required this.priceCents,
    this.costCents,
    this.barcode,
    this.combos = const [],
  });

  /// Nulo si es nueva; si ya existe, su id (para actualizarla, no duplicarla).
  final String? id;
  final String name;

  /// Cuántas unidades BASE contiene (ya multiplicado: un paquete de 20
  /// cajetillas de 20 unidades contiene 400).
  final int unitsPerPack;
  final int priceCents;

  /// Costo de la presentación; nulo = unidades × costo del producto base.
  final int? costCents;
  final String? barcode;
  final List<ProductCombo> combos;
}
