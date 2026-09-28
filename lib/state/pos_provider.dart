import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/product.dart';

class PosProvider extends ChangeNotifier {
  final List<CartItem> _cart = [];
  String? _selectedCustomerId;

  List<CartItem> get cart => List.unmodifiable(_cart);
  String? get selectedCustomerId => _selectedCustomerId;
  bool get isEmpty => _cart.isEmpty;
  int get itemCount => _cart.fold(0, (sum, item) => sum + item.quantity);
  double get total => _cart.fold(0.0, (sum, item) => sum + item.subtotal);

  void setCustomer(String? customerId) {
    _selectedCustomerId = customerId;
    notifyListeners();
  }

  void addProduct(Product product) {
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
        } else {
          item.quantity--;
        }
        notifyListeners();
        return;
      }
    }
  }

  void removeItem(String productId) {
    _cart.removeWhere((item) => item.product.id == productId);
    notifyListeners();
  }

  void clear() {
    _cart.clear();
    _selectedCustomerId = null;
    notifyListeners();
  }
}
