import '../models/product_combo.dart';

/// Total en centavos de vender [quantity] unidades a [unitPriceCents] cada una,
/// aprovechando los [combos] de la forma MÁS BARATA para el cliente.
///
/// Ejemplo: unidad a 15¢ y combo "2 por 25¢". Para 5 unidades: 2 combos (50¢)
/// + 1 suelta (15¢) = 65¢, en vez de 75¢. Se calcula con programación dinámica
/// (el mínimo entre sumar una unidad suelta o cerrar un combo), así funciona
/// también con varios combos (2x, 5x...) sin depender del orden.
///
/// Si [quantity] no es un número entero (productos por peso) o no hay combos,
/// es simplemente `cantidad × precio`.
int comboSubtotalCents({
  required double quantity,
  required int unitPriceCents,
  required List<ProductCombo> combos,
}) {
  final plain = (quantity * unitPriceCents).round();
  if (combos.isEmpty || quantity < 2 || quantity != quantity.roundToDouble()) return plain;

  final units = quantity.round();
  // best[i] = lo mínimo que cuestan i unidades.
  final best = List<int>.filled(units + 1, 0);
  for (var i = 1; i <= units; i++) {
    var cost = best[i - 1] + unitPriceCents;
    for (final combo in combos) {
      if (combo.quantity >= 2 && combo.quantity <= i) {
        final withCombo = best[i - combo.quantity] + combo.priceCents;
        if (withCombo < cost) cost = withCombo;
      }
    }
    best[i] = cost;
  }
  return best[units];
}

/// Cuánto se ahorra el cliente gracias a los combos (0 si no aplican).
int comboSavingsCents({
  required double quantity,
  required int unitPriceCents,
  required List<ProductCombo> combos,
}) {
  final plain = (quantity * unitPriceCents).round();
  return plain - comboSubtotalCents(quantity: quantity, unitPriceCents: unitPriceCents, combos: combos);
}
