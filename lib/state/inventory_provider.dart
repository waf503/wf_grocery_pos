import 'package:flutter/foundation.dart';

import '../data/mock_data.dart';
import '../models/product.dart';

class InventoryProvider extends ChangeNotifier {
  InventoryProvider() : _products = buildMockProducts();

  final List<Product> _products;

  List<Product> get products => List.unmodifiable(_products);

  List<Product> get lowStockProducts =>
      _products.where((p) => p.isLowStock).toList();

  List<Product> search({String query = '', String? category}) {
    final normalizedQuery = query.trim().toLowerCase();
    return _products.where((p) {
      final matchesCategory = category == null || category == 'Todas' || p.category == category;
      final matchesQuery = normalizedQuery.isEmpty ||
          p.name.toLowerCase().contains(normalizedQuery) ||
          (p.barcode?.contains(normalizedQuery) ?? false);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  Product? byId(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  void addProduct(Product product) {
    _products.add(product);
    notifyListeners();
  }

  void updateProduct(Product updated) {
    final index = _products.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _products[index] = updated;
      notifyListeners();
    }
  }

  void deleteProduct(String id) {
    _products.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void decreaseStock(String productId, int quantity) {
    final product = byId(productId);
    if (product != null) {
      product.stock -= quantity;
      notifyListeners();
    }
  }

  String nextId() => 'p${DateTime.now().millisecondsSinceEpoch}';
}
