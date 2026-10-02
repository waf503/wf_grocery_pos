import '../core/money.dart';
import 'product.dart';

class CartItem {
  CartItem({required this.product, this.quantity = 1});

  final Product product;
  int quantity;

  /// El subtotal se calcula en centavos enteros para que el total del
  /// carrito coincida exactamente con el de la venta que se registra.
  int get subtotalCents => product.priceCents * quantity;

  double get subtotal => fromCents(subtotalCents);
}
