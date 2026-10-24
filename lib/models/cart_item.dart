import '../core/money.dart';
import '../core/pricing.dart';
import 'product.dart';

class CartItem {
  CartItem({required this.product, this.quantity = 1});

  final Product product;
  double quantity;

  /// El subtotal se calcula en centavos enteros para que el total del
  /// carrito coincida exactamente con el de la venta que se registra.
  /// Aplica los combos del producto (ej. 2 por $0.25) de la forma más barata.
  int get subtotalCents => comboSubtotalCents(
        quantity: quantity,
        unitPriceCents: product.priceCents,
        combos: product.combos,
      );

  /// Lo que se ahorra el cliente por los combos (0 si no aplica ninguno).
  int get savingsCents => comboSavingsCents(
        quantity: quantity,
        unitPriceCents: product.priceCents,
        combos: product.combos,
      );

  double get subtotal => fromCents(subtotalCents);
}
