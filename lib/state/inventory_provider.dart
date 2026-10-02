import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../core/barcode/internal_barcode.dart';
import '../core/database/app_database.dart';
import '../core/text/product_tags.dart';
import '../features/products/data/product_repository.dart';
import '../models/product.dart';

/// Estado de la sección de Inventario.
///
/// Delega todo al [ProductRepository] (inyectado por constructor) y
/// mantiene una copia local sincronizada — actualizada sola cada vez que
/// la base de datos cambia, gracias a `watchAll()`.
class InventoryProvider extends ChangeNotifier {
  InventoryProvider(this._repository) {
    _subscription = _repository.watchAll().listen((rows) {
      _products = rows;
      notifyListeners();
    });
  }

  final ProductRepository _repository;
  late final StreamSubscription<List<Product>> _subscription;

  List<Product> _products = [];

  List<Product> get products => List.unmodifiable(_products);

  List<Product> get lowStockProducts =>
      _products.where((p) => p.isLowStock).toList();

  /// Búsqueda por nombre, tags o código de barras (sin importar mayúsculas
  /// ni acentos).
  List<Product> search({String query = '', String? category}) {
    final normalizedQuery = normalizeText(query.trim());
    return _products.where((p) {
      final matchesCategory =
          category == null || category == 'Todas' || p.category == category;
      final matchesQuery = normalizedQuery.isEmpty ||
          normalizeText(p.name).contains(normalizedQuery) ||
          p.tags.contains(normalizedQuery) ||
          (p.barcode?.contains(query.trim()) ?? false);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  /// Productos ya ingresados que coinciden con lo que el usuario está
  /// escribiendo: cada palabra tecleada debe ser el comienzo de algún tag
  /// ("coca" → "Coca-Cola Lata 355ml"). Como los tags viven en el propio
  /// producto, al borrar un producto desaparece su sugerencia.
  List<Product> suggestionsFor(String text, {int limit = 6}) {
    final typed = tokenize(text);
    if (typed.isEmpty) return const [];
    final matches = _products.where((p) {
      final tags = p.tags.split(' ');
      return typed.every((word) => tags.any((tag) => tag.startsWith(word)));
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return matches.take(limit).toList();
  }

  /// Código EAN-13 interno libre, para productos o packs sin código físico.
  String generateInternalBarcode() {
    return buildInternalBarcode(nextInternalSequence(_products.map((p) => p.barcode)));
  }

  /// `true` si otro producto (distinto de [exceptId]) ya usa ese código.
  bool isBarcodeTaken(String code, {String? exceptId}) {
    return _products.any((p) => p.barcode == code && p.id != exceptId);
  }

  Product? byId(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> addProduct({
    required String name,
    required String categoryId,
    required String unitId,
    required int priceCents,
    required int costCents,
    required double stock,
    required double minStock,
    String? barcode,
    String extraTags = '',
  }) {
    return _repository.add(
      ProductsTableCompanion.insert(
        name: name.trim(),
        categoryId: categoryId,
        unitId: unitId,
        priceCents: priceCents,
        costCents: costCents,
        stock: Value(stock),
        minStock: Value(minStock),
        barcode: Value(barcode),
        tags: Value(buildTags(name, extra: extraTags)),
      ),
    );
  }

  Future<void> updateProduct({
    required String id,
    required String name,
    required String categoryId,
    required String unitId,
    required int priceCents,
    required int costCents,
    required double stock,
    required double minStock,
    String? barcode,
    String extraTags = '',
  }) {
    return _repository.update(
      ProductsTableCompanion(
        id: Value(id),
        name: Value(name.trim()),
        categoryId: Value(categoryId),
        unitId: Value(unitId),
        priceCents: Value(priceCents),
        costCents: Value(costCents),
        stock: Value(stock),
        minStock: Value(minStock),
        barcode: Value(barcode),
        tags: Value(buildTags(name, extra: extraTags)),
      ),
    );
  }

  Future<void> deleteProduct(String id) => _repository.delete(id);

  Future<void> deleteProducts(Iterable<String> ids) async {
    for (final id in ids) {
      await _repository.delete(id);
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
