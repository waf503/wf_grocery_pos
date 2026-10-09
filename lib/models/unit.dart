/// Una unidad de medida (pieza, kg, libra, litro, paquete...).
class Unit {
  Unit({
    required this.id,
    required this.name,
    this.abbreviation,
    this.allowsDecimals = false,
    this.saleStep = 1,
  });

  final String id;
  final String name;
  final String? abbreviation;
  final bool allowsDecimals;

  /// Incremento mínimo de venta (0.5 = de media en media). 1 para enteras.
  final double saleStep;

  /// Lo que se muestra junto a una cantidad: la abreviatura si existe, o el
  /// nombre completo.
  String get label =>
      (abbreviation != null && abbreviation!.isNotEmpty) ? abbreviation! : name;
}
