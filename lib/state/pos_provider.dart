import 'package:flutter/foundation.dart';

import '../core/money.dart';
import '../models/cart_item.dart';
import '../models/product.dart';

class PosProvider extends ChangeNotifier {
  final List<CartItem> _cart = [];
  String? _selectedCustomerId;

  /// Producto "activo": el último cuya cantidad se tocó (agregar, + o −).
  /// El carrito lo colorea con el color de su categoría como feedback. Es
  /// nulo si ese renglón se eliminó o el carrito se vació.
  ///
  /// `_addSerial` sube solo con `addProduct` y sirve para hacer scroll hasta
  /// el renglón (aunque sea el mismo producto escaneado otra vez).
  String? _activeProductId;
  int _addSerial = 0;

  List<CartItem> get cart => List.unmodifiable(_cart);
  String? get selectedCustomerId => _selectedCustomerId;
  String? get activeProductId => _activeProductId;
  int get addSerial => _addSerial;
  bool get isEmpty => _cart.isEmpty;
  double get itemCount => _cart.fold(0.0, (sum, item) => sum + item.quantity);
  int get totalCents => _cart.fold(0, (sum, item) => sum + item.subtotalCents);
  double get total => fromCents(totalCents);

  void setCustomer(String? customerId) {
    _selectedCustomerId = customerId;
    notifyListeners();
  }

  /// Unidades del producto base (pool) que ya hay en el carrito, sumando todas
  /// sus presentaciones: 2 cajetillas de 20 y 3 sueltas son 43 unidades.
  double poolUnitsInCart(String poolId) {
    var units = 0.0;
    for (final item in _cart) {
      if (item.product.poolId == poolId) units += item.quantity * item.product.poolFactor;
    }
    return units;
  }

  /// Cuánto suman el + / − y un clic: 1 para piezas, o el incremento de la
  /// unidad para productos por peso (0.5 = media libra).
  double _stepOf(Product product) => product.allowsDecimals ? product.quantityStep : 1;

  /// Redondea a milésimas para no arrastrar ruido de punto flotante.
  double _round(double value) => (value * 1000).round() / 1000;

  /// Agrega [quantity] (por defecto un incremento) del producto; si ya está
  /// en el carrito, suma a su renglón.
  void addProduct(Product product, {double? quantity}) {
    final amount = quantity ?? _stepOf(product);
    _activeProductId = product.id;
    _addSerial++;
    for (final item in _cart) {
      if (item.product.id == product.id) {
        item.quantity = _round(item.quantity + amount);
        notifyListeners();
        return;
      }
    }
    _cart.add(CartItem(product: product, quantity: _round(amount)));
    notifyListeners();
  }

  /// Agrega una venta genérica (algo que no está en el inventario). Cada
  /// una es su propio renglón, aunque se repita el nombre.
  void addGeneric({required String name, required int priceCents, int quantity = 1}) {
    final product = Product.generic(name: name, priceCents: priceCents);
    _activeProductId = product.id;
    _addSerial++;
    _cart.add(CartItem(product: product, quantity: quantity.toDouble()));
    notifyListeners();
  }

  void incrementQuantity(String productId) {
    for (final item in _cart) {
      if (item.product.id == productId) {
        item.quantity = _round(item.quantity + _stepOf(item.product));
        _activeProductId = productId;
        notifyListeners();
        return;
      }
    }
  }

  void decrementQuantity(String productId) {
    for (final item in _cart) {
      if (item.product.id == productId) {
        final step = _stepOf(item.product);
        if (item.quantity <= step + 1e-9) {
          _cart.remove(item);
          if (_activeProductId == productId) _activeProductId = null;
        } else {
          item.quantity = _round(item.quantity - step);
          _activeProductId = productId;
        }
        notifyListeners();
        return;
      }
    }
  }

  /// Fija la cantidad exacta de un renglón (p. ej. 2.5 lb). Cero o menos lo quita.
  void setQuantity(String productId, double quantity) {
    if (quantity <= 0) {
      removeItem(productId);
      return;
    }
    for (final item in _cart) {
      if (item.product.id == productId) {
        item.quantity = _round(quantity);
        _activeProductId = productId;
        notifyListeners();
        return;
      }
    }
  }

  void removeItem(String productId) {
    _cart.removeWhere((item) => item.product.id == productId);
    if (_activeProductId == productId) _activeProductId = null;
    notifyListeners();
  }

  void clear() {
    _cart.clear();
    _activeProductId = null;
    _selectedCustomerId = null;
    notifyListeners();
  }
}
