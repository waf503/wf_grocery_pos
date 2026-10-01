import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../core/database/app_database.dart';
import '../features/products/data/product_repository.dart';
import '../models/product.dart';
import '../models/product_family.dart';

/// Estado de la sección de Inventario.
///
/// Delega todo al [ProductRepository] (inyectado por constructor) y
/// mantiene una copia local sincronizada — actualizada sola cada vez que
/// la base de datos cambia, gracias a `watchAllVariants()`.
class InventoryProvider extends ChangeNotifier {
  InventoryProvider(this._repository) {
    _variantsSubscription = _repository.watchAllVariants().listen((rows) {
      _products = rows;
      notifyListeners();
    });
    _familiesSubscription = _repository.watchFamilies().listen((rows) {
      _families = rows;
      notifyListeners();
    });
  }

  final ProductRepository _repository;
  late final StreamSubscription<List<Product>> _variantsSubscription;
  late final StreamSubscription<List<ProductFamily>> _familiesSubscription;

  List<Product> _products = [];
  List<ProductFamily> _families = [];

  List<Product> get products => List.unmodifiable(_products);

  /// Familias existentes, para el `Autocomplete` del formulario de
  /// Inventario (poder reutilizar "Coca-Cola" al agregar una presentación
  /// nueva en vez de crear una familia duplicada).
  List<ProductFamily> get families => List.unmodifiable(_families);

  List<Product> get lowStockProducts =>
      _products.where((p) => p.isLowStock).toList();

  List<Product> search({String query = '', String? category}) {
    final normalizedQuery = query.trim().toLowerCase();
    return _products.where((p) {
      final matchesCategory =
          category == null || category == 'Todas' || p.category == category;
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

  /// Crea una variante nueva, reutilizando la familia si ya existe
  /// (mismo nombre, sin importar mayúsculas/minúsculas) o creándola si no.
  Future<void> addProduct({
    required String familyName,
    required String categoryId,
    required String presentation,
    required String unit,
    required double price,
    required double cost,
    required double stock,
    required double minStock,
    String? barcode,
  }) async {
    final family = await _repository.findOrCreateFamily(
      name: familyName,
      categoryId: categoryId,
    );
    await _repository.addVariant(
      family.id,
      ProductVariantsTableCompanion.insert(
        productId: family.id,
        presentation: presentation,
        unit: unit,
        price: price,
        cost: cost,
        stock: Value(stock),
        minStock: Value(minStock),
        barcode: Value(barcode),
      ),
    );
  }

  Future<void> updateProduct(Product product) {
    return _repository.updateVariant(
      ProductVariantsTableCompanion(
        id: Value(product.id),
        productId: Value(product.familyId),
        presentation: Value(product.presentation),
        unit: Value(product.unit),
        price: Value(product.price),
        cost: Value(product.cost),
        stock: Value(product.stock),
        minStock: Value(product.minStock),
        barcode: Value(product.barcode),
      ),
    );
  }

  Future<void> deleteProduct(String id) {
    return _repository.deleteVariant(id);
  }

  Future<void> decreaseStock(String productId, double quantity) {
    return _repository.decreaseStock(productId, quantity);
  }

  @override
  void dispose() {
    _variantsSubscription.cancel();
    _familiesSubscription.cancel();
    super.dispose();
  }
}
