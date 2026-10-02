import 'package:flutter/foundation.dart';

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
  int get itemCount => _cart.fold(0, (sum, item) => sum + item.quantity);
  double get total => _cart.fold(0.0, (sum, item) => sum + item.subtotal);

  void setCustomer(String? customerId) {
    _selectedCustomerId = customerId;
    notifyListeners();
  }

  void addProduct(Product product) {
    _activeProductId = product.id;
    _addSerial++;
    for (final item in _cart) {
      if (item.product.id == product.id) {
        item.quantity++;
        notifyListeners();
        return;
      }
    }
    _cart.add(CartItem(product: product));
    notifyListeners();
  }

  void incrementQuantity(String productId) {
    for (final item in _cart) {
      if (item.product.id == productId) {
        item.quantity++;
        _activeProductId = productId;
        notifyListeners();
        return;
      }
    }
  }

  void decrementQuantity(String productId) {
    for (final item in _cart) {
      if (item.product.id == productId) {
        if (item.quantity <= 1) {
          _cart.remove(item);
          if (_activeProductId == productId) _activeProductId = null;
        } else {
          item.quantity--;
          _activeProductId = productId;
        }
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
